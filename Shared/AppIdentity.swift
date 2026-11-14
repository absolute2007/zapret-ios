import Foundation

/// Identifiers that survive AltStore/SideStore re-signing.
///
/// AltStore rewrites `io.github.x.zapret` → `io.github.x.zapret.<TEAMID>` and the
/// app group `group.io.github.x.zapret` → `group.io.github.x.zapret.<TEAMID>`,
/// so everything is derived from the bundle identifier at runtime instead of
/// being hard-coded.
enum AppIdentity {
    static let tunnelSuffix = ".tunnel"

    static var appBundleID: String {
        let id = Bundle.main.bundleIdentifier ?? "io.github.absolute2007.zapret"
        if id.hasSuffix(tunnelSuffix) {
            return String(id.dropLast(tunnelSuffix.count))
        }
        return id
    }

    static var tunnelBundleID: String { appBundleID + tunnelSuffix }

    static var appGroupID: String {
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
           let group = groups.first(where: { !$0.isEmpty }) {
            return group
        }
        return "group." + appBundleID
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}

enum Links {
    static let repoOwner = "absolute2007"
    static let repoName = "zapret-ios"
    static var repo: URL { URL(string: "https://github.com/\(repoOwner)/\(repoName)")! }
    static var altSource: URL {
        URL(string: "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/main/altstore/source.json")!
    }
    static let upstreamRepo = URL(string: "https://github.com/Flowseal/zapret-discord-youtube")!
    static let upstreamRaw = "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/"
}

enum Paths {
    static var container: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroupID) {
            return url
        }
        // Should not happen on a correctly signed build; keep the app usable anyway.
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var hasSharedContainer: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroupID) != nil
    }

    static var config: URL { container.appendingPathComponent("config.json") }
    static var lists: URL { dir("lists") }
    static var engine: URL { dir("engine") }
    static var logs: URL { dir("logs") }
    static var tunnelLog: URL { logs.appendingPathComponent("tunnel.log") }
    static var engineLog: URL { logs.appendingPathComponent("engine.log") }
    static var hevLog: URL { logs.appendingPathComponent("tun2socks.log") }
    static var testerLog: URL { logs.appendingPathComponent("tester.log") }
    static var listsMeta: URL { lists.appendingPathComponent("meta.json") }

    private static func dir(_ name: String) -> URL {
        let url = container.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Bundled resources (both the app and the extension carry a copy).
    static func resource(_ name: String, ext: String, subdir: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}
