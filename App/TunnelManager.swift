import Foundation
import NetworkExtension
import Observation

/// VPN mode: our own Network Extension (paid developer account).
@Observable
@MainActor
final class TunnelManager {
    private(set) var vpnStatus: NEVPNStatus = .invalid
    private(set) var tunnelStatus: TunnelStatus?
    var lastError: String?
    private(set) var isBusy = false

    @ObservationIgnored private var manager: NETunnelProviderManager?
    @ObservationIgnored private var statusObserver: NSObjectProtocol?
    @ObservationIgnored private var pollTimer: Timer?

    var isConnected: Bool { vpnStatus == .connected }
    var isTransitioning: Bool { [.connecting, .disconnecting, .reasserting].contains(vpnStatus) }

    init() {
        // Lite has no extension and no NE entitlement.
        if !AppEdition.isLite {
            Task { await load() }
        }
    }

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let ours = managers.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppIdentity.tunnelBundleID
            }
            // Profiles left over from an install signed with another team.
            for stale in managers where stale !== ours {
                if let id = (stale.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier,
                   id.hasSuffix(AppIdentity.tunnelSuffix), id != AppIdentity.tunnelBundleID {
                    try? await stale.removeFromPreferences()
                }
            }
            setManager(ours)
        } catch {
            lastError = "Не удалось загрузить профили VPN: \(error.localizedDescription)"
        }
    }

    private func setManager(_ m: NETunnelProviderManager?) {
        manager = m
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        guard let m else {
            vpnStatus = .invalid
            return
        }
        vpnStatus = m.connection.status
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: m.connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.statusChanged() }
        }
        statusChanged()
    }

    private func statusChanged() {
        guard let m = manager else { return }
        vpnStatus = m.connection.status
        if vpnStatus == .connected {
            startPolling()
        } else {
            stopPolling()
            if vpnStatus == .disconnected { tunnelStatus = nil }
        }
    }

    private func prepareManager(config: AppConfig) async throws -> NETunnelProviderManager {
        let m = manager ?? NETunnelProviderManager()
        let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppIdentity.tunnelBundleID
        proto.serverAddress = "Zapret · на устройстве"
        proto.disconnectOnSleep = false
        m.protocolConfiguration = proto
        m.localizedDescription = "Zapret"
        m.isEnabled = true
        if config.onDemand {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            m.onDemandRules = [rule]
            m.isOnDemandEnabled = true
        } else {
            m.onDemandRules = []
            m.isOnDemandEnabled = false
        }
        try await m.saveToPreferences()
        try await m.loadFromPreferences()
        if manager !== m { setManager(m) }
        return m
    }

    func connect(config: AppConfig) async {
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        guard Paths.hasSharedContainer else {
            lastError = "App Group недоступна: приложение подписано без нужных прав. Установите IPA через AltStore."
            return
        }
        ConfigStore.save(config)
        do {
            let m = try await prepareManager(config: config)
            try m.connection.startVPNTunnel()
        } catch {
            lastError = "Не удалось запустить туннель: \(error.localizedDescription)"
        }
    }

    func disconnect() async {
        guard let m = manager else { return }
        isBusy = true
        defer { isBusy = false }
        if m.isOnDemandEnabled {
            // Otherwise the system immediately reconnects.
            m.isOnDemandEnabled = false
            try? await m.saveToPreferences()
        }
        m.connection.stopVPNTunnel()
    }

    /// Waits until the tunnel is fully down (used before running the tester).
    func disconnectAndWait() async {
        await disconnect()
        for _ in 0..<50 where vpnStatus != .disconnected && vpnStatus != .invalid {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func applyOnDemand(config: AppConfig) async {
        guard manager != nil else { return }
        _ = try? await prepareManager(config: config)
    }

    /// Asks the running extension to re-read config.json.
    func reload() async {
        guard isConnected else { return }
        if let status = await send(.reload) { tunnelStatus = status }
    }

    func refreshStatus() async {
        guard isConnected else { return }
        if let status = await send(.status) { tunnelStatus = status }
    }

    private func send(_ command: TunnelCommand) async -> TunnelStatus? {
        guard let session = manager?.connection as? NETunnelProviderSession,
              let data = try? JSONEncoder().encode(TunnelRequest(command: command)) else { return nil }
        return await withCheckedContinuation { cont in
            do {
                try session.sendProviderMessage(data) { response in
                    let status = response.flatMap { try? JSONDecoder().decode(TunnelStatus.self, from: $0) }
                    cont.resume(returning: status)
                }
            } catch {
                cont.resume(returning: nil)
            }
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        Task { await refreshStatus() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshStatus() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
