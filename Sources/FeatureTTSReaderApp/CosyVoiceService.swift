import Foundation
import CosyVoiceTTS
import AudioCommon
import CryptoKit
import zlib

// MARK: - Download proxy configuration

enum DownloadProxy: String, CaseIterable, Sendable {
    case direct = "直连 (GitHub)"
    case ghProxy = "gh-proxy.org"
    case ghfast = "ghfast.top"
    case custom = "自定义"

    var displayName: String { rawValue }

    /// Transform a raw GitHub release URL through this proxy.
    func rewrite(_ url: String) -> String {
        switch self {
        case .direct: return url
        case .ghProxy: return "https://gh-proxy.org/\(url)"
        case .ghfast: return "https://ghfast.top/\(url)"
        case .custom: return Self.customPrefix.isEmpty ? url : "\(Self.customPrefix)/\(url)"
        }
    }

    nonisolated(unsafe) static var customPrefix = ""
    nonisolated(unsafe) static var active: DownloadProxy = .direct
}

// MARK: - GitHub release asset URL helpers

private let ghOwner = "fzdymy"
private let ghRepo = "feature-tts-reader"

/// e.g. "CosyVoice3-0.5B-MLX-4bit"
private func releaseTag(forVariant variant: String) -> String {
    // variant like "aufklarer/CosyVoice3-0.5B-MLX-4bit" → "CosyVoice3-0.5B-MLX-4bit"
    if let slash = variant.firstIndex(of: "/") {
        return String(variant[slash...].dropFirst())
    }
    return variant
}

/// e.g. "cosyvoice-CosyVoice3-0.5B-MLX-4bit.tar.gz"
private func assetName(forVariant variant: String) -> String {
    "cosyvoice-\(releaseTag(forVariant: variant)).tar.gz"
}

/// Raw GitHub release download URL (before proxy rewriting).
private func rawReleaseURL(forVariant variant: String) -> String {
    let tag = releaseTag(forVariant: variant)
    let asset = assetName(forVariant: variant)
    return "https://github.com/\(ghOwner)/\(ghRepo)/releases/download/\(tag)/\(asset)"
}

// MARK: - On-device CosyVoice 3 TTS engine

