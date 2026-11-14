import Foundation

/// sing-box (≥ 1.12) profile for proxy mode.
///
/// Only hosts from the zapret lists (plus Discord voice ports) are sent to the
/// local engine; everything else goes direct. So if iOS ever suspends the app,
/// only YouTube/Discord stop working, not the whole internet.
///
/// sing-box sends destinations as IP addresses (no sniff override), so the
/// engine never has to resolve names itself; it reads the SNI from the
/// ClientHello for hostlist matching.
enum SingBoxProfile {
    static let remoteProfileURL = URL(string: "https://raw.githubusercontent.com/\(Links.repoOwner)/\(Links.repoName)/main/singbox/profile.json")!
    static let remoteRuleSetURL = "https://raw.githubusercontent.com/\(Links.repoOwner)/\(Links.repoName)/main/singbox/zapret-domains.json"

    /// `sing-box://import-remote-profile?url=…#name` — opens sing-box and adds an auto-updating profile.
    static var importURL: URL? {
        guard let encoded = remoteProfileURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "sing-box://import-remote-profile?url=\(encoded)#Zapret")
    }

    /// Profile with the user's merged lists inlined (exported as a file).
    static func localProfile(config: AppConfig) -> Data {
        let files = ListStore.prepareEngineFiles(config: config)
        let domains = [files.google, files.general]
            .compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            .flatMap { ListStore.entries($0, ipset: false) }
            .filter { $0 != ListKind.general.placeholder }
        let ruleSet: [String: Any] = [
            "type": "inline",
            "tag": "zapret-domains",
            "rules": [["domain_suffix": Array(Set(domains)).sorted()]],
        ]
        return make(ports: EngineArgs.proxyPorts, dns: config.dns, ruleSet: ruleSet)
    }

    /// The engine takes the first free port of `ports`; sing-box probes them
    /// with urltest and uses whichever answers.
    static func make(ports: [Int], dns: DNSPreset, ruleSet: [String: Any]) -> Data {
        let members: [[String: Any]] = ports.enumerated().map { i, port in
            ["type": "socks", "tag": "zapret-\(i + 1)", "server": "127.0.0.1", "server_port": port, "version": "5"]
        }
        let group: [String: Any] = [
            "type": "urltest",
            "tag": "zapret",
            "outbounds": members.compactMap { $0["tag"] as? String },
            "url": "https://www.gstatic.com/generate_204",
            "interval": "1m",
            "tolerance": 300,
        ]
        let dnsServer: [String: Any]
        switch dns {
        case .googleDoH: dnsServer = ["type": "https", "tag": "remote", "server": "8.8.8.8"]
        case .quad9DoH: dnsServer = ["type": "https", "tag": "remote", "server": "9.9.9.9"]
        case .adguardDoH: dnsServer = ["type": "https", "tag": "remote", "server": "94.140.14.14"]
        case .cloudflarePlain: dnsServer = ["type": "udp", "tag": "remote", "server": "1.1.1.1"]
        case .system: dnsServer = ["type": "local", "tag": "remote"]
        case .cloudflareDoH: dnsServer = ["type": "https", "tag": "remote", "server": "1.1.1.1"]
        }

        let profile: [String: Any] = [
            "log": ["level": "warn"],
            "dns": [
                "servers": [dnsServer],
                "final": "remote",
                "strategy": "prefer_ipv4",
            ],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true,
                "strict_route": true,
            ]],
            "outbounds": [["type": "direct", "tag": "direct"], group] + members,
            "route": [
                "rules": [
                    ["action": "sniff"],
                    ["protocol": "dns", "action": "hijack-dns"],
                    ["ip_is_private": true, "outbound": "direct"],
                    ["rule_set": ["zapret-domains"], "outbound": "zapret"],
                    ["network": "udp", "port_range": ["50000:50100", "19294:19344"], "outbound": "zapret"],
                ],
                "rule_set": [ruleSet],
                "final": "direct",
                "auto_detect_interface": true,
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: profile, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    /// Writes the local profile to a temporary file for the share sheet.
    static func exportFile(config: AppConfig) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Zapret-sing-box.json")
        try? localProfile(config: config).write(to: url, options: .atomic)
        return url
    }
}
