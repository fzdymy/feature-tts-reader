import Foundation
import CosyVoiceTTS
import AudioCommon
import CryptoKit
import zlib
import os

// MARK: - Download proxy configuration

private let _proxyLock = OSAllocatedUnfairLock()
nonisolated(unsafe) private var _proxyActive: DownloadProxy = .direct
nonisolated(unsafe) private var _proxyCustomPrefix = ""
private let _variantLock = OSAllocatedUnfairLock()
nonisolated(unsafe) private var _activeVariant = "CosyVoice3-0.5B-MLX-bf16"

enum DownloadProxy: String, CaseIterable, Sendable {
    case direct = "直连 (GitHub)"
    case ghProxy = "gh-proxy.org"
    case ghfast = "ghfast.top"
    case custom = "自定义"

    var displayName: String { rawValue }

    func rewrite(_ url: String) -> String {
        switch self {
        case .direct: return url
        case .ghProxy: return "https://gh-proxy.org/\(url)"
        case .ghfast: return "https://ghfast.top/\(url)"
        case .custom:
            let prefix = _proxyLock.withLock { _proxyCustomPrefix }
            return prefix.isEmpty ? url : "\(prefix)/\(url)"
        }
    }

    static var active: DownloadProxy {
        get { _proxyLock.withLock { _proxyActive } }
        set { _proxyLock.withLock { _proxyActive = newValue } }
    }

    static var customPrefix: String {
        get { _proxyLock.withLock { _proxyCustomPrefix } }
        set { _proxyLock.withLock { _proxyCustomPrefix = newValue } }
    }
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
    let tag = releaseTag(forVariant: variant)
    let ext = DownloadProxy.active == .custom ? "zip" : "tar.gz"
    return "cosyvoice-\(tag).\(ext)"
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
    /// Approximate model size for progress estimation (1.2 GB tarball)
    static let estimatedModelSize: Int64 = 1_900_000_000
    /// Active variant (persisted via UserDefaults in Lifecycle + setVariant).
    nonisolated static var activeVariant: String {
        get { _variantLock.withLock { _activeVariant } }
        set { _variantLock.withLock { _activeVariant = newValue } }
    }
    /// All available variants (tag name → display name)
    static let variants: [(name: String, tag: String)] = [
        ("4bit (~1.0 GB, ❌)", "CosyVoice3-0.5B-MLX-4bit"),
        ("8bit (~1.2 GB, ⚠️)", "CosyVoice3-0.5B-MLX-8bit"),
        ("8bit-full (~1.4 GB, ⚠️)", "CosyVoice3-0.5B-MLX-8bit-full"),
        ("bf16 (推荐, ~1.9 GB)", "CosyVoice3-0.5B-MLX-bf16"),
    ]
    /// Download URL (after proxy rewriting).
    nonisolated static var modelDownloadURL: String {
        if DownloadProxy.active == .custom {
            let tag = releaseTag(forVariant: activeVariant)
            let prefix = _proxyLock.withLock { _proxyCustomPrefix }
            let base = prefix.hasSuffix("/") ? prefix : "\(prefix)/"
            return "\(base)cosyvoice-\(tag).zip"
        }
        let raw = rawReleaseURL(forVariant: activeVariant)
        return DownloadProxy.active.rewrite(raw)
    }
    /// Release page URL.
    nonisolated static var modelPageURL: String {
        "https://github.com/\(ghOwner)/\(ghRepo)/releases/tag/\(releaseTag(forVariant: activeVariant))"
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
    nonisolated static func cacheStatistics() async -> CacheStats.Snapshot {
        await shared.cacheStats.snapshot()
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

    /// Change the active variant and reset the loaded model.
    func setVariant(_ variant: String) {
        let old = Self.activeVariant
        Self.activeVariant = variant
        UserDefaults.standard.set(variant, forKey: "cosyvoice_active_variant")
        if variant != old { resetDownload() }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "cosyvoice_active_variant")
        if let saved = saved, Self.variants.contains(where: { $0.tag == saved }) {
            Self.activeVariant = saved
        }
        // else: keep the default set in the global var initializer
    }

    /// Cancellable download task (set before download starts, cleared after).
    private var activeDownloadTask: Task<Void, Error>?
    /// Retained to keep download delegate alive across async boundaries.
    private var downloadSession: URLSession?
    private var downloadDelegate: _DownloadDelegate?

    func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        // Invalidate session to cancel actual network request immediately.
        // The delegate stays alive until defer in downloadStreaming cleans up.
        downloadSession?.invalidateAndCancel()
        // Reset state regardless of current phase
        downloadPhase = .failed
        downloadError = "用户取消了下载"
        isDownloading = false
        downloadStartedAt = nil
    }

