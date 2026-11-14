import Foundation
import Network
import Observation

/// iOS analogue of zapret's "test zapret.ps1": runs every strategy in a local
/// byedpi instance inside the app and checks real YouTube/Discord endpoints
/// through it on the *current* network (Wi-Fi or a specific carrier).
@Observable
@MainActor
final class StrategyTester {
    struct Target: Identifiable, Hashable {
        let id: String
        let group: String
        let url: URL
        /// Read at least this many bytes to count as success (detects throttling).
        let minBytes: Int
    }

    struct TargetResult: Identifiable, Hashable {
        let id: String
        let ok: Bool
        let millis: Int
        let detail: String
    }

    struct Result: Identifiable, Hashable {
        let id: String
        let name: String
        let targets: [TargetResult]
        var passed: Int { targets.filter(\.ok).count }
        var avgMillis: Int {
            let ok = targets.filter(\.ok)
            return ok.isEmpty ? 0 : ok.map(\.millis).reduce(0, +) / ok.count
        }
        func passed(group: String) -> Int {
            targets.filter { $0.ok && $0.id.hasPrefix(group) }.count
        }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case quick, full
        var id: String { rawValue }
        var title: String { self == .quick ? "Быстрый" : "Полный" }
    }

    static let baselineID = "__baseline"

    static let targets: [Target] = [
        Target(id: "yt.web", group: "YouTube", url: URL(string: "https://www.youtube.com/")!, minBytes: 96 * 1024),
        Target(id: "yt.api", group: "YouTube", url: URL(string: "https://youtubei.googleapis.com/generate_204")!, minBytes: 0),
        Target(id: "yt.video", group: "YouTube", url: URL(string: "https://redirector.googlevideo.com/report_mapping")!, minBytes: 0),
        Target(id: "yt.img", group: "YouTube", url: URL(string: "https://i.ytimg.com/generate_204")!, minBytes: 0),
        Target(id: "dc.main", group: "Discord", url: URL(string: "https://discord.com/api/v9/gateway")!, minBytes: 0),
        Target(id: "dc.gw", group: "Discord", url: URL(string: "https://gateway.discord.gg/")!, minBytes: 0),
        Target(id: "dc.cdn", group: "Discord", url: URL(string: "https://cdn.discordapp.com/")!, minBytes: 0),
        Target(id: "dc.upd", group: "Discord", url: URL(string: "https://updates.discord.com/")!, minBytes: 0),
    ]

    static let quickSet = ["general", "mobile", "alt", "alt4", "alt5", "alt7", "fta", "sf_alt"]

    private(set) var running = false
    private(set) var progress: Double = 0
    private(set) var current: String?
    private(set) var results: [Result] = []
    var error: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let engine = EngineRunner.shared
    /// Called on the main actor when a run finishes or is cancelled.
    @ObservationIgnored var onFinish: (() -> Void)?

    var sortedResults: [Result] {
        results.filter { $0.id != Self.baselineID }.sorted {
            $0.passed != $1.passed ? $0.passed > $1.passed : $0.avgMillis < $1.avgMillis
        }
    }

    var baseline: Result? { results.first { $0.id == Self.baselineID } }

    func start(mode: Mode, config: AppConfig) {
        guard !running else { return }
        var candidates: [(id: String, name: String, args: [String])] = [(id: Self.baselineID, name: "Без обхода", args: [])]
        let pool = mode == .quick
            ? StrategyCatalog.all.filter { Self.quickSet.contains($0.id) }
            : StrategyCatalog.all
        candidates += pool.map { (id: $0.id, name: $0.name, args: $0.general) }
        if !config.customArgs.trimmingCharacters(in: .whitespaces).isEmpty {
            candidates.append((id: StrategyCatalog.customID, name: "Свои параметры", args: Strategy.split(config.customArgs)))
        }

        running = true
        progress = 0
        results = []
        error = nil
        Log.clear(Paths.testerLog)
        zdpi_redirect_stderr(Paths.testerLog.path)

        task = Task { [weak self] in
            guard let self else { return }
            for (index, candidate) in candidates.enumerated() {
                if Task.isCancelled { break }
                self.current = candidate.name
                let result = await self.run(candidate: candidate)
                self.results.append(result)
                self.progress = Double(index + 1) / Double(candidates.count)
            }
            self.current = nil
            await self.stopEngine()
            self.running = false
            self.onFinish?()
            self.onFinish = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func stopEngine() async {
        let engine = self.engine
        await Task.detached { engine.stop() }.value
    }

    private func run(candidate: (id: String, name: String, args: [String])) async -> Result {
        let engine = self.engine
        Log.write("=== \(candidate.name): \(candidate.args.joined(separator: " "))", to: Paths.testerLog)
        var listening: Int?
        var lastError: Error = EngineRunner.EngineError.exited(-5)
        for port in EngineArgs.testerPorts {
            let args = EngineArgs.tester(desync: candidate.args, port: port)
            do {
                try await Task.detached { try engine.start(args: args) }.value
                listening = port
                break
            } catch EngineRunner.EngineError.exited(-5) {
                continue
            } catch {
                lastError = error
                break
            }
        }
        guard let port = listening else {
            let detail = lastError.localizedDescription
            let failed = Self.targets.map { TargetResult(id: $0.id, ok: false, millis: 0, detail: detail) }
            return Result(id: candidate.id, name: candidate.name, targets: failed)
        }

        let session = Self.makeSession(port: port)
        defer { session.invalidateAndCancel() }

        let results = await withTaskGroup(of: TargetResult.self) { group -> [TargetResult] in
            for target in Self.targets {
                group.addTask { await Self.probe(target, session: session) }
            }
            var out: [TargetResult] = []
            for await r in group { out.append(r) }
            return out
        }
        let ordered = Self.targets.compactMap { t in results.first { $0.id == t.id } }
        await stopEngine()
        return Result(id: candidate.id, name: candidate.name, targets: ordered)
    }

    nonisolated private static func makeSession(port: Int) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 7
        cfg.timeoutIntervalForResource = 9
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.httpShouldUsePipelining = false
        cfg.waitsForConnectivity = false
        if #available(iOS 17.0, *) {
            let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
            cfg.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: endpoint)]
        } else {
            cfg.connectionProxyDictionary = [
                "SOCKSEnable": 1,
                "SOCKSProxy": "127.0.0.1",
                "SOCKSPort": port,
            ]
        }
        return URLSession(configuration: cfg)
    }

    nonisolated private static func probe(_ target: Target, session: URLSession) async -> TargetResult {
        let start = Date()
        func ms() -> Int { Int(Date().timeIntervalSince(start) * 1000) }
        do {
            var request = URLRequest(url: target.url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                             forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if target.minBytes == 0 {
                bytes.task.cancel()
                return TargetResult(id: target.id, ok: true, millis: ms(), detail: "HTTP \(status)")
            }
            var received = 0
            for try await _ in bytes {
                received += 1
                if received >= target.minBytes { break }
            }
            bytes.task.cancel()
            let ok = received >= target.minBytes || received == Int(response.expectedContentLength)
            return TargetResult(id: target.id, ok: ok, millis: ms(),
                                detail: ok ? "HTTP \(status), \(received / 1024) КБ" : "обрыв на \(received / 1024) КБ")
        } catch {
            let ns = error as NSError
            let detail = ns.code == NSURLErrorTimedOut ? "таймаут" : ns.localizedDescription
            return TargetResult(id: target.id, ok: false, millis: ms(), detail: detail)
        }
    }
}
