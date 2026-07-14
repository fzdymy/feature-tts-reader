import Foundation

/// AI Worker 解析结果缓存：按 chapterID + text.hash 键值缓存到文件，LRU 淘汰
actor AIParseCache {
    private let maxEntries = 50
    private let maxStorageMB = 50.0
    private let cacheDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        cacheDir = docs.appendingPathComponent("ai_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Cache Entry

    struct CacheEntry: Codable {
        let key: String
        let segments: [AISegment]
        let timestamp: Date
        let chapterTitle: String
    }

    // MARK: - Public API

    func getSegments(chapter: BookChapter) -> [AISegment]? {
        let key = cacheKey(for: chapter)
        let url = cacheDir.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }
        // 更新访问时间（touch file）
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return entry.segments
    }

    func save(chapter: BookChapter, segments: [AISegment]) async {
        let key = cacheKey(for: chapter)
        let entry = CacheEntry(key: key, segments: segments, timestamp: Date(), chapterTitle: chapter.title)
        let url = cacheDir.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
        }
        await evictIfNeeded()
    }

    func invalidate(chapterID: UUID) {
        // 清除指定章节的缓存（需要遍历匹配）
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
               entry.key.starts(with: chapterID.uuidString.prefix(8)) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func invalidateAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Private

    private func cacheKey(for chapter: BookChapter) -> String {
        "\(chapter.id.uuidString.prefix(8))_\(abs(chapter.text.hashValue))"
    }

    private func evictIfNeeded() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        guard jsonFiles.count > maxEntries else { return }

        // 按修改时间排序，删除最旧的多余条目
        let sorted = jsonFiles.compactMap { url -> (URL, Date)? in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date else { return nil }
            return (url, modDate)
        }.sorted { $0.1 < $1.1 }

        let toDelete = sorted.prefix(sorted.count - maxEntries)
        for (url, _) in toDelete {
            try? FileManager.default.removeItem(at: url)
        }

        // Also enforce storage size limit
        guard let allFiles = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let allJson = allFiles.filter { $0.pathExtension == "json" }
        let totalSize = allJson.reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int) ?? 0) }
        let maxSizeBytes = Int(maxStorageMB * 1024 * 1024)
        if totalSize > maxSizeBytes {
            let sortedSize = allJson.compactMap { url -> (URL, Date)? in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let modDate = attrs[.modificationDate] as? Date else { return nil }
                return (url, modDate)
            }.sorted { $0.1 < $1.1 }
            var runningSize = totalSize
            for (file, _) in sortedSize {
                guard runningSize > maxSizeBytes else { break }
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
                try? FileManager.default.removeItem(at: file)
                runningSize -= fileSize
            }
        }
    }
    }

    /// 检查指定章节是否有缓存
    func hasCachedSegments(for chapter: BookChapter) -> Bool {
        let key = cacheKey(for: chapter)
        let url = cacheDir.appendingPathComponent("\(key).json")
        return FileManager.default.fileExists(atPath: url.path)
    }
}