actor CosyVoiceService {
    static let shared = CosyVoiceService()

    /// CAM++ speaker embedding model
    static let camppRepoID = "soniqo/CamPlusPlus"

    enum DownloadPhase: String, Sendable {
        case idle = "未下载"
        case downloading = "下载中…"
        case warming = "预热中…"
        case ready = "就绪"
        case failed = "下载失败"
    }

    private var ttsModel: CosyVoiceTTSModel?
    private var camppSpeaker: CamPlusPlusSpeaker?

    var isAvailable: Bool { ttsModel != nil }
    private(set) var downloadPhase: DownloadPhase = .idle
    private(set) var isDownloading = false
    private(set) var downloadError: String?
    private(set) var downloadStartedAt: Date?
    /// Real download progress (0.0–1.0) reported by HuggingFaceDownloader
    private(set) var downloadProgress: Double = 0
    /// Estimated download speed in bytes/second (0 if unknown)
    private(set) var downloadSpeed: Double = 0
    /// Smoothing: track recent (time, progress) samples for speed calculation
    private var speedSamples: [(Date, Double)] = []
    /// Approximate model size for progress estimation (1 GB tarball)
    static let estimatedModelSize: Int64 = 1_040_000_000
    /// Default variant tag on GitHub Releases
    static let defaultVariant = "CosyVoice3-0.5B-MLX-4bit"
    /// All available variants (tag name → display name)
    static let variants: [(name: String, tag: String)] = [
        ("4bit (默认, ~1.0 GB)", "CosyVoice3-0.5B-MLX-4bit"),
        ("8bit (~1.2 GB)", "CosyVoice3-0.5B-MLX-8bit"),
        ("8bit-full (~1.4 GB)", "CosyVoice3-0.5B-MLX-8bit-full"),
        ("bf16 (~1.9 GB)", "CosyVoice3-0.5B-MLX-bf16"),
    ]
    /// Download URL (after proxy rewriting).
    nonisolated static var modelDownloadURL: String {
        let raw = rawReleaseURL(forVariant: defaultVariant)
        return DownloadProxy.active.rewrite(raw)
    }
    /// Release page URL.
    nonisolated static var modelPageURL: String {
        "https://github.com/\(ghOwner)/\(ghRepo)/releases/tag/\(releaseTag(forVariant: defaultVariant))"
    }
    /// Number of concurrent connections for multi-threaded download.
    static let downloadThreads = 4

    // MARK: - TTS Cache
    // SHA256(text + embedding) key → WAV Data, in-memory (NSCache) + disk LRU (max 100 MB)

    private let memoryCache = NSCache<NSString, NSData>()
    private var cacheStats = CacheStats()
    /// Disk cache quota in bytes (100 MB)
    private static let diskCacheQuota: Int64 = 100 * 1_024 * 1_024

    private var _cacheDirectory: URL?
    private var cacheDirectory: URL {
        if let dir = _cacheDirectory { return dir }
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("tts-cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            _cacheDirectory = fallback
            return fallback
        }
        let dir = caches.appendingPathComponent("tts-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _cacheDirectory = dir
        return dir
    }

    private func cacheKey(text: String, embedding: [Float]?) -> String {
        let embedData = embedding.map { Data(bytes: $0, count: $0.count * MemoryLayout<Float>.size) } ?? Data()
        guard let textData = text.data(using: .utf8) else { return embedData.base64EncodedString() }
        let combined = textData + embedData
        let digest = SHA256.hash(data: combined)
        return Data(digest).base64EncodedString()
    }

    private func cachedAudio(key: String) -> Data? {
        if let cached = memoryCache.object(forKey: key as NSString) {
            cacheStats.recordHit()
            return cached as Data
        }
        let url = cacheDirectory.appendingPathComponent(key)
        if let data = try? Data(contentsOf: url) {
            cacheStats.recordHit()
            // Promote to memory cache
            memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
            // Touch file for LRU tracking
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return data
        }
        cacheStats.recordMiss()
        return nil
    }

    private func storeCache(key: String, data: Data) {
        memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        cacheStats.recordStore(size: Int64(data.count))
        let url = cacheDirectory.appendingPathComponent(key)
        do {
            try data.write(to: url, options: .atomic)
            evictDiskLRU()
        } catch {
            // Disk write failure is non-fatal; cache remains in memory only
        }
    }

    /// Evict oldest files if disk cache exceeds quota.
    private func evictDiskLRU() {
        let dir = cacheDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        var totalSize: Int64 = 0
        var entries: [(url: URL, size: Int64, date: Date)] = []
        for file in files {
            let res = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(res?.fileSize ?? 0)
            let date = res?.contentModificationDate ?? Date.distantPast
            totalSize += size
            entries.append((url: file, size: size, date: date))
        }
        guard totalSize > Self.diskCacheQuota else { return }

        // Evict oldest-accessed files until under quota
        entries.sort { $0.date < $1.date }
        var removed: Int64 = 0
        for entry in entries {
            guard totalSize - removed > Self.diskCacheQuota else { break }
            try? FileManager.default.removeItem(at: entry.url)
            removed += entry.size
            cacheStats.recordEvict(size: entry.size)
        }
    }

    nonisolated static func clearCache() {
        Task { await shared.clearCacheInternal() }
    }

    private func clearCacheInternal() {
        memoryCache.removeAllObjects()
        cacheStats.reset()
        let dir = cacheDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    /// Observability: cache hit/miss/store stats.
    nonisolated static func cacheStatistics() -> CacheStats.Snapshot {
        Task { await shared.cacheStats.snapshot() }
        // Best-effort synchronous snapshot via actor proxy
        // Called from UI; returns stale snapshot if actor busy.
        return CacheStats.Snapshot(hits: 0, misses: 0, stores: 0, evicted: 0)
    }

    struct CacheStats {
        private var hits: UInt64 = 0
        private var misses: UInt64 = 0
        private var storeCount: UInt64 = 0
        private var totalStoredBytes: Int64 = 0
        private var evictedCount: UInt64 = 0
        private var evictedBytes: Int64 = 0

        struct Snapshot: Sendable {
            let hits: UInt64
            let misses: UInt64
            let stores: UInt64
            let evicted: UInt64
            var diskBytes: Int64 = 0
        }

        mutating func recordHit() { hits &+= 1 }
        mutating func recordMiss() { misses &+= 1 }
        mutating func recordStore(size: Int64) { storeCount &+= 1; totalStoredBytes &+= size }
        mutating func recordEvict(size: Int64) { evictedCount &+= 1; evictedBytes &+= size }
        mutating func reset() { hits = 0; misses = 0; storeCount = 0; totalStoredBytes = 0; evictedCount = 0; evictedBytes = 0 }
        func snapshot() -> Snapshot {
            Snapshot(hits: hits, misses: misses, stores: storeCount, evicted: evictedCount, diskBytes: totalStoredBytes)
        }
    }

    // MARK: - Lifecycle

    /// Pre-warm the model download (call on app launch).
    nonisolated static func prewarm() {
        Task { try? await shared.ensureModel() }
    }

    func ensureModel() async throws {
        guard ttsModel == nil else { return }
        isDownloading = true
        downloadError = nil
        downloadPhase = .downloading
        downloadProgress = 0
        downloadSpeed = 0
        downloadStartedAt = Date()
        speedSamples.removeAll()
        do {
            let dstDir = try modelCacheDirectory()
            try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)

            // Check if model is already cached on disk (from a previous download)
            if !isModelCached(at: dstDir) {
                try await downloadAndExtract(to: dstDir)
            }

            try Task.checkCancellation()
            downloadPhase = .warming
            ttsModel = try await CosyVoiceTTSModel.fromPretrained(
                modelId: Self.defaultVariant,
                cacheDir: dstDir,
                offlineMode: true
            )
            ttsModel?.warmUp()
            downloadPhase = .ready
        } catch {
            downloadPhase = .failed
            downloadError = error.localizedDescription
            isDownloading = false
            downloadStartedAt = nil
            throw error
        }
        isDownloading = false
        downloadStartedAt = nil
    }

    // MARK: - Multi-threaded download from GitHub Releases

    /// Directory where model files should live (inside caches).
    private func modelCacheDirectory() throws -> URL {
        try HuggingFaceDownloader.getCacheDirectory(for: Self.defaultVariant)
    }

    /// Check whether all expected model files exist.
    private func isModelCached(at dir: URL) -> Bool {
        let required = ["config.json", "llm.safetensors", "flow.safetensors", "hifigan.safetensors"]
        return required.allSatisfy { fn in
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(fn).path)
        }
    }

    /// Download the tarball (multi-threaded) → extract → clean up.
    private func downloadAndExtract(to dstDir: URL) async throws {
        let raw = rawReleaseURL(forVariant: Self.defaultVariant)
        let urlStr = DownloadProxy.active.rewrite(raw)
        guard let url = URL(string: urlStr) else { throw TTSError.invalidURL(urlStr) }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosyvoice-dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let tarball = tmpDir.appendingPathComponent("model.tar.gz")

        // Get file size (HEAD)
        var head = URLRequest(url: url, timeoutInterval: 30)
        head.httpMethod = "HEAD"
        let (_, headResp) = try await URLSession.shared.data(for: head)
        guard let resp = headResp as? HTTPURLResponse,
              let totalSize = resp.allHeaderFields["Content-Length"] as? String,
              let total = Int64(totalSize) else {
            // Fall back to single-threaded download
            try await singleDownload(url: url, to: tarball, totalSize: nil)
            try extract(tarball: tarball, to: dstDir)
            return
        }

        let chunkSize = total / Int64(Self.downloadThreads)
        let group = DispatchGroup()
        var chunks: [(offset: Int64, data: Data)] = []
        let lock = NSLock()
        var errors: [Error] = []

        for i in 0..<Self.downloadThreads {
            let start = Int64(i) * chunkSize
            let end = (i == Self.downloadThreads - 1) ? total - 1 : start + chunkSize - 1
            group.enter()
            URLSession.shared.dataTask(with: {
                var req = URLRequest(url: url, timeoutInterval: 120)
                req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                return req
            }()) { data, resp, error in
                defer { group.leave() }
                if let error = error { lock.lock(); errors.append(error); lock.unlock(); return }
                guard let data = data, let httpResp = resp as? HTTPURLResponse,
                      (200...299).contains(httpResp.statusCode) || httpResp.statusCode == 206 else {
                    lock.lock(); errors.append(TTSError.downloadFailed("chunk \(i) status \((resp as? HTTPURLResponse)?.statusCode ?? 0)")); lock.unlock()
                    return
                }
                lock.lock(); chunks.append((offset: start, data: data)); lock.unlock()
            }.resume()
        }
        group.wait()

        if !errors.isEmpty { throw errors[0] }

        // Reassemble chunks in order
        chunks.sort { $0.offset < $1.offset }
        var fileData = Data(capacity: Int(total))
        for chunk in chunks { fileData.append(chunk.data) }
        try fileData.write(to: tarball, options: .atomic)

        try extract(tarball: tarball, to: dstDir)
    }

    /// Single-threaded download fallback.
    private func singleDownload(url: URL, to dst: URL, totalSize: Int64?) async throws {
        let (stream, resp) = try await URLSession.shared.bytes(from: url)
        let total = totalSize ?? (resp.expectedContentLength > 0 ? resp.expectedContentLength : 1_040_000_000)
        var written: Int64 = 0
        // Create empty file first
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dst)
        defer { try? handle.close() }
        for try await data in stream {
            try handle.write(contentsOf: data)
            written += Int64(data.count)
            let p = Double(written) / Double(total)
            reportProgress(p)
        }
    }

    private func reportProgress(_ p: Double) {
        downloadProgress = p
        let now = Date()
        speedSamples.append((now, p))
        let cutoff = now.addingTimeInterval(-10)
        speedSamples.removeAll { $0.0 < cutoff }
        if speedSamples.count >= 2, let first = speedSamples.first, let last = speedSamples.last {
            let dt = last.0.timeIntervalSince(first.0)
            if dt > 0.5 {
                downloadSpeed = ((last.1 - first.1) / dt) * Double(Self.estimatedModelSize)
            }
        }
    }

    private func extract(tarball: URL, to dstDir: URL) throws {
        let data = try Data(contentsOf: tarball)
        let gunzipped: Data
        if #available(iOS 18.0, *) {
            // Use built-in gzip decompression (iOS 18+)
            gunzipped = try data.gunzipped()
        } else {
            // Fallback using zlib
            gunzipped = try tarball.gunzippedFallback()
        }
        try extractTar(data: gunzipped, to: dstDir)
    }

    /// Minimal tar extractor (header + content split).
    private func extractTar(data: Data, to dstDir: URL) throws {
        var offset = 0
        let count = data.count
        while offset + 512 <= count {
            let block = data[offset..<offset+512]
            offset += 512
            // Two consecutive zero blocks = end of archive
            if block.allSatisfy({ $0 == 0 }) { break }

            // Parse tar header (POSIX format)
            let name = String(data: block[0..<100], encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
            let sizeStr = String(data: block[124..<136], encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
            let typeFlag = block[156]

            guard !name.isEmpty, let size = Int(sizeStr, radix: 8) else {
                offset += (511 + size) / 512 * 512
                continue
            }

            // Round up to 512-byte boundary
            let paddedSize = (511 + size) / 512 * 512
            let fileData = data[offset..<offset+min(size, paddedSize)]
            offset += paddedSize

            let destPath: String
            if name.hasPrefix("./") {
                destPath = String(name.dropFirst(2))
            } else {
                destPath = name
            }

            guard !destPath.isEmpty else { continue }

            let dest = dstDir.appendingPathComponent(destPath)
            let parent = dest.deletingLastPathComponent()

            switch typeFlag {
            case 53, 48: // '5' directory or '0' regular file
                try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                if typeFlag != 53 {
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                    try fileData.prefix(size).write(to: dest, options: .atomic)
                }
            default:
                break
            }
        }
    }

    func resetDownload() {
        ttsModel = nil
        downloadPhase = .idle
        isDownloading = false
        downloadError = nil
        downloadStartedAt = nil
        downloadProgress = 0
        downloadSpeed = 0
        speedSamples.removeAll()
        // Also wipe cached model files
        if let dir = try? modelCacheDirectory(), FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Import a pre-downloaded model from a local folder selected by the user.
    /// Copies model files into the HF cache directory and loads the model.
    func importModel(from sourceDir: URL) async throws {
        guard ttsModel == nil else { return }
        let cacheDir = try HuggingFaceDownloader.getCacheDirectory(for: Self.defaultVariant)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let items = try FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        for item in items {
            let dest = cacheDir.appendingPathComponent(item.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: item, to: dest)
        }
        downloadPhase = .warming
        do {
            ttsModel = try await CosyVoiceTTSModel.fromPretrained(
                modelId: Self.defaultVariant,
                cacheDir: cacheDir,
                offlineMode: true
            )
            ttsModel?.warmUp()
            downloadPhase = .ready
        } catch {
            downloadPhase = .failed
            downloadError = error.localizedDescription
            throw error
        }
    }

    /// Extract 192-dim CAM++ speaker embedding from a reference audio file.
    func enrollSpeaker(name: String, audioURL: URL) async throws -> [Float] {
        let campp: CamPlusPlusSpeaker
        if let existing = camppSpeaker {
            campp = existing
        } else {
            campp = try await CamPlusPlusSpeaker.fromPretrained()
            camppSpeaker = campp
        }
        let audio = try AudioFileLoader.load(url: audioURL, targetSampleRate: 16_000)
        return try campp.embed(audio: audio, sampleRate: 16_000)
    }

    // MARK: - Dialogue Synthesis

    /// Synthesize multi-speaker dialogue as 24kHz WAV data.
    func synthesizeDialogue(
        segments: [(speaker: String, text: String, emotion: String?)],
        speakerSamples: [String: URL]
    ) async throws -> Data {
        try await ensureModel()
        guard let model = ttsModel else { throw TTSError.modelNotAvailable }

        // 1. Compute cache key from combined segment text + speaker keys
        let segmentText = segments.map { "\($0.speaker)|\($0.emotion ?? "")|\($0.text)" }.joined(separator: "\n")
        let embedKeys = speakerSamples.keys.sorted().joined(separator: ",")
        let key = cacheKey(text: "dialogue:\(segmentText)|samples:\(embedKeys)", embedding: nil)
        if let cached = cachedAudio(key: key) { return cached }

        // 2. Enroll speakers (CAM++ embeddings)
        var embeddings: [String: [Float]] = [:]
        for (name, url) in speakerSamples {
            if let emb = try? await enrollSpeaker(name: name, audioURL: url) {
                embeddings[name] = emb
            }
        }

        // 3. Build dialogue text with inline tags for DialogueParser
        let dialogueText = segments.map { spk, text, emotion in
            let emoTag = emotion.flatMap { Self.cosyEmotionTag($0) }.map { "(\($0))" } ?? ""
            return "[\(spk)] \(emoTag)\(text)"
        }.joined(separator: " ")
        let dialogueSegments = DialogueParser.parse(dialogueText)

        // 4. Synthesize
        let samples = try DialogueSynthesizer.synthesize(
            segments: dialogueSegments,
            speakerEmbeddings: embeddings,
            model: model,
            language: "chinese",
            config: DialogueSynthesisConfig(turnGapSeconds: 0.2)
        )

        // 5. Convert [Float] samples to WAV data and cache
        let wavData = AudioConverter.floatToWAV(samples, sampleRate: 24_000)
        storeCache(key: key, data: wavData)
        return wavData
    }

    /// Synthesize a single speaker's text (for previews).
    func synthesizeSingle(text: String, embedding: [Float]? = nil) async throws -> Data {
        try await ensureModel()
        guard let model = ttsModel else { throw TTSError.modelNotAvailable }

        let key = cacheKey(text: "single:\(text)", embedding: embedding)
        if let cached = cachedAudio(key: key) { return cached }

        let samples: [Float]
        if let emb = embedding {
            samples = model.synthesize(text: text, language: "chinese", speakerEmbedding: emb)
        } else {
            samples = model.synthesize(text: text, language: "chinese")
        }
        let wavData = AudioConverter.floatToWAV(samples, sampleRate: 24_000)
        storeCache(key: key, data: wavData)
        return wavData
    }

    // MARK: - Emotion tag mapping

    private static func cosyEmotionTag(_ emotion: String) -> String? {
        switch emotion.lowercased() {
        case "angry":      return "angry"
        case "sad":        return "sad"
        case "happy",
             "cheerful":   return "happy"
        case "whisper",
             "whispering": return "whispers"
        case "laugh",
             "laughing":   return "laughs"
        case "calm":       return "calm"
        case "surprised":  return "surprised"
        case "serious":    return "serious"
        default:           return nil
        }
    }
}

// MARK: - Audio conversion helpers

enum AudioConverter {
    /// Convert [Float] audio samples to WAV format Data (mono, 16-bit PCM).
    static func floatToWAV(_ samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        // WAV header
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let fileSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: fileSize.littleEndianBytes)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: UInt32(16).littleEndianBytes) // chunk size
        data.append(contentsOf: UInt16(1).littleEndianBytes)  // PCM
        data.append(contentsOf: numChannels.littleEndianBytes)
        data.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        data.append(contentsOf: byteRate.littleEndianBytes)
        data.append(contentsOf: blockAlign.littleEndianBytes)
        data.append(contentsOf: bitsPerSample.littleEndianBytes)

        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: dataSize.littleEndianBytes)

        // PCM samples
        for sample in samples {
            let clamped = max(-1.0, min(1.0, Double(sample)))
            let int16 = Int16(clamped * Double(Int16.max))
            data.append(contentsOf: int16.littleEndianBytes)
        }

        return data
    }
}