    func ensureModel() async throws {
        guard ttsModel == nil else { return }
        ReaderStore.writeCrashMarker("ensureModel_start")

        // Cancel any previous pending download
        activeDownloadTask?.cancel()
        activeDownloadTask = nil

        isDownloading = true
        downloadError = nil
        downloadPhase = .downloading
        downloadProgress = 0
        downloadSpeed = 0
        downloadStartedAt = Date()
        speedSamples.removeAll()
        do {
            let rootCache = try modelCacheDirectory()
            let stagingDir = try stagingDirectory()
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            if !isModelCached(at: try hfSnapshotsDirectory()) {
                ReaderStore.writeCrashMarker("download_start")
                // Wrap download in a cancellable Task
                activeDownloadTask = Task {
                    try await downloadAndExtract(to: stagingDir)
                }
                defer { activeDownloadTask = nil }
                try await activeDownloadTask!.value
                try Task.checkCancellation()
                ReaderStore.writeCrashMarker("download_done")

                // Arrange files into HuggingFace cache structure
                try setupHuggingFaceCache(from: stagingDir)
                // Clean up staging
                try? FileManager.default.removeItem(at: stagingDir)
            }

            try Task.checkCancellation()
            let snapDir = try hfSnapshotsDirectory()
            guard isModelCached(at: snapDir) else {
                throw TTSError.extractionFailed("缓存校验失败：模型文件不完整或尺寸异常，请重新下载")
            }
            try checkAvailableMemory()
            // Log cache state for debugging
            os_log("[TTS] ensureModel: cacheDir=%@, snapDir=%@, variant=%@", type: .debug,
                   rootCache.path, snapDir.path, Self.activeVariant)
            if let files = try? FileManager.default.contentsOfDirectory(at: snapDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    os_log("[TTS]   snap file: %@ (%lld bytes)", type: .debug, f.lastPathComponent, size)
                }
            }
            // Validate model files can be read before calling the library
            try validateModelFiles(at: snapDir)
            ReaderStore.writeCrashMarker("model_warm_start")
            downloadPhase = .warming
            ttsModel = try await CosyVoiceTTSModel.fromPretrained(
                modelId: Self.activeVariant,
                cacheDir: rootCache,
                offlineMode: true
            )
            ReaderStore.writeCrashMarker("model_load_done")
            ttsModel?.warmUp()
            downloadPhase = .ready
            ReaderStore.writeCrashMarker("model_warm_done")
        } catch {
            downloadPhase = .failed
            if error is CancellationError || (error as NSError).code == URLError.cancelled.rawValue {
                downloadError = "用户取消了下载"
            } else {
                let desc = error.localizedDescription
                if desc.contains("must be 8-bit quantized") || desc.contains("plain Linear") {
                    downloadError = "模型格式不兼容，请改用 8bit 或 bf16 变体（当前变体 \(Self.activeVariant) 不被该库支持）"
                } else {
                    downloadError = desc
                }
            }
            isDownloading = false
            downloadStartedAt = nil
            ReaderStore.writeCrashMarker("ensureModel_failed:\(error.localizedDescription.prefix(60))")
            throw error
        }
        isDownloading = false
        downloadStartedAt = nil
    }

    // MARK: - Multi-threaded download from GitHub Releases

/// Root HuggingFace-style cache directory.
private func modelCacheDirectory() throws -> URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    return caches.appendingPathComponent("com.cosyvoice/models")
}

/// HF cache directory for the current variant: .../models--<variant>/
private func hfModelCacheDirectory() throws -> URL {
    try modelCacheDirectory().appendingPathComponent("models--\(Self.activeVariant)")
}

/// HF snapshot directory: .../models--<variant>/snapshots/downloaded/
private func hfSnapshotsDirectory() throws -> URL {
    try hfModelCacheDirectory().appendingPathComponent("snapshots/downloaded")
}

/// Temp staging directory for raw extraction.
private func stagingDirectory() throws -> URL {
    try modelCacheDirectory().appendingPathComponent(".staging-\(Self.activeVariant)")
}

