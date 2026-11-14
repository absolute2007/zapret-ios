import Foundation
import Network

/// Editable configuration shared with the extension through config.json.
@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig {
        didSet {
            guard config != oldValue else { return }
            ConfigStore.save(config)
            scheduleReload(onDemandChanged: config.onDemand != oldValue.onDemand)
        }
    }
    @Published private(set) var localNetwork: NetworkKind = .other
    @Published private(set) var listsMeta = ListStore.loadMeta()
    @Published private(set) var updatingLists = false
    @Published var listsMessage: String?

    weak var tunnel: TunnelManager?
    private var reloadTask: Task<Void, Never>?
    private let monitor = NWPathMonitor()

    init() {
        config = ConfigStore.load()
        ListStore.ensureInstalled()
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: NetworkKind
            if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                kind = .wifi
            } else if path.usesInterfaceType(.cellular) {
                kind = .cellular
            } else if path.availableInterfaces.contains(where: { $0.type == .cellular }) {
                kind = .cellular
            } else if path.availableInterfaces.contains(where: { $0.type == .wifi }) {
                kind = .wifi
            } else {
                kind = .other
            }
            Task { @MainActor in self?.localNetwork = kind }
        }
        monitor.start(queue: DispatchQueue(label: "zapret.app.path"))
    }

    var currentNetwork: NetworkKind { tunnel?.tunnelStatus?.network ?? localNetwork }

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

    private func scheduleReload(onDemandChanged: Bool) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self, let tunnel = self.tunnel else { return }
            if onDemandChanged { await tunnel.applyOnDemand(config: self.config) }
            await tunnel.reload()
        }
    }

    func updateLists() async {
        updatingLists = true
        defer { updatingLists = false }
        let result = await ListStore.updateFromUpstream()
        listsMeta = ListStore.loadMeta()
        switch result {
        case .success(let n):
            listsMessage = "Обновлено файлов: \(n)"
            await tunnel?.reload()
        case .failure(let error):
            listsMessage = "Ошибка обновления: \(error.localizedDescription)"
        }
    }

    func userListChanged() {
        listsMeta = ListStore.loadMeta()
        scheduleReload(onDemandChanged: false)
    }
}