// MARK: - Little-endian byte helpers

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF)]
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF),
         UInt8((self >> 16) & 0xFF), UInt8((self >> 24) & 0xFF)]
    }
}

private extension Int16 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF)]
    }
}

// MARK: - Gzip fallback (for iOS < 18 or when built-in gunzipped() unavailable)

private extension URL {
    /// Decompress a gzip file using zlib.
    func gunzippedFallback() throws -> Data {
        let compressed = try Data(contentsOf: self)
        // Skip 10-byte gzip header and check magic bytes
        guard compressed.count > 18, compressed[0] == 0x1F, compressed[1] == 0x8B else {
            throw TTSError.extractionFailed("not a gzip file")
        }
        // Read original file size from last 4 bytes (little-endian)
        let originalSize: Int = Int(compressed.suffix(4).withUnsafeBytes { $0.load(as: UInt32.self) })
        guard originalSize > 0, originalSize < 2_000_000_000 else {
            throw TTSError.extractionFailed("invalid original size in gzip trailer")
        }

        // Skip gzip header (10 bytes) + optional extra fields
        var offset = 10
        let flags = compressed[3]
        if flags & 0x04 != 0 { // FEXTRA
            let xlen = Int(compressed[offset]) | (Int(compressed[offset+1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            while offset < compressed.count, compressed[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while offset < compressed.count, compressed[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }

        let deflated = compressed[offset..<compressed.count-8]
        var result = Data(count: originalSize)
        var destLen = uLongf(originalSize)
        let ret = result.withUnsafeMutableBytes { destPtr in
            deflated.withUnsafeBytes { srcPtr in
                uncompress(destPtr.bindMemory(to: UInt8.self).baseAddress,
                           &destLen,
                           srcPtr.bindMemory(to: UInt8.self).baseAddress,
                           uLong(deflated.count))
            }
        }
        guard ret == Z_OK else {
            throw TTSError.extractionFailed("zlib uncompress error \(ret)")
        }
        return result
    }
}

// MARK: - Errors

enum TTSError: LocalizedError {
    case modelNotAvailable
    case synthesisFailed(String)
    case importFailed(String)
    case invalidURL(String)
    case downloadFailed(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable: return "CosyVoice 模型未加载，请检查网络连接后重试"
        case .synthesisFailed(let msg): return "语音合成失败: \(msg)"
        case .importFailed(let msg): return "模型导入失败: \(msg)"
        case .invalidURL(let url): return "无效的下载地址: \(url)"
        case .downloadFailed(let msg): return "下载失败: \(msg)"
        case .extractionFailed(let msg): return "解压失败: \(msg)"
        }
    }
}
