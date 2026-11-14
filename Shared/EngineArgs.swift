import Foundation

/// Builds byedpi command lines that mirror the structure of zapret's
/// `general*.bat` (filter groups separated by `--new`).
///
/// byedpi picks the first group whose filters match, so the order is:
///   0. ipset-exclude              → no desync
///   1. UDP/443  (QUIC)            → fake QUIC Initial ×N  | drop
///   2. UDP Discord voice/STUN     → fake Discord packet ×N
///   3. UDP games (ipset, opt.)    → fake ×12
///   4. list-exclude               → no desync
///   5. list-google                → strategy.google  (+ auto fallbacks)
///   6. list-general               → strategy.general (+ auto fallbacks)
///   7. ipset-all (optional)       → strategy.general
///   8. everything else            → no desync
enum EngineArgs {
    static let tunnelPort = 10_808
    static let testerPort = 10_909
    static let tunnelPortRange = 10_808...10_818

    static func build(config: AppConfig, strategy: Strategy, files: EngineFiles, port: Int = tunnelPort) -> [String] {
        var a: [String] = ["ciadpi", "-i", "127.0.0.1", "-p", String(port),
                           "-c", "768", "-x", config.verboseLog ? "1" : "0"]
        if config.autoFallback {
            // Userspace timer: no ServerHello within 3 s → treat as blocked.
            a += ["--tls-timeout", "3"]
        }

        func group(_ extra: [String]) { a += ["--auto=none"] + extra }
        let ttl = String(max(1, min(255, config.udpFakeTTL)))
        let repeats = String(max(1, min(20, config.udpFakeRepeats)))
        let http = ["--mod-http", "h,d"]

        // 0. First group is implicit (no --auto before it).
        a += ["--ipset", files.ipsetExclude]

        // 1. QUIC
        switch config.quicMode {
        case .fake:
            if let quic = files.quicFake {
                group(["--proto", "udp", "--pf", "443", "--udp-fake", repeats, "--fake-data", quic, "--ttl", ttl])
            }
        case .block:
            group(["--proto", "udp", "--pf", "443", "--rst"])
        case .off:
            break
        }

        // 2. Discord voice / STUN
        if config.discordVoice, let discord = files.discordFake {
            for ports in ["50000-50100", "19294-19344"] {
                group(["--proto", "udp", "--pf", ports, "--udp-fake", repeats, "--fake-data", discord, "--ttl", ttl])
            }
        }

        // 3. Game filter (needs ipset-all, as in zapret)
        if config.gameFilter, let ipset = files.ipsetAll, let game = files.gameFake {
            group(["--proto", "udp", "--pf", "1024-65535", "--ipset", ipset,
                   "--udp-fake", "12", "--fake-data", game, "--ttl", ttl])
        }

        // 4. Excluded domains
        group(["--hosts", files.exclude])

        // 5-6. Hostlists with optional automatic fallbacks
        for (list, desync) in [(files.google, strategy.google), (files.general, strategy.general)] {
            group(["--hosts", list] + desync + http)
            if config.autoFallback {
                for fb in StrategyCatalog.fallbacks where fb != desync {
                    a += ["--auto=torst,ssl_err", "--hosts", list] + fb + http
                }
            }
        }

        // 7. ipset-all
        if let ipset = files.ipsetAll {
            group(["--ipset", ipset] + strategy.general)
        }

        // 8. Default: pass through untouched.
        a += ["--auto=none"]
        return a
    }

    /// Tester: one strategy applied to every connection (no hostlists).
    static func tester(desync: [String], port: Int = testerPort) -> [String] {
        ["ciadpi", "-i", "127.0.0.1", "-p", String(port), "-c", "128", "-x", "1"] + desync
    }
}
