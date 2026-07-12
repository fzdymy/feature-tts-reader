import Foundation

/// 调试日志：每次调用生成一个独立的时间戳 JSON 文件到 app Documents/debug/ 目录
enum DebugLogger {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return f
    }()

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f
    }()

    private static var logDir: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let dir = docs?.appendingPathComponent("debug", isDirectory: true)
        if let dir, !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static let queue = DispatchQueue(label: "com.featuretts.debuglogger", qos: .utility)

    /// 写入一条结构化日志（JSON 对象，字段按字母序确保可读性）
    static func log(
        flow: String,
        step: String,
        details: [String: Any] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        let timestamp = Date()
        let filename = "debug_\(dateFormatter.string(from: timestamp)).json"
        guard let dir = logDir else { return }

        var entry: [String: Any] = [
            "timestamp": isoFormatter.string(from: timestamp),
            "flow": flow,
            "step": step,
            "file": file,
            "line": line,
        ]
        for (k, v) in details {
            entry[k] = v
        }

        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys]) else { return }

        let url = dir.appendingPathComponent(filename)
        queue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 日志目录路径，用于 UI 显示
    static var logDirectoryPath: String {
        logDir?.path ?? ""
    }

    /// 列出所有日志文件名（按时间倒序）
    static var logFiles: [String] {
        guard let dir = logDir,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return files.filter { $0.hasPrefix("debug_") && $0.hasSuffix(".json") }.sorted(by: >)
    }

    /// 清理超过 N 天的日志
    static func clean(olderThanDays days: Int = 7) {
        queue.async {
            guard let dir = logDir else { return }
            let cutoff = Date().addingTimeInterval(-Double(days * 86400))
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
            for f in files {
                let url = dir.appendingPathComponent(f)
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let mtime = attrs[.modificationDate] as? Date,
                      mtime < cutoff
                else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
