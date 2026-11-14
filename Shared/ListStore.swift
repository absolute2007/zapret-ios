import Foundation

/// Hostlists / ipsets from Flowseal/zapret-discord-youtube plus user lists.
enum ListKind: String, CaseIterable, Identifiable, Codable {
    case general = "list-general"
    case google = "list-google"
    case exclude = "list-exclude"
    case ipsetExclude = "ipset-exclude"
    case ipsetAll = "ipset-all"

    var id: String { rawValue }
    var fileName: String { rawValue + ".txt" }
    var userFileName: String { rawValue + "-user.txt" }
    var isIPSet: Bool { self == .ipsetExclude || self == .ipsetAll }

    var title: String {
        switch self {
        case .general: return "Общий (Discord, Cloudflare…)"
        case .google: return "YouTube / Google"
        case .exclude: return "Исключения (домены)"
        case .ipsetExclude: return "Исключения (IP)"
        case .ipsetAll: return "ipset-all"
        }
    }

    /// Where the upstream copy lives.
    var upstreamPath: String {
        switch self {
        case .ipsetAll: return ".service/ipset-service.txt"
        default: return "lists/" + fileName
        }
    }

    /// Byedpi refuses empty lists, so we feed it a harmless placeholder.
    var placeholder: String { isIPSet ? "203.0.113.113/32" : "placeholder.invalid" }
}

struct ListsMeta: Codable {
    var lastUpdate: Date?
    var lastError: String?
    var counts: [String: Int] = [:]
}

struct EngineFiles {
    let general: String
    let google: String
    let exclude: String
    let ipsetExclude: String
    let ipsetAll: String?
    let quicFake: String?
    let discordFake: String?
    let gameFake: String?
}

enum ListStore {
    static let staleInterval: TimeInterval = 24 * 3600

    static func url(_ kind: ListKind) -> URL { Paths.lists.appendingPathComponent(kind.fileName) }
    static func userURL(_ kind: ListKind) -> URL { Paths.lists.appendingPathComponent(kind.userFileName) }

    static func loadMeta() -> ListsMeta {
        guard let data = try? Data(contentsOf: Paths.listsMeta),
              let meta = try? JSONDecoder().decode(ListsMeta.self, from: data) else { return ListsMeta() }
        return meta
    }

    static func saveMeta(_ meta: ListsMeta) {
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: Paths.listsMeta, options: .atomic)
        }
    }

    static var isStale: Bool {
        guard let last = loadMeta().lastUpdate else { return true }
        return Date().timeIntervalSince(last) > staleInterval
    }

    /// Copies bundled lists into the shared container if they are missing.
    static func ensureInstalled() {
        let fm = FileManager.default
        for kind in ListKind.allCases {
            let dst = url(kind)
            if !fm.fileExists(atPath: dst.path),
               let src = Paths.resource(kind.rawValue, ext: "txt", subdir: "lists") {
                try? fm.copyItem(at: src, to: dst)
            }
            let user = userURL(kind)
            if !fm.fileExists(atPath: user.path) {
                try? "".write(to: user, atomically: true, encoding: .utf8)
            }
        }
    }

    static func read(_ kind: ListKind, user: Bool = false) -> String {
        (try? String(contentsOf: user ? userURL(kind) : url(kind), encoding: .utf8)) ?? ""
    }

    static func writeUser(_ kind: ListKind, text: String) {
        try? text.write(to: userURL(kind), atomically: true, encoding: .utf8)
    }

    /// Normalises zapret list syntax for byedpi: strips comments and the
    /// `^` (exact match) prefix, drops junk lines.
    static func entries(_ text: String, ipset: Bool) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("^") { line.removeFirst() }
            line = line.lowercased()
            guard !line.isEmpty, !line.contains(" ") else { continue }
            if ipset {
                guard line.contains(".") || line.contains(":") else { continue }
            } else {
                guard line.contains("."), !line.contains("/") else { continue }
            }
            if seen.insert(line).inserted { out.append(line) }
        }
        return out
    }

    static func count(_ kind: ListKind) -> Int {
        entries(read(kind), ipset: kind.isIPSet).count + entries(read(kind, user: true), ipset: kind.isIPSet).count
    }

    /// Merges upstream + user lists into files the engine reads.
    static func prepareEngineFiles(config: AppConfig) -> EngineFiles {
        ensureInstalled()
        func merged(_ kind: ListKind) -> String {
            let items = entries(read(kind), ipset: kind.isIPSet) + entries(read(kind, user: true), ipset: kind.isIPSet)
            let body = (items.isEmpty ? [kind.placeholder] : items).joined(separator: "\n") + "\n"
            let dst = Paths.engine.appendingPathComponent(kind.fileName)
            try? body.write(to: dst, atomically: true, encoding: .utf8)
            return dst.path
        }

        var ipsetAll: String?
        if config.ipsetMode == .loaded {
            let items = entries(read(.ipsetAll), ipset: true) + entries(read(.ipsetAll, user: true), ipset: true)
            // The upstream default is a single placeholder address: treat as empty.
            if items.contains(where: { $0 != ListKind.ipsetAll.placeholder }) {
                ipsetAll = merged(.ipsetAll)
            }
        }

        return EngineFiles(
            general: merged(.general),
            google: merged(.google),
            exclude: merged(.exclude),
            ipsetExclude: merged(.ipsetExclude),
            ipsetAll: ipsetAll,
            quicFake: Paths.resource("quic_initial_www_google_com", ext: "bin", subdir: "fake")?.path,
            discordFake: Paths.resource("ACTIVE_DISCORD_UDP", ext: "bin", subdir: "fake")?.path,
            gameFake: Paths.resource("ACTIVE_GAME_UDP", ext: "bin", subdir: "fake")?.path
        )
    }

    /// Downloads fresh lists from the upstream repository.
    @discardableResult
    static func updateFromUpstream() async -> Result<Int, Error> {
        ensureInstalled()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var meta = loadMeta()
        var updated = 0
        var firstError: Error?

        for kind in ListKind.allCases {
            guard let remote = URL(string: Links.upstreamRaw + kind.upstreamPath) else { continue }
            do {
                let (data, response) = try await session.data(from: remote)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let text = String(data: data, encoding: .utf8) else {
                    throw URLError(.badServerResponse)
                }
                let items = entries(text, ipset: kind.isIPSet)
                // Sanity check: never replace a list with garbage.
                guard !items.isEmpty || kind == .ipsetAll else { throw URLError(.cannotParseResponse) }
                try text.write(to: url(kind), atomically: true, encoding: .utf8)
                meta.counts[kind.rawValue] = items.count
                updated += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if updated > 0 {
            meta.lastUpdate = Date()
        }
        meta.lastError = firstError.map { "\($0.localizedDescription)" }
        saveMeta(meta)

        if updated == 0, let err = firstError { return .failure(err) }
        return .success(updated)
    }
}
