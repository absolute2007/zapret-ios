import Foundation

/// A zapret-discord-youtube strategy adapted to what is possible on stock iOS.
///
/// On iOS there are no raw sockets, so TCP tricks that need hand-crafted
/// packets (`fake` with badseq/ts/md5sig fooling, `seqovl`, `syndata`) cannot
/// be reproduced. Each strategy is mapped by *intent* to the techniques that
/// work through regular sockets: split, disorder (TTL=1 segment), OOB,
/// TLS record fragmentation and HTTP header tampering. UDP fakes (QUIC,
/// Discord voice/STUN, games) are reproduced 1:1.
struct Strategy: Identifiable, Hashable {
    let id: String
    let name: String
    /// Original zapret file and its desync mode.
    let origin: String
    /// What the iOS adaptation does.
    let summary: String
    /// Desync args for list-general (+ user list).
    let general: [String]
    /// Desync args for list-google (YouTube).
    let google: [String]

    init(_ id: String, _ name: String, origin: String, summary: String, general: String, google: String? = nil) {
        self.id = id
        self.name = name
        self.origin = origin
        self.summary = summary
        self.general = Strategy.split(general)
        self.google = Strategy.split(google ?? general)
    }

    static func split(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
    }
}

enum StrategyCatalog {
    static let defaultWifi = "general"
    static let defaultCellular = "mobile"
    static let customID = "custom"

    private static let hostSplit = "--split 0+s --disorder 0+se"

