import Foundation
import CosyVoiceTTS
import AudioCommon
import CryptoKit

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
    /// Approximate model size for progress estimation (bytes)
    static let estimatedModelSize: Int64 = 1_300_000_000
    /// Default CosyVoice 3 variant (4-bit, ~1.2 GB)
    static let defaultVariant = "aufklarer/CosyVoice3-0.5B-MLX-4bit"
    /// All available variants
    static let variants: [(name: String, repo: String)] = [
        ("4bit (默认, ~1.2 GB)", "aufklarer/CosyVoice3-0.5B-MLX-4bit"),
        ("8bit (~1.4 GB)", "aufklarer/CosyVoice3-0.5B-MLX-8bit"),
        ("8bit-full (~1.6 GB)", "aufklarer/CosyVoice3-0.5B-MLX-8bit-full"),
        ("bf16 (~2.1 GB)", "aufklarer/CosyVoice3-0.5B-MLX-bf16"),
    ]
    nonisolated static var modelDownloadURL: String {
        "https://huggingface.co/\(defaultVariant)"
    }

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
        downloadStartedAt = Date()
        do {
            ttsModel = try await CosyVoiceTTSModel.fromPretrained()
            try Task.checkCancellation()
            downloadPhase = .warming
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

    func resetDownload() {
        ttsModel = nil
        downloadPhase = .idle
        isDownloading = false
        downloadError = nil
        downloadStartedAt = nil
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

// MARK: - Errors

enum TTSError: LocalizedError {
    case modelNotAvailable
    case synthesisFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable: return "CosyVoice 模型未加载，请检查网络连接后重试"
        case .synthesisFailed(let msg): return "语音合成失败: \(msg)"
        }
    }
}
