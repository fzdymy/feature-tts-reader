import Foundation
import os

/// 调试日志：每次 app 启动生成一个 .jsonl 文件追加写入 Documents/debug/
/// 每行一个 JSON 对象，方便一次性发送整个文件排查问题
enum DebugLogger {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
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
    private static let urlLock = OSAllocatedUnfairLock()
    private static var _fileURL: URL? = nil

    private static var fileURL: URL? {
        get { urlLock.withLock { _fileURL } }
        set { urlLock.withLock { _fileURL = newValue } }
    }

    /// 初始化日志文件（app 启动时调用一次）
    static func startSession() {
        let fn = "debug_\(dateFormatter.string(from: Date())).jsonl"
        fileURL = logDir?.appendingPathComponent(fn)
        log(flow: "session", step: "start", details: ["app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""])
    }

    /// 写入一行 JSON 到当前日志文件（追加模式）
    static func log(
        flow: String,
        step: String,
        details: [String: Any] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        let timestamp = isoFormatter.string(from: Date())
        var entry: [String: Any] = [
            "timestamp": timestamp,
            "flow": flow,
            "step": step,
            "file": file,
            "line": line,
        ]
        for (k, v) in details {
            entry[k] = v
        }

        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let lineStr = String(data: data, encoding: .utf8)
        else { return }
        let payload = lineStr + "\n"

        let url = fileURL ?? {
            let fn = "debug_\(dateFormatter.string(from: Date())).jsonl"
            let u = logDir?.appendingPathComponent(fn)
            fileURL = u
            return u
        }()
        guard let url else { return }

        queue.async {
            if FileManager.default.fileExists(atPath: url.path) {
                guard let fh = try? FileHandle(forWritingTo: url) else { return }
                try? fh.seekToEnd()
                try? fh.write(Data(payload.utf8))
                try? fh.close()
            } else {
                try? payload.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    /// 日志目录路径，用于 UI 显示
    static var logDirectoryPath: String {
        logDir?.path ?? ""
    }

    /// 当前会话日志文件路径
    static var currentSessionFile: URL? {
        fileURL
    }

    /// 列出所有日志文件名（按时间倒序）
    static var logFiles: [String] {
        guard let dir = logDir,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return files.filter { $0.hasPrefix("debug_") && $0.hasSuffix(".jsonl") }.sorted(by: >)
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