    static let all: [Strategy] = [
        Strategy("general", "general",
                 origin: "general.bat · multisplit + seqovl",
                 summary: "Разрез после 1-го байта, disorder внутри SNI и разбиение TLS-записи.",
                 general: "--split 1 --disorder 1+s --tlsrec 1+s"),
        Strategy("mobile", "Mobile (iOS)",
                 origin: "Только для iOS · подобрана под мобильные DPI",
                 summary: "Split + disorder после SNI + TLS-запись + смена регистра Host. Хорошо переживает CGNAT операторов.",
                 general: "--split 1 --disorder 3+s --tlsrec 1+s --mod-http h,d"),
        Strategy("alt", "ALT",
                 origin: "general (ALT).bat · fake,fakedsplit (ts)",
                 summary: "Disorder первого байта + TLS-запись в SNI.",
                 general: "--disorder 1 --tlsrec 1+s"),
        Strategy("alt2", "ALT2",
                 origin: "general (ALT2).bat · multisplit seqovl=652 pos=2",
                 summary: "Разрез после 2-го байта + TLS-запись.",
                 general: "--split 2 --tlsrec 2+s"),
        Strategy("alt3", "ALT3",
                 origin: "general (ALT3).bat · fake,hostfakesplit",
                 summary: "Разрез по началу SNI, disorder середины SNI, TLS-запись в середине SNI.",
                 general: "--split 0+s --disorder 0+sm --tlsrec 0+sm"),
        Strategy("alt4", "ALT4",
                 origin: "general (ALT4).bat · fake,multisplit (badseq)",
                 summary: "OOB-байт после 1-го байта + TLS-запись.",
                 general: "--oob 1 --tlsrec 1+s"),
        Strategy("alt5", "ALT5",
                 origin: "general (ALT5).bat · syndata,multidisorder",
                 summary: "Двойной disorder: 1-й байт и SNI.",
                 general: "--disorder 1 --disorder 1+s"),
        Strategy("alt6", "ALT6",
                 origin: "general (ALT6).bat · multisplit seqovl=681",
                 summary: "Разрез после 1-го байта + TLS-запись.",
                 general: "--split 1 --tlsrec 1+s"),
        Strategy("alt7", "ALT7",
                 origin: "general (ALT7).bat · multisplit pos=2,sniext+1",
                 summary: "Разрезы на 2-м байте и в SNI + TLS-запись.",
                 general: "--split 2 --split 1+s --tlsrec 1+s"),
        Strategy("alt8", "ALT8",
                 origin: "general (ALT8).bat · fake (badseq=2)",
                 summary: "Disorder с OOB-байтом + TLS-запись.",
                 general: "--disoob 1 --tlsrec 1+s"),
        Strategy("alt9", "ALT9",
                 origin: "general (ALT9).bat · hostfakesplit (md5sig)",
                 summary: "Хост вырезается в отдельный сегмент, хвост уходит в disorder.",
                 general: hostSplit),
        Strategy("alt10", "ALT10",
                 origin: "general (ALT10).bat · fake (ts)",
                 summary: "Только disorder первого байта — минимальное вмешательство.",
                 general: "--disorder 1"),
        Strategy("alt11", "ALT11",
                 origin: "general (ALT11).bat · fake,multisplit seqovl=664",
                 summary: "Split + OOB в SNI + TLS-запись.",
                 general: "--split 1 --oob 1+s --tlsrec 1+s"),
        Strategy("alt12", "ALT12",
                 origin: "general (ALT12).bat · hostfakesplit / fake,multisplit",
                 summary: "YouTube: вырезание хоста; остальные: OOB в SNI + TLS-запись.",
                 general: "--oob 1+s --tlsrec 3+s", google: hostSplit),
        Strategy("alt13", "ALT13",
                 origin: "general (ALT13).bat · fake,hostfakesplit",
                 summary: "YouTube: вырезание хоста; остальные: disoob в SNI + TLS-запись.",
                 general: "--disoob 1+s --tlsrec 1+s", google: hostSplit),
        Strategy("exp", "EXP",
                 origin: "general (EXP).bat · fake,multisplit seqovl=480",
                 summary: "Disorder + разрез в середине SNI + TLS-запись.",
                 general: "--disorder 1 --split 1+sm --tlsrec 1+s", google: hostSplit),
        Strategy("fta", "FAKE TLS AUTO",
                 origin: "general (FAKE TLS AUTO).bat · fake,multidisorder 1,midsld",
                 summary: "Multidisorder: 1-й байт и середина SNI + TLS-запись.",
                 general: "--disorder 1 --disorder 1+sm --tlsrec 1+s"),
        Strategy("fta_alt", "FAKE TLS AUTO ALT",
                 origin: "general (FAKE TLS AUTO ALT).bat · fake,fakedsplit",
                 summary: "Disorder + TLS-запись в середине SNI.",
                 general: "--disorder 1 --tlsrec 1+sm"),
        Strategy("fta_alt2", "FAKE TLS AUTO ALT2",
                 origin: "general (FAKE TLS AUTO ALT2).bat · fake,multisplit seqovl",
                 summary: "Split + TLS-запись в середине SNI.",
                 general: "--split 1 --tlsrec 1+sm"),
        Strategy("fta_alt3", "FAKE TLS AUTO ALT3",
                 origin: "general (FAKE TLS AUTO ALT3).bat · fake,multisplit (ts)",
                 summary: "OOB + TLS-запись в середине SNI.",
                 general: "--oob 1 --tlsrec 1+sm"),
        Strategy("sf", "SIMPLE FAKE",
                 origin: "general (SIMPLE FAKE).bat · fake (ts)",
                 summary: "Только разбиение TLS-записи (YouTube — вырезание хоста).",
                 general: "--tlsrec 1+s", google: hostSplit),
        Strategy("sf_alt", "SIMPLE FAKE ALT",
                 origin: "general (SIMPLE FAKE ALT).bat · fake (badseq)",
                 summary: "Один OOB-байт внутри SNI.",
                 general: "--oob 1+s"),
        Strategy("sf_alt2", "SIMPLE FAKE ALT2",
                 origin: "general (SIMPLE FAKE ALT2).bat · fake (ts)",
                 summary: "Disorder внутри SNI.",
                 general: "--disorder 1+s"),
    ]

    /// Recipes tried automatically (byedpi --auto=torst,ssl_err) when a
    /// connection to a listed host looks blocked.
    static let fallbacks: [[String]] = [
        Strategy.split("--disorder 1 --tlsrec 1+s"),
        Strategy.split("--oob 1+s --tlsrec 3+s"),
        Strategy.split("--split 2 --disoob 1+sm"),
    ]

    static func custom(_ args: String) -> Strategy {
        Strategy(customID, "Свои параметры",
                 origin: "Ручная настройка",
                 summary: args.isEmpty ? "Без десинхронизации" : args,
                 general: args)
    }

    static func strategy(id: String, config: AppConfig) -> Strategy {
        if id == customID { return custom(config.customArgs) }
        return all.first(where: { $0.id == id }) ?? all[0]
    }

    static func name(for id: String) -> String {
        if id == customID { return "Свои параметры" }
        return all.first(where: { $0.id == id })?.name ?? id
    }
}
