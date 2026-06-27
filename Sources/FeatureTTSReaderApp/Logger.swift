import Foundation

struct Logger {
    static let fileName = "tts_reader_log.txt"

    static func log(_ message: String) {
        let logEntry = "[\(Date())] \(message)\n"
        guard let url = logFileURL() else { return }
        DispatchQueue.global(qos: .background).async {
            if let data = logEntry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let fh = try? FileHandle(forWritingTo: url) {
                        fh.seekToEndOfFile()
                        fh.write(data)
                        try? fh.close()
                    }
                } else {
                    try? data.write(to: url, options: .atomic)
                }
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
