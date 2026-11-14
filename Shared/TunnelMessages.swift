import Foundation

enum TunnelCommand: String, Codable {
    case status
    case reload
}

struct TunnelRequest: Codable {
    var command: TunnelCommand
}

struct TunnelStatus: Codable, Equatable {
    var network: NetworkKind
    var radio: String?
    var strategyID: String
    var engineRunning: Bool
    var startedAt: Date
    var txBytes: UInt64
    var rxBytes: UInt64
    var restarts: Int
    var lastError: String?
}

enum ByteFormat {
    static func string(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary)
    }
}
