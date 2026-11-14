import AVFoundation
import Foundation
import Network
import Observation

/// Proxy mode: the engine runs inside the app as a SOCKS5 server on
/// 127.0.0.1 and a VPN client from the App Store (sing-box) feeds traffic
/// into it. No Network Extension, so it works with a free Apple ID.
@Observable
@MainActor
final class ProxyController {
    enum State: Equatable {
        case stopped, starting, running
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var startedAt: Date?
    private(set) var network: NetworkKind = .other
    private(set) var interfaceName: String?
    private(set) var activeStrategyID: String?
    /// Port the engine actually listens on (may differ from the preferred one).
    private(set) var activePort: Int?
    private(set) var restarts = 0

    @ObservationIgnored private let engine = EngineRunner.shared
    @ObservationIgnored private let keepAlive = BackgroundKeepAlive()
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var config = AppConfig()
    @ObservationIgnored private var pendingRestart: Task<Void, Never>?

    var isRunning: Bool { state == .running }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    init() {
        startMonitor()
    }

    func start(config: AppConfig) async {
        guard state != .starting else { return }
        self.config = config
        state = .starting
        Log.rotateIfNeeded(Paths.engineLog, limit: 1024 * 1024)
        zdpi_redirect_stderr(Paths.engineLog.path)
        do {
            try await launchEngine()
            if config.keepAliveAudio {
                do { try keepAlive.start() } catch {
                    Log.write("keep-alive audio failed: \(error.localizedDescription)")
                }
            }
            startedAt = Date()
            state = .running
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        pendingRestart?.cancel()
        keepAlive.stop()
        let engine = self.engine
        await Task.detached { engine.stop() }.value
        startedAt = nil
        activeStrategyID = nil
        activePort = nil
        state = .stopped
        Log.write("proxy: stopped")
    }

    /// Applies a new configuration to the running engine.
    func reload(config: AppConfig) async {
        let old = self.config
        self.config = config
        guard isRunning else { return }
        if old.keepAliveAudio != config.keepAliveAudio {
            if config.keepAliveAudio { try? keepAlive.start() } else { keepAlive.stop() }
        }
        await restart(reason: "config")
    }

    private func restart(reason: String) async {
        let engine = self.engine
        await Task.detached { engine.stop() }.value
        do {
            try await launchEngine()
            restarts += 1
            Log.write("proxy: engine restarted (\(reason))")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func launchEngine() async throws {
        let strategy = StrategyCatalog.strategy(id: config.strategyID(for: network), config: config)
        let files = ListStore.prepareEngineFiles(config: config)
        let engine = self.engine
        var ports = [activePort ?? config.proxyPort]
        ports += EngineArgs.proxyPorts.filter { !ports.contains($0) }
        for port in ports {
            let args = EngineArgs.build(config: config, strategy: strategy, files: files, port: port)
            do {
                try await Task.detached { try engine.start(args: args) }.value
            } catch EngineRunner.EngineError.exited(-5) {
                Log.write("proxy: port \(port) is busy, trying next")
                continue
            }
            activePort = port
            activeStrategyID = strategy.id
            Log.write("proxy: engine on 127.0.0.1:\(port), strategy=\(strategy.id), network=\(network.rawValue), iface=\(interfaceName ?? "—")")
            return
        }
        throw PortsBusyError()
    }

    struct PortsBusyError: LocalizedError {
        var errorDescription: String? {
            let ports = EngineArgs.proxyPorts
            return "Порты \(ports.first!)–\(ports.last!) заняты другим приложением. Закройте другие VPN- и прокси-клиенты (кроме sing-box) и попробуйте снова."
        }
    }

    // MARK: - Physical interface tracking

    private func startMonitor() {
        // Excluding .other hides utun interfaces of the VPN client, so the
        // path always describes the real Wi-Fi / cellular link.
        let monitor = NWPathMonitor(prohibitedInterfaceTypes: [.other, .loopback])
        monitor.pathUpdateHandler = { [weak self] path in
            let iface = path.availableInterfaces.first { path.usesInterfaceType($0.type) }
                ?? path.availableInterfaces.first
            let kind: NetworkKind
            switch iface?.type {
            case .wifi?, .wiredEthernet?: kind = .wifi
            case .cellular?: kind = .cellular
            default: kind = .other
            }
            let index = iface.map { UInt32($0.index) } ?? 0
            let name = iface?.name
            Task { @MainActor in self?.pathChanged(kind: kind, index: index, name: name) }
        }
        monitor.start(queue: DispatchQueue(label: "zapret.proxy.path"))
        self.monitor = monitor
    }

    private func pathChanged(kind: NetworkKind, index: UInt32, name: String?) {
        // Applies to new connections immediately, no restart required.
        zdpi_set_bound_interface(index)
        interfaceName = name
        guard kind != network else { return }
        let old = network
        network = kind
        guard isRunning, old != .other else { return }
        Log.write("proxy: network \(old.rawValue) → \(kind.rawValue)")
        pendingRestart?.cancel()
        pendingRestart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.restart(reason: "network \(kind.rawValue)")
        }
    }
}

/// Keeps the app alive in the background by playing silence (mixed with
/// other audio, so music from other apps is not interrupted).
final class BackgroundKeepAlive {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var observers: [NSObjectProtocol] = []
    private(set) var isActive = false

    func start() throws {
        guard !isActive else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050) else { return }
        buffer.frameLength = 22_050 // zero-filled: one second of silence
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = 0
        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()

        self.engine = engine
        self.player = player
        isActive = true
        observe()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        isActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.restart()
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.restart()
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            self?.restart()
        })
    }

    private func restart() {
        guard isActive else { return }
        stop()
        try? start()
    }
}
