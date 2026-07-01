import Foundation

struct Logger {
    static let fileName = "tts_reader_log.txt"
    private static let maxLogSize: UInt64 = 1_000_000 // 1MB

    static func log(_ message: String) {
        let logEntry = "[\(Date())] \(message)\n"
        guard let url = logFileURL() else { return }
        DispatchQueue.global(qos: .background).async {
            // Rotate if too large
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64, size > maxLogSize {
                let rotated = url.deletingLastPathComponent().appendingPathComponent("tts_reader_log_old.txt")
                try? FileManager.default.removeItem(at: rotated)
                try? FileManager.default.moveItem(at: url, to: rotated)
            }
            guard let data = logEntry.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                guard let fh = try? FileHandle(forWritingTo: url) else { return }
                try? fh.seekToEnd()
                try? fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func log(error: Error) {
        log("ERROR: \(error.localizedDescription)")
    }

    static func log(fileURL: URL) {
        log("FILE: \(fileURL.path)")
    }

    private static func logFileURL() -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(fileName)
    }
}
