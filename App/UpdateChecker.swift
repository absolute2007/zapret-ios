import Foundation
import Observation
import UIKit

/// Checks the AltStore source (altstore/source.json in this repo) for a newer
/// build and hands the IPA over to AltStore / SideStore.
@Observable
@MainActor
final class UpdateChecker {
    struct Source: Decodable {
        struct App: Decodable {
            let bundleIdentifier: String
            let versions: [Version]?
        }
        let apps: [App]
    }

    struct Version: Decodable, Equatable {
        let version: String
        let buildVersion: String?
        let date: String?
        let localizedDescription: String?
        let downloadURL: String
        let size: Int?
    }

    private(set) var available: Version?
    private(set) var checking = false
    private(set) var lastChecked: Date?
    var message: String?

    @ObservationIgnored private let lastCheckKey = "updates.lastCheck"
    @ObservationIgnored private let minInterval: TimeInterval = 6 * 3600

    func checkIfNeeded() async {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < minInterval { return }
        await check()
    }

    func check() async {
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: Links.altSource)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            let source = try JSONDecoder().decode(Source.self, from: data)
            // AltStore appends the team ID, so match by prefix; the longest
            // match wins (…zapret.lite must not pick …zapret).
            let app = source.apps
                .filter { AppIdentity.appBundleID.hasPrefix($0.bundleIdentifier) }
                .max { $0.bundleIdentifier.count < $1.bundleIdentifier.count }
            let latest = app?.versions?.first
            lastChecked = Date()
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            if let latest, Self.isNewer(latest, thanVersion: AppIdentity.appVersion, build: AppIdentity.buildNumber) {
                available = latest
                message = nil
            } else {
                available = nil
                message = "Установлена последняя версия (\(AppIdentity.appVersion))"
            }
        } catch {
            message = "Не удалось проверить обновления: \(error.localizedDescription)"
        }
    }

    static func isNewer(_ v: Version, thanVersion current: String, build: String) -> Bool {
        let order = compare(v.version, current)
        if order != .orderedSame { return order == .orderedDescending }
        if let b = v.buildVersion, let lb = Int(b), let cb = Int(build) { return lb > cb }
        return false
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Opens AltStore (or SideStore) with the new IPA.
    func install(_ version: Version) {
        guard let encoded = version.downloadURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return }
        let candidates = [
            "altstore://install?url=\(encoded)",
            "sidestore://install?url=\(encoded)",
        ].compactMap(URL.init(string:))
        open(candidates, fallback: URL(string: version.downloadURL))
    }

    /// Adds this repository as a source in AltStore so it auto-updates the app.
    func addSource() {
        guard let encoded = Links.altSource.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return }
        let candidates = [
            "altstore://source?url=\(encoded)",
            "sidestore://source?url=\(encoded)",
        ].compactMap(URL.init(string:))
        open(candidates, fallback: Links.repo)
    }

    private func open(_ urls: [URL], fallback: URL?) {
        guard let first = urls.first else {
            if let fallback { UIApplication.shared.open(fallback) }
            return
        }
        UIApplication.shared.open(first) { [weak self] ok in
            guard !ok else { return }
            Task { @MainActor in self?.open(Array(urls.dropFirst()), fallback: fallback) }
        }
    }
}
