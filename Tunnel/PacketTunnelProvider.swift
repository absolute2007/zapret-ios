import CoreTelephony
import Foundation
import Network
import NetworkExtension

/// tun (iOS) → hev-socks5-tunnel (lwIP) → 127.0.0.1 SOCKS5 → byedpi (desync) → Internet
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let engine = EngineRunner()
    private let controlQueue = DispatchQueue(label: "zapret.tunnel.control")
    private var hevThread: Thread?
    private var pathMonitor: NWPathMonitor?
    private var pendingNetworkChange: DispatchWorkItem?
    private var listsTimer: DispatchSourceTimer?

    private var config = AppConfig()
    private var network: NetworkKind = .other
    private var startedAt = Date()
    private var restarts = 0
    private var lastError: String?
    private var enginePort = EngineArgs.tunnelPort
    private var activeStrategyID = StrategyCatalog.defaultWifi

    // MARK: - Lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Log.rotateIfNeeded(Paths.engineLog, limit: 1024 * 1024)
        Log.rotateIfNeeded(Paths.hevLog, limit: 1024 * 1024)
        zdpi_redirect_stderr(Paths.engineLog.path)

        config = ConfigStore.load()
        network = PacketTunnelProvider.currentNetworkKind()
        startedAt = Date()
        Log.write("start: v\(AppIdentity.appVersion) (\(AppIdentity.buildNumber)), network=\(network.rawValue), group=\(AppIdentity.appGroupID), shared=\(Paths.hasSharedContainer)")

        setTunnelNetworkSettings(makeNetworkSettings()) { [weak self] error in
            guard let self else { return }
            if let error {
                Log.write("setTunnelNetworkSettings failed: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            self.controlQueue.async {
                do {
                    try self.startEngine()
                    try self.startTun2Socks()
                    self.startPathMonitor()
                    self.scheduleListsUpdates()
                    Log.write("tunnel is up, strategy=\(self.activeStrategyID)")
                    completionHandler(nil)
                } catch {
                    Log.write("start failed: \(error.localizedDescription)")
                    self.lastError = error.localizedDescription
                    self.engine.stop()
                    completionHandler(error)
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        Log.write("stop: reason=\(reason.rawValue)")
        pathMonitor?.cancel()
        pathMonitor = nil
        listsTimer?.cancel()
        listsTimer = nil
        controlQueue.async {
            hev_socks5_tunnel_quit()
            self.engine.stop()
            completionHandler()
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
        // Sockets may be stale after a long sleep; let the path monitor decide.
    }

    // MARK: - App messages

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let request = try? JSONDecoder().decode(TunnelRequest.self, from: messageData) else {
            completionHandler?(nil)
            return
        }
        switch request.command {
        case .status:
            completionHandler?(try? JSONEncoder().encode(status()))
        case .reload:
            controlQueue.async {
                self.reload()
                completionHandler?(try? JSONEncoder().encode(self.status()))
            }
        }
    }

    private func status() -> TunnelStatus {
        var tx = 0, txb = 0, rx = 0, rxb = 0
        hev_socks5_tunnel_stats(&tx, &txb, &rx, &rxb)
        return TunnelStatus(network: network,
                            radio: PacketTunnelProvider.radioTechnology(),
                            strategyID: activeStrategyID,
                            engineRunning: engine.isRunning,
                            startedAt: startedAt,
                            txBytes: UInt64(txb),
                            rxBytes: UInt64(rxb),
                            restarts: restarts,
                            lastError: lastError)
    }

    private func reload() {
        let old = config
        config = ConfigStore.load()
        Log.write("reload requested")
        let needsNetworkSettings = old.dns != config.dns || old.ipv6 != config.ipv6
        if needsNetworkSettings {
            let sem = DispatchSemaphore(value: 0)
            setTunnelNetworkSettings(makeNetworkSettings()) { error in
                if let error { Log.write("network settings update failed: \(error.localizedDescription)") }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 10)
        }
        restartEngine(reason: "config reload")
    }

    // MARK: - Engine

    /// - Parameter ports: candidate ports. On first start any free port from the
    ///   range is fine; on restart tun2socks is already bound to `enginePort`.
    private func startEngine(ports: [Int] = Array(EngineArgs.tunnelPortRange)) throws {
        let strategy = StrategyCatalog.strategy(id: config.strategyID(for: network), config: config)
        let files = ListStore.prepareEngineFiles(config: config)
        var lastFailure: Error?
        for port in ports {
            let args = EngineArgs.build(config: config, strategy: strategy, files: files, port: port)
            do {
                try engine.start(args: args)
                enginePort = port
                activeStrategyID = strategy.id
                lastError = nil
                Log.write("engine: strategy=\(strategy.id) network=\(network.rawValue) port=\(port)")
                if config.verboseLog { Log.write("engine args: " + args.joined(separator: " ")) }
                return
            } catch EngineRunner.EngineError.exited(-5) {
                lastFailure = EngineRunner.EngineError.exited(-5)
                usleep(200_000)
                continue
            } catch {
                lastFailure = error
                break
            }
        }
        throw lastFailure ?? EngineRunner.EngineError.timeout
    }

    private func restartEngine(reason: String) {
        engine.stop()
        do {
            // Same port every attempt: tun2socks keeps pointing at it.
            try startEngine(ports: Array(repeating: enginePort, count: 5))
            restarts += 1
            Log.write("engine restarted (\(reason))")
        } catch {
            lastError = error.localizedDescription
            Log.write("engine restart failed: \(error.localizedDescription)")
        }
    }

    // MARK: - tun2socks

    private var tunnelFileDescriptor: Int32? {
        // KVC on packetFlow ("socket.fileDescriptor") can throw an ObjC
        // exception on newer iOS, so scan for the utun control socket instead.
        let fd = zapret_find_tun_fd()
        return fd >= 0 ? fd : nil
    }

    private func startTun2Socks() throws {
        guard let fd = tunnelFileDescriptor else {
            throw NSError(domain: "Zapret", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не найден дескриптор utun"])
        }
        let yaml = """
        tunnel:
          mtu: 1500
        socks5:
          port: \(enginePort)
          address: 127.0.0.1
          udp: 'udp'
          udp-address: 127.0.0.1
        misc:
          task-stack-size: 24576
          tcp-buffer-size: 4096
          max-session-count: 1200
          connect-timeout: 10000
          tcp-read-write-timeout: 300000
          udp-read-write-timeout: 60000
          log-file: \(Paths.hevLog.path)
          log-level: \(config.verboseLog ? "info" : "warn")
        """
        let thread = Thread {
            let data = Array(yaml.utf8)
            let code = data.withUnsafeBufferPointer { buf in
                hev_socks5_tunnel_main_from_str(buf.baseAddress, UInt32(buf.count), fd)
            }
            Log.write("tun2socks exited with code \(code)")
        }
        thread.name = "zapret.tun2socks"
        thread.stackSize = 1 << 20
        thread.qualityOfService = .userInitiated
        thread.start()
        hevThread = thread
    }

    // MARK: - Network settings

    private func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1500

        let v4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        v4.includedRoutes = [NEIPv4Route.default()]
        v4.excludedRoutes = [
            ("10.0.0.0", "255.0.0.0"),
            ("100.64.0.0", "255.192.0.0"),
            ("127.0.0.0", "255.0.0.0"),
            ("169.254.0.0", "255.255.0.0"),
            ("172.16.0.0", "255.240.0.0"),
            ("192.168.0.0", "255.255.0.0"),
            ("224.0.0.0", "240.0.0.0"),
        ].map { NEIPv4Route(destinationAddress: $0.0, subnetMask: $0.1) }
        settings.ipv4Settings = v4

        if config.ipv6 {
            let v6 = NEIPv6Settings(addresses: ["fd66:f83a:c650::1"], networkPrefixLengths: [120])
            v6.includedRoutes = [NEIPv6Route.default()]
            v6.excludedRoutes = [
                NEIPv6Route(destinationAddress: "fe80::", networkPrefixLength: 10),
                NEIPv6Route(destinationAddress: "fc00::", networkPrefixLength: 7),
                NEIPv6Route(destinationAddress: "ff00::", networkPrefixLength: 8),
            ]
            settings.ipv6Settings = v6
        }

        let preset = config.dns
        if let url = preset.dohURL {
            let doh = NEDNSOverHTTPSSettings(servers: preset.servers)
            doh.serverURL = url
            doh.matchDomains = [""]
            settings.dnsSettings = doh
        } else if !preset.servers.isEmpty {
            let dns = NEDNSSettings(servers: preset.servers)
            dns.matchDomains = [""]
            settings.dnsSettings = dns
        }
        return settings
    }

    // MARK: - Network changes (Wi-Fi ⇄ cellular)

    private func startPathMonitor() {
        let monitor = Network.NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePath(path)
        }
        monitor.start(queue: controlQueue)
        pathMonitor = monitor
    }

    private func handlePath(_ path: Network.NWPath) {
        guard path.status == .satisfied else { return }
        let kind = PacketTunnelProvider.kind(of: path)
        guard kind != network else { return }

        pendingNetworkChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let old = self.network
            self.network = kind
            Log.write("network changed: \(old.rawValue) → \(kind.rawValue)")
            // Always restart: the per-IP strategy cache learned on another
            // network (other DPI) is not valid here.
            self.restartEngine(reason: "network \(kind.rawValue)")
        }
        pendingNetworkChange = work
        controlQueue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private static func kind(of path: Network.NWPath) -> NetworkKind {
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.availableInterfaces.contains(where: { $0.type == .cellular }) { return .cellular }
        if path.availableInterfaces.contains(where: { $0.type == .wifi || $0.type == .wiredEthernet }) { return .wifi }
        return .other
    }

    static func currentNetworkKind() -> NetworkKind {
        let monitor = Network.NWPathMonitor()
        let sem = DispatchSemaphore(value: 0)
        var result: NetworkKind = .other
        monitor.pathUpdateHandler = { path in
            result = kind(of: path)
            sem.signal()
        }
        monitor.start(queue: DispatchQueue(label: "zapret.path.once"))
        _ = sem.wait(timeout: .now() + 1)
        monitor.cancel()
        return result
    }

    static func radioTechnology() -> String? {
        let info = CTTelephonyNetworkInfo()
        guard let tech = info.serviceCurrentRadioAccessTechnology?.values.first else { return nil }
        if #available(iOS 14.1, *) {
            if tech == CTRadioAccessTechnologyNR || tech == CTRadioAccessTechnologyNRNSA { return "5G" }
        }
        switch tech {
        case CTRadioAccessTechnologyLTE: return "LTE"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD:
            return "3G"
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyCDMA1x:
            return "2G"
        default: return nil
        }
    }

    // MARK: - Lists auto-update

    private func scheduleListsUpdates() {
        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now() + 20, repeating: 6 * 3600)
        timer.setEventHandler { [weak self] in
            guard let self, self.config.listsAutoUpdate, ListStore.isStale else { return }
            Task {
                let result = await ListStore.updateFromUpstream()
                switch result {
                case .success(let n):
                    Log.write("lists updated (\(n) files)")
                    self.controlQueue.async { self.restartEngine(reason: "lists updated") }
                case .failure(let error):
                    Log.write("lists update failed: \(error.localizedDescription)")
                }
            }
        }
        timer.resume()
        listsTimer = timer
    }
}
