import Foundation
import Network
import Observation

/// Root state. Owns both engines (VPN tunnel / in-app proxy), the tester and
/// the updater, and keeps config.json in sync with the extension.
@Observable
@MainActor
final class AppModel {
    var config: AppConfig {
        didSet {
            guard config != oldValue else { return }
            ConfigStore.save(config)
            configChanged(from: oldValue)
        }
    }

    let tunnel = TunnelManager()
    let proxy = ProxyController()
    let updates = UpdateChecker()
    let tester = StrategyTester()

    private(set) var localNetwork: NetworkKind = .other
    private(set) var listsMeta = ListStore.loadMeta()
    private(set) var updatingLists = false
    var listsMessage: String?

    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private let monitor = NWPathMonitor(prohibitedInterfaceTypes: [.other, .loopback])

    init() {
        config = ConfigStore.load()
        ListStore.ensureInstalled()
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: NetworkKind
            if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                kind = .wifi
            } else if path.usesInterfaceType(.cellular) {
                kind = .cellular
            } else {
                kind = .other
            }
            Task { @MainActor in self?.localNetwork = kind }
        }
        monitor.start(queue: DispatchQueue(label: "zapret.app.path"))
    }

    // MARK: - Unified control

    var mode: RunMode { AppEdition.isLite ? .proxy : config.mode }

    var isOn: Bool {
        mode == .vpn ? tunnel.isConnected : proxy.isRunning
    }

    var isTransitioning: Bool {
        mode == .vpn ? (tunnel.isTransitioning || tunnel.isBusy) : proxy.state == .starting
    }

    var errorMessage: String? {
        mode == .vpn ? (tunnel.lastError ?? tunnel.tunnelStatus?.lastError) : proxy.errorMessage
    }

    var currentNetwork: NetworkKind {
        if mode == .vpn, let status = tunnel.tunnelStatus { return status.network }
        if mode == .proxy, proxy.network != .other { return proxy.network }
        return localNetwork
    }

    var activeStrategyID: String {
        let running = mode == .vpn ? tunnel.tunnelStatus?.strategyID : proxy.activeStrategyID
        return running ?? config.strategyID(for: currentNetwork)
    }

    var startedAt: Date? {
        mode == .vpn ? tunnel.tunnelStatus?.startedAt : proxy.startedAt
    }

    func toggle() async {
        if isOn || isTransitioning {
            await turnOff()
        } else {
            await turnOn()
        }
    }

    func turnOn() async {
        switch mode {
        case .vpn: await tunnel.connect(config: config)
        case .proxy: await proxy.start(config: config)
        }
    }

    func turnOff() async {
        switch mode {
        case .vpn: await tunnel.disconnect()
        case .proxy: await proxy.stop()
        }
    }

    // MARK: - Strategies

    func strategyID(for kind: NetworkKind) -> String {
        kind == .cellular ? config.cellularStrategyID : config.wifiStrategyID
    }

    func setStrategy(_ id: String, for kind: NetworkKind) {
        if kind == .cellular {
            config.cellularStrategyID = id
            if !config.separateCellularProfile { config.wifiStrategyID = id }
        } else {
            config.wifiStrategyID = id
        }
    }

    // MARK: - Tester

    /// Stops whatever is running, runs the tester, then restores the previous state.
    func runTester(mode testMode: StrategyTester.Mode) async {
        let wasOn = isOn
        let runMode = mode
        if wasOn {
            switch runMode {
            case .vpn: await tunnel.disconnectAndWait()
            case .proxy: await proxy.stop()
            }
        }
        tester.onFinish = { [weak self] in
            guard let self, wasOn else { return }
            Task { await self.turnOn() }
        }
        tester.start(mode: testMode, config: config)
    }

    // MARK: - Config propagation

    private func configChanged(from old: AppConfig) {
        let modeChanged = old.mode != config.mode
        let onDemandChanged = old.onDemand != config.onDemand
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            if modeChanged {
                // Switching modes: stop the engine of the previous mode.
                if old.mode == .vpn { await self.tunnel.disconnect() } else { await self.proxy.stop() }
                return
            }
            if onDemandChanged { await self.tunnel.applyOnDemand(config: self.config) }
            switch self.mode {
            case .vpn: await self.tunnel.reload()
            case .proxy: await self.proxy.reload(config: self.config)
            }
        }
    }

    // MARK: - Lists

    func updateLists() async {
        updatingLists = true
        defer { updatingLists = false }
        let result = await ListStore.updateFromUpstream()
        listsMeta = ListStore.loadMeta()
        switch result {
        case .success(let n):
            listsMessage = "Обновлено файлов: \(n)"
            reloadEngine()
        case .failure(let error):
            listsMessage = "Ошибка обновления: \(error.localizedDescription)"
        }
    }

    func userListChanged() {
        listsMeta = ListStore.loadMeta()
        reloadEngine()
    }

    private func reloadEngine() {
        Task {
            switch mode {
            case .vpn: await tunnel.reload()
            case .proxy: await proxy.reload(config: config)
            }
        }
    }
}
