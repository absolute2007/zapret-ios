import Foundation

enum NetworkKind: String, Codable, CaseIterable, Identifiable {
    case wifi, cellular, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Сотовая сеть"
        case .other: return "Другая сеть"
        }
    }

    var symbol: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        }
    }
}

enum QuicMode: String, Codable, CaseIterable, Identifiable {
    /// Fake QUIC Initial before the real one (как в zapret).
    case fake
    /// Drop UDP/443 so apps fall back to TCP+TLS, where desync is strongest.
    case block
    /// Do not touch QUIC.
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fake: return "Фейк (как zapret)"
        case .block: return "Блокировать QUIC"
        case .off: return "Не трогать"
        }
    }
}

enum IpsetMode: String, Codable, CaseIterable, Identifiable {
    case off, loaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Выключен"
        case .loaded: return "ipset-all (из репозитория)"
        }
    }
}

enum DNSPreset: String, Codable, CaseIterable, Identifiable {
    case cloudflareDoH, googleDoH, quad9DoH, adguardDoH, cloudflarePlain, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloudflareDoH: return "Cloudflare (DoH)"
        case .googleDoH: return "Google (DoH)"
        case .quad9DoH: return "Quad9 (DoH)"
        case .adguardDoH: return "AdGuard (DoH)"
        case .cloudflarePlain: return "1.1.1.1 (обычный DNS)"
        case .system: return "DNS провайдера"
        }
    }

    var servers: [String] {
        switch self {
        case .cloudflareDoH, .cloudflarePlain: return ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111"]
        case .googleDoH: return ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888"]
        case .quad9DoH: return ["9.9.9.9", "149.112.112.112", "2620:fe::fe"]
        case .adguardDoH: return ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff"]
        case .system: return []
        }
    }

    var dohURL: URL? {
        switch self {
        case .cloudflareDoH: return URL(string: "https://cloudflare-dns.com/dns-query")
        case .googleDoH: return URL(string: "https://dns.google/dns-query")
        case .quad9DoH: return URL(string: "https://dns.quad9.net/dns-query")
        case .adguardDoH: return URL(string: "https://dns.adguard-dns.com/dns-query")
        case .cloudflarePlain, .system: return nil
        }
    }
}

struct AppConfig: Codable, Equatable {
    /// Strategy used on Wi-Fi / wired-like networks.
    var wifiStrategyID: String = StrategyCatalog.defaultWifi
    /// Strategy used on cellular networks.
    var cellularStrategyID: String = StrategyCatalog.defaultCellular
    /// When false, the Wi-Fi strategy is used everywhere.
    var separateCellularProfile: Bool = true
    /// Automatically try fallback recipes when a connection looks blocked
    /// (reset / timeout / broken TLS handshake). Very useful on mobile carriers.
    var autoFallback: Bool = true
    var quicMode: QuicMode = .fake
    var discordVoice: Bool = true
    var gameFilter: Bool = false
    var ipsetMode: IpsetMode = .off
    /// TTL for UDP fake packets. 64 ≈ zapret default (fake is sent without fooling).
    var udpFakeTTL: Int = 64
    var udpFakeRepeats: Int = 6
    var dns: DNSPreset = .cloudflareDoH
    var ipv6: Bool = true
    var onDemand: Bool = false
    var listsAutoUpdate: Bool = true
    /// Raw byedpi arguments for the "custom" strategy (desync part only).
    var customArgs: String = "--disorder 1 --tlsrec 1+s"
    var verboseLog: Bool = false

    init() {}

    func strategyID(for kind: NetworkKind) -> String {
        if separateCellularProfile && kind == .cellular {
            return cellularStrategyID
        }
        return wifiStrategyID
    }

    // Tolerant decoding: new fields get defaults, unknown ones are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.defaults
        wifiStrategyID = (try? c.decode(String.self, forKey: .wifiStrategyID)) ?? d.wifiStrategyID
        cellularStrategyID = (try? c.decode(String.self, forKey: .cellularStrategyID)) ?? d.cellularStrategyID
        separateCellularProfile = (try? c.decode(Bool.self, forKey: .separateCellularProfile)) ?? d.separateCellularProfile
        autoFallback = (try? c.decode(Bool.self, forKey: .autoFallback)) ?? d.autoFallback
        quicMode = (try? c.decode(QuicMode.self, forKey: .quicMode)) ?? d.quicMode
        discordVoice = (try? c.decode(Bool.self, forKey: .discordVoice)) ?? d.discordVoice
        gameFilter = (try? c.decode(Bool.self, forKey: .gameFilter)) ?? d.gameFilter
        ipsetMode = (try? c.decode(IpsetMode.self, forKey: .ipsetMode)) ?? d.ipsetMode
        udpFakeTTL = (try? c.decode(Int.self, forKey: .udpFakeTTL)) ?? d.udpFakeTTL
        udpFakeRepeats = (try? c.decode(Int.self, forKey: .udpFakeRepeats)) ?? d.udpFakeRepeats
        dns = (try? c.decode(DNSPreset.self, forKey: .dns)) ?? d.dns
        ipv6 = (try? c.decode(Bool.self, forKey: .ipv6)) ?? d.ipv6
        onDemand = (try? c.decode(Bool.self, forKey: .onDemand)) ?? d.onDemand
        listsAutoUpdate = (try? c.decode(Bool.self, forKey: .listsAutoUpdate)) ?? d.listsAutoUpdate
        customArgs = (try? c.decode(String.self, forKey: .customArgs)) ?? d.customArgs
        verboseLog = (try? c.decode(Bool.self, forKey: .verboseLog)) ?? d.verboseLog
    }

    private static let defaults = AppConfig()
}

enum ConfigStore {
    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: Paths.config),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return cfg
    }

    static func save(_ config: AppConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) {
            try? data.write(to: Paths.config, options: .atomic)
        }
    }
}
