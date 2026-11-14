import Foundation

/// Tiny file logger shared by the app and the extension.
enum Log {
    private static let queue = DispatchQueue(label: "zapret.log")
    private static let maxSize: UInt64 = 512 * 1024

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String, to url: URL = Paths.tunnelLog) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            rotateIfNeeded(url)
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func rotateIfNeeded(_ url: URL, limit: UInt64 = maxSize) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size > limit else { return }
        let old = url.appendingPathExtension("old")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: url, to: old)
    }

    static func read(_ url: URL, maxBytes: Int = 200_000) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func clear(_ url: URL) {
        try? Data().write(to: url, options: .atomic)
    }
}