/// Move extracted model files into the HuggingFace cache layout and create refs.
private func setupHuggingFaceCache(from staging: URL) throws {
    let destDir = try hfSnapshotsDirectory()
    let refsDir = try hfModelCacheDirectory().appendingPathComponent("refs")

    os_log("[TTS] setupHuggingFaceCache: staging=%@, dest=%@", type: .debug, staging.path, destDir.path)

    // Log what's in staging
    if let items = try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.fileSizeKey]) {
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            os_log("[TTS]   staging file: %@ (%lld bytes)", type: .debug, item.lastPathComponent, size)
        }
    }

    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)

    // Flatten subdirectories first (zip may unpack to a top-level dir)
    flattenSubdirectories(at: staging)

    // Move all files from staging into snapshots/downloaded/
    let items = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    for item in items {
        let dest = destDir.appendingPathComponent(item.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: item, to: dest)
        os_log("[TTS]   moved -> %@", type: .debug, dest.lastPathComponent)
    }

    // Write refs/main so the library resolves the snapshot
    let refsFile = refsDir.appendingPathComponent("main")
    try "downloaded".write(to: refsFile, atomically: true, encoding: .utf8)
}

    /// Check whether all expected model files exist and have reasonable sizes.
    /// Also searches one level of subdirectories (zip may unpack to a top-level dir).
    private func isModelCached(at dir: URL) -> Bool {
        let required: [(name: String, minBytes: Int64)] = [
            ("config.json", 50),
            ("llm.safetensors", 1_000_000),
            ("flow.safetensors", 1_000_000),
            ("hifigan.safetensors", 100_000),
            ("speech_tokenizer.safetensors", 10_000),
        ]

        // Collect all files in dir and one level of subdirs
        var entries: [URL] = []
        if let top = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        ) {
            entries = top
            for entry in top where entry.hasDirectoryPath {
                if let sub = try? FileManager.default.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
                ) {
                    entries.append(contentsOf: sub)
                }
            }
        }

        for (fn, minBytes) in required {
            let match = entries.first { url in
                url.lastPathComponent == fn
                && (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) >= minBytes } == true
            }
            if match == nil {
                let sizeStr = entries.filter { $0.lastPathComponent == fn }.compactMap {
                    (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { "\($0)b" }
                }.joined(separator: ", ")
                os_log("[TTS] isModelCached: missing or too small %@ (found: %@, min: %lld)", type: .debug, fn, sizeStr.isEmpty ? "none" : sizeStr, minBytes)
                return false
            }
        }
        return true
    }

    /// If model files ended up in a subdirectory (common zip structure), move them up one level.
    private func flattenSubdirectories(at dir: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        for entry in entries where entry.hasDirectoryPath {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: entry, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            for file in files {
                let dest = dir.appendingPathComponent(file.lastPathComponent)
                // Don't overwrite existing files
                guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
                try? FileManager.default.moveItem(at: file, to: dest)
            }
        }
    }

    /// Verify model files are readable before calling the library.
    /// Prevents crashes from corrupted or wrong-format files.
    private func validateModelFiles(at dir: URL) throws {
        // Check config.json is valid JSON
        let configURL = dir.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL),
              let configJSON = try? JSONSerialization.jsonObject(with: configData) as? [String: Any]
        else {
            throw TTSError.importFailed("config.json 无法解析，模型文件可能已损坏")
        }
        // Check each safetensors file starts with valid JSON metadata
        let tensorFiles = ["llm.safetensors", "flow.safetensors", "hifigan.safetensors", "speech_tokenizer.safetensors"]
        for fn in tensorFiles {
            let url = dir.appendingPathComponent(fn)
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                throw TTSError.importFailed("无法读取 \(fn)，文件可能已损坏")
            }
            // Read the first 8 bytes to get the JSON header length (little-endian u64)
            guard let headerLenData = try? handle.read(upToCount: 8), headerLenData.count == 8 else {
                try? handle.close()
                throw TTSError.importFailed("\(fn) 文件格式异常")
            }
            try? handle.close()
        }
    }

    /// Check available memory; throw if too low to load the model.
    private func checkAvailableMemory() throws {
        let available = os_proc_available_memory()
        // Require at least 500 MB free for model loading overhead
        guard available >= 500_000_000 else {
            throw TTSError.downloadFailed("设备可用内存不足（仅剩 \(available / 1_000_000) MB），无法加载模型")
        }
    }

    /// Download the archive → extract → clean up.
    private func downloadAndExtract(to dstDir: URL) async throws {
        let urlStr: String
        let isZip: Bool
        if DownloadProxy.active == .custom {
            let tag = releaseTag(forVariant: Self.activeVariant)
            let prefix = _proxyLock.withLock { _proxyCustomPrefix }
            let base = prefix.hasSuffix("/") ? prefix : "\(prefix)/"
            urlStr = "\(base)cosyvoice-\(tag).zip"
            isZip = true
        } else {
            let raw = rawReleaseURL(forVariant: Self.activeVariant)
            urlStr = DownloadProxy.active.rewrite(raw)
            isZip = false
        }
        guard let url = URL(string: urlStr) else { throw TTSError.invalidURL(urlStr) }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosyvoice-dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let archiveFile = tmpDir.appendingPathComponent("model.\(isZip ? "zip" : "tar.gz")")

        reportProgress(0)
        let tempFile = try await downloadStreaming(url: url)
        try FileManager.default.moveItem(at: tempFile, to: archiveFile)
        if isZip {
            try extractZip(archive: archiveFile, to: dstDir)
        } else {
            try extract(tarball: archiveFile, to: dstDir)
        }
        guard isModelCached(at: dstDir) else {
            throw TTSError.extractionFailed("解压后缺少必要文件，请重新下载")
        }
    }

    /// Download with streaming progress via retained delegate.
    private func downloadStreaming(url: URL) async throws -> URL {
        let delegate = _DownloadDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        downloadSession = session
        downloadDelegate = delegate

        let task = session.downloadTask(with: URLRequest(url: url, timeoutInterval: 600))
        // Poll progress via KVO observation
        let obs = task.progress.observe(\.fractionCompleted, options: .initial) { [weak self] p, _ in
            Task { [weak self] in await self?.reportProgress(p.fractionCompleted) }
        }
        task.resume()

        defer {
            obs.invalidate()
            downloadSession = nil
            downloadDelegate = nil
        }

        return try await delegate.result
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
        let gunzipped = try tarball.gunzippedFallback()
        try extractTar(data: gunzipped, to: dstDir)
    }

    /// Minimal tar extractor (header + content split).
    private func extractTar(data: Data, to dstDir: URL) throws {
        var offset = 0
        let count = data.count
        while offset + 512 <= count {
            let block = data[offset..<offset+512]
            offset += 512
            if block.allSatisfy({ $0 == 0 }) { break }

            let name = String(data: block[0..<100], encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
            let sizeStr = String(data: block[124..<136], encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
            let typeFlag = block[156]

            guard !name.isEmpty, let fileSize = Int(sizeStr, radix: 8) else {
                continue
            }

            let paddedSize = (511 + fileSize) / 512 * 512
            guard offset + paddedSize <= count else { break }

            let fileData = data[offset..<offset + paddedSize]
            offset += paddedSize

            let destPath = name.hasPrefix("./") ? String(name.dropFirst(2)) : name
            guard !destPath.isEmpty else { continue }

            let dest = dstDir.appendingPathComponent(destPath)
            let parent = dest.deletingLastPathComponent()

            switch typeFlag {
            case 53: // directory
                try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            case 48, 0: // regular file
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try fileData.prefix(fileSize).write(to: dest, options: .atomic)
            default:
                break
            }
        }
    }

    /// Extract a .zip archive using zlib raw inflate.
    /// Uses memory-mapped file (`mappedIfSafe`) to avoid loading the entire ~1.2 GB zip into RAM.
    private func extractZip(archive: URL, to dstDir: URL) throws {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        var offset = 0

        // First pass: detect a common top-level directory prefix
        var commonPrefix: String? = nil
        var tempOff = 0
        while tempOff + 30 <= data.count {
            let sig = readLEU32(data, tempOff)
            guard sig == 0x04034b50 else { tempOff += 1; continue }
            let nameLen = Int(readLEU16(data, tempOff + 26))
            let extraLen = Int(readLEU16(data, tempOff + 28))
            let compSize = Int(readLEU32(data, tempOff + 18))
            let hdrSize = 30 + nameLen + extraLen
            guard tempOff + hdrSize + compSize <= data.count else { break }
            if nameLen > 0, tempOff + 30 + nameLen <= data.count, let name = String(data: data[tempOff+30..<tempOff+30+nameLen], encoding: .utf8), !name.isEmpty {
                if let slash = name.firstIndex(of: "/") {
                    let top = String(name[name.startIndex...slash])
                    if commonPrefix == nil { commonPrefix = top }
                    else if commonPrefix != top || top == "" { commonPrefix = nil; break }
                } else {
                    commonPrefix = nil
                    break
                }
            }
            tempOff += hdrSize + compSize
        }

        // Second pass: extract files, stripping the common prefix
        offset = 0
        while offset + 30 <= data.count {
            let sig = readLEU32(data, offset)
            guard sig == 0x04034b50 else { offset += 1; continue }

            let compression = Int(readLEU16(data, offset + 8))
            let compressedSize = Int(readLEU32(data, offset + 18))
            let uncompressedSize = Int(readLEU32(data, offset + 22))
            let nameLength = Int(readLEU16(data, offset + 26))
            let extraLength = Int(readLEU16(data, offset + 28))

            let headerSize = 30 + nameLength + extraLength
            guard offset + headerSize + compressedSize <= data.count else { break }
            guard nameLength > 0 else { offset += headerSize + compressedSize; continue }

            let rawName = String(data: data[offset+30..<offset+30+nameLength], encoding: .utf8) ?? ""
            let fileData = data[offset+headerSize..<offset+headerSize+compressedSize]
            offset += headerSize + compressedSize

            var cleanName = rawName.hasPrefix("./") ? String(rawName.dropFirst(2)) : rawName
            // Strip common prefix dir if detected
            if let prefix = commonPrefix, cleanName.hasPrefix(prefix) {
                cleanName = String(cleanName.dropFirst(prefix.count))
            }

            guard !cleanName.isEmpty, !cleanName.contains("..") else { continue }

            let dest = dstDir.appendingPathComponent(cleanName)
            let parent = dest.deletingLastPathComponent()

            if cleanName.hasSuffix("/") || cleanName.hasSuffix("\\") {
                try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                continue
            }

            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

            if compression == 0 {
                try Data(fileData).write(to: dest, options: .atomic)
            } else if compression == 8 {
                let decompressed = try Data(fileData).rawInflate(uncompressedSize: uncompressedSize)
                try decompressed.write(to: dest, options: .atomic)
            } else {
                throw TTSError.extractionFailed("不支持的 zip 压缩方式: \(compression)")
            }
        }
    }

    /// Read a little-endian UInt16 from Data at offset.
    private func readLEU16(_ data: Data, _ off: Int) -> UInt16 {
        UInt16(data[off]) | (UInt16(data[off+1]) << 8)
    }

    /// Read a little-endian UInt32 from Data at offset.
    private func readLEU32(_ data: Data, _ off: Int) -> UInt32 {
        UInt32(data[off]) | (UInt32(data[off+1]) << 8) | (UInt32(data[off+2]) << 16) | (UInt32(data[off+3]) << 24)
    }

    func resetDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        downloadDelegate = nil
        ttsModel = nil
        downloadPhase = .idle
        isDownloading = false
        downloadError = nil
        downloadStartedAt = nil
        downloadProgress = 0
        downloadSpeed = 0
        speedSamples.removeAll()
        // Also wipe cached model files
        if let dir = try? hfModelCacheDirectory(), FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        // Also clean up any staging dir
        if let staging = try? stagingDirectory(), FileManager.default.fileExists(atPath: staging.path) {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    /// Import a pre-downloaded model from a local folder or .tar.gz archive selected by the user.
    /// Copies model files into the cache directory and loads the model.
    func importModel(from sourceURL: URL) async throws {
        guard ttsModel == nil else { return }
        ReaderStore.writeCrashMarker("importModel_start")
        let rootCache = try modelCacheDirectory()
        let stagingDir = try stagingDirectory()
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        var sourceDir = sourceURL

        // If the selected URL is a .tar.gz archive, extract it first
        if sourceURL.lastPathComponent.hasSuffix(".tar.gz") || sourceURL.pathExtension == "gz" {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("cosyvoice-import-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let localArchive = tmpDir.appendingPathComponent("model.tar.gz")
            try FileManager.default.copyItem(at: sourceURL, to: localArchive)
            try extract(tarball: localArchive, to: tmpDir)
            sourceDir = tmpDir
        }

        // Copy model files from source directory to staging
        let items = try FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        for item in items {
            let dest = stagingDir.appendingPathComponent(item.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: item, to: dest)
        }

        // Arrange into HuggingFace cache layout
        try setupHuggingFaceCache(from: stagingDir)
        try? FileManager.default.removeItem(at: stagingDir)

        let snapDir = try hfSnapshotsDirectory()
        guard isModelCached(at: snapDir) else {
            throw TTSError.extractionFailed("导入的模型文件不完整或尺寸异常")
        }

        try checkAvailableMemory()
        ReaderStore.writeCrashMarker("importModel_warm_start")
        downloadPhase = .warming
        do {
            ttsModel = try await CosyVoiceTTSModel.fromPretrained(
                modelId: Self.activeVariant,
                cacheDir: rootCache,
                offlineMode: true
            )
            ReaderStore.writeCrashMarker("importModel_load_done")
            ttsModel?.warmUp()
            downloadPhase = .ready
            ReaderStore.writeCrashMarker("importModel_done")
        } catch {
            downloadPhase = .failed
            downloadError = error.localizedDescription
            ReaderStore.writeCrashMarker("importModel_failed:\(error.localizedDescription.prefix(60))")
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

    /// Synthesize multi-speaker dialogue with pre-computed embeddings AND fallback URL-based enrollment.
    func synthesizeDialogueWithEmbeddings(
        segments: [(speaker: String, text: String, emotion: String?)],
        speakerEmbeddings: [String: [Float]],
        speakerSamples: [String: URL]
    ) async throws -> Data {
        try await ensureModel()
        guard let model = ttsModel else { throw TTSError.modelNotAvailable }

        // 1. Compute cache key
        let segmentText = segments.map { "\($0.speaker)|\($0.emotion ?? "")|\($0.text)" }.joined(separator: "\n")
        let embedKeys = Array(speakerEmbeddings.keys).sorted().joined(separator: ",") + "|" + Array(speakerSamples.keys).sorted().joined(separator: ",")
        let key = cacheKey(text: "dialogue:\(segmentText)|samples:\(embedKeys)", embedding: nil)
        if let cached = cachedAudio(key: key) { return cached }

        // 2. Merge pre-computed embeddings with URL-based enrollments
        var embeddings = speakerEmbeddings
        for (name, url) in speakerSamples where embeddings[name] == nil {
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

        // 5. Convert to WAV and cache
        let wavData = AudioConverter.floatToWAV(samples, sampleRate: 24_000)
        storeCache(key: key, data: wavData)
        return wavData
    }

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

// MARK: - Download delegate (retained by actor, bridges URLSession to async)

/// Minimal URLSessionDownloadDelegate: copies file to stable temp location during callback,
/// then exposes async `result` property.
/// All shared state protected by `OSAllocatedUnfairLock` to prevent data races
/// between the URLSession delegate queue and the async caller.
private final class _DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let _lock = OSAllocatedUnfairLock()
    private nonisolated(unsafe) var _continuation: CheckedContinuation<URL, Error>?
    private nonisolated(unsafe) var _tempURL: URL?
    private nonisolated(unsafe) var _error: Error?

    var result: URL {
        get async throws {
            try await withCheckedThrowingContinuation { c in
                _lock.lock()
                if let error = _error {
                    c.resume(throwing: error)
                    _lock.unlock()
                    return
                }
                if let url = _tempURL {
                    c.resume(returning: url)
                    _lock.unlock()
                    return
                }
                _continuation = c
                _lock.unlock()
            }
        }
    }

    nonisolated func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosyvoice-\(UUID().uuidString)")
        try? FileManager.default.copyItem(at: location, to: tmp)
        _lock.lock()
        _tempURL = tmp
        _continuation?.resume(returning: tmp)
        _continuation = nil
        _lock.unlock()
    }

    nonisolated func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        _lock.lock()
        _error = error
        _continuation?.resume(throwing: error)
        _continuation = nil
        _lock.unlock()
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

// MARK: - Raw Inflate (for zip decompression)

private extension Data {
    /// Decompress raw deflate data (no zlib/gzip header) using zlib.
    func rawInflate(uncompressedSize: Int) throws -> Data {
        var result = Data(count: uncompressedSize)
        var stream = z_stream()
        let ret = self.withUnsafeBytes { srcRaw in
            result.withUnsafeMutableBytes { dstRaw in
                let srcPtr = srcRaw.bindMemory(to: UInt8.self).baseAddress!
                let dstPtr = dstRaw.bindMemory(to: UInt8.self).baseAddress!
                stream.next_in = UnsafeMutablePointer(mutating: srcPtr)
                stream.avail_in = uInt(self.count)
                stream.next_out = dstPtr
                stream.avail_out = uInt(uncompressedSize)
                return inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            }
        }
        guard ret == Z_OK else { inflateEnd(&stream); throw TTSError.extractionFailed("inflateInit failed: \(ret)") }
        let ret2 = inflate(&stream, Z_FINISH)
        inflateEnd(&stream)
        guard ret2 == Z_STREAM_END || ret2 == Z_OK else {
            throw TTSError.extractionFailed("inflate failed: \(ret2)")
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
