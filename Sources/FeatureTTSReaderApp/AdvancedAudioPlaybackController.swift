import Foundation
@preconcurrency import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class AdvancedAudioPlaybackController: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentAnchor: PlaybackAnchor?
    @Published private(set) var audioVolumeRMS: Float = 0.0
    @Published private(set) var queueCount: Int = 0
    var playbackRate: Float = 1.0

    private var player: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?      // 预加载的下一条
    private var nextItem: TTSQueueItem?         // 对应的队列项
    private var queue: [TTSQueueItem] = []
    private var currentItem: TTSQueueItem?
    private var playbackHistory: [TTSQueueItem] = []
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private var rmsTimer: Timer?
    private var rmsInstallRequested = false
    private var remoteCommandCenter = MPRemoteCommandCenter.shared()
    private var isPreloading = false            // 防重入

    override init() {
        super.init()
        setupRemoteCommands()
    }

    func restorePlaybackState() {}

    func ensureEngineSetup() {}
    func ensureEngineStarted() {}

    private func setupRemoteCommands() {
        remoteCommandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.resume() }
            return .success
        }
        remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.pause() }
            return .success
        }
        remoteCommandCenter.stopCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.stop() }
            return .success
        }
        remoteCommandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.playNext() }
            return .success
        }
        remoteCommandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.playPrevious() }
            return .success
        }
        remoteCommandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self.seek(to: event.positionTime) }
            return .success
        }
        remoteCommandCenter.skipForwardCommand.preferredIntervals = [15]
        remoteCommandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.seekForward(15) }
            return .success
        }
        remoteCommandCenter.skipBackwardCommand.preferredIntervals = [15]
        remoteCommandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.seekBackward(15) }
            return .success
        }
    }

    func playQueue(_ items: [TTSQueueItem], startingAt index: Int = 0) {
        flushPlayback()
        queue = Array(items.dropFirst(index))
        queueCount = queue.count
        playbackHistory.removeAll(keepingCapacity: false)
        playNextSeamlessly()
    }

    func appendToQueue(_ items: [TTSQueueItem]) {
        queue.append(contentsOf: items)
        queueCount = queue.count
        if !isPlaying {
            playNextSeamlessly()
        } else {
            preloadNextIfNeeded()
        }
    }

    private func playNextSeamlessly() {
        guard !queue.isEmpty else {
            isPlaying = false
            currentAnchor = nil
            currentItem = nil
            nextPlayer = nil
            nextItem = nil
            queueCount = 0
            stopRMS()
            updateNowPlaying()
            if let continuation = playbackContinuation {
                playbackContinuation = nil
                continuation.resume()
            }
            return
        }
        
        // 1. 如果有预加载的 nextPlayer，直接接管（无缝切换）
        if let readyPlayer = nextPlayer, let readyItem = nextItem {
            if !queue.isEmpty { queue.removeFirst() }
            if let currentItem {
                playbackHistory.append(currentItem)
                if playbackHistory.count > 200 {
                    playbackHistory.removeFirst(playbackHistory.count - 200)
                }
            }
            player?.stop()
            player = readyPlayer
            currentItem = readyItem
            currentAnchor = readyItem.anchor
            queueCount = queue.count
            nextPlayer = nil
            nextItem = nil
            
            player?.delegate = self
            player?.rate = playbackRate
            player?.enableRate = true
            player?.volume = 1.0
            // 准备工作已在预加载时完成，直接播放
            if player?.play() == true {
                isPlaying = true
                startRMS()
                updateNowPlaying()
                preloadNextIfNeeded() // 继续预加载下一条
            }
            return
        }
        
        // 2. 首次或跳转后：从队列取第一条，创建播放器并预加载下一条
        if let currentItem {
            playbackHistory.append(currentItem)
            if playbackHistory.count > 200 {
                playbackHistory.removeFirst(playbackHistory.count - 200)
            }
        }
        let item = queue.removeFirst()
        currentItem = item
        queueCount = queue.count
        currentAnchor = item.anchor
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try makePlayer(for: item)
            player?.delegate = self
            player?.rate = playbackRate
            player?.enableRate = true
            player?.volume = 1.0
            player?.prepareToPlay()
            
            // 同步预加载下一条（异步，不阻塞当前播放）
            preloadNextIfNeeded()
            
            if player?.play() == true {
                isPlaying = true
                startRMS()
                updateNowPlaying()
            }
        } catch {
            Logger.log(error: error, message: "playNext")
            playNextSeamlessly()
        }
    }

    /// 创建 AVAudioPlayer（内存数据优先，回退文件）
    private func makePlayer(for item: TTSQueueItem) throws -> AVAudioPlayer {
        if let data = item.audioData, let p = try? AVAudioPlayer(data: data) { return p }
        if let url = item.audioURL {
            if let data = try? Data(contentsOf: url), let p = try? AVAudioPlayer(data: data) { return p }
            return try AVAudioPlayer(contentsOf: url)
        }
        throw NSError(domain: "TTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio source"])
    }

    /// 异步预加载下一句到 nextPlayer
    private func preloadNextIfNeeded() {
        guard !isPreloading, nextPlayer == nil, !queue.isEmpty else { return }
        isPreloading = true
        let next = queue[0]
        nextItem = next
        let audioData = next.audioData
        let audioURL = next.audioURL
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let p = try await Self.makePlayerAsync(audioData: audioData, audioURL: audioURL)
                await MainActor.run {
                    self.nextPlayer = p
                    self.nextPlayer?.prepareToPlay()
                    self.isPreloading = false
                }
            } catch {
                await MainActor.run {
                    self.nextPlayer = nil
                    self.nextItem = nil
                    self.isPreloading = false
                }
            }
        }
    }

    /// 在非隔离上下文创建 AVAudioPlayer（避免 Sendable 问题）
    nonisolated private static func makePlayerAsync(audioData: Data?, audioURL: URL?) async throws -> AVAudioPlayer {
        if let data = audioData, let p = try? AVAudioPlayer(data: data) { return p }
        if let url = audioURL {
            if let data = try? Data(contentsOf: url), let p = try? AVAudioPlayer(data: data) { return p }
            return try AVAudioPlayer(contentsOf: url)
        }
        throw NSError(domain: "TTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio source"])
    }

    func stop() {
        if let continuation = playbackContinuation {
            playbackContinuation = nil
            continuation.resume()
        }
        flushPlayback()
    }

    func skipToSegment(at paragraphIndex: Int) {
        let target = max(0, paragraphIndex)
        guard let idx = queue.firstIndex(where: { ($0.anchor?.paragraphIndex ?? $0.paragraphIndex ?? -1) >= target }) else {
            stop()
            return
        }
        let remaining = Array(queue[idx...])
        queue.removeAll(keepingCapacity: false)
        queue = remaining
        queueCount = queue.count
        player?.stop()
        player = nil
        nextPlayer?.stop()
        nextPlayer = nil
        nextItem = nil
        self.currentAnchor = nil
        currentItem = nil
        isPlaying = false
        stopRMS()
        playNextSeamlessly()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard let player else { return }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func playNext() { playNextSeamlessly() }
    func playPrevious() {
        guard let previous = playbackHistory.last else { return }
        playbackHistory.removeLast()
        queue.insert(previous, at: 0)
        queueCount = queue.count
        player?.stop()
        player = nil
        nextPlayer?.stop()
        nextPlayer = nil
        nextItem = nil
        self.currentAnchor = nil
        currentItem = nil
        isPlaying = false
        stopRMS()
        playNextSeamlessly()
    }
    func skipForward() { playNextSeamlessly() }
    func skipBackward() { playPrevious() }

    func skipPreviousSentence() {
        guard let anchor = currentAnchor else { return }
        let targetParagraph = anchor.paragraphIndex
        let targetSentence = anchor.sentenceIndex
        guard let previousIndex = playbackHistory.lastIndex(where: { item in
            guard let a = item.anchor else { return false }
            return a.paragraphIndex < targetParagraph || (a.paragraphIndex == targetParagraph && a.sentenceIndex < targetSentence)
        }) else { return }
        let target = playbackHistory.remove(at: previousIndex)
        queue.insert(target, at: 0)
        queueCount = queue.count
        player?.stop()
        player = nil
        nextPlayer?.stop()
        nextPlayer = nil
        nextItem = nil
        self.currentAnchor = nil
        currentItem = nil
        isPlaying = false
        stopRMS()
        playNextSeamlessly()
    }

    func skipPreviousParagraph() {
        guard let anchor = currentAnchor else { return }
        let target = anchor.paragraphIndex - 1
        var previousIndex: Int?
        if let idx = playbackHistory.firstIndex(where: { item in
            guard let a = item.anchor else { return false }
            return a.paragraphIndex == target
        }) {
            previousIndex = idx
        } else if let idx = playbackHistory.lastIndex(where: { item in
            guard let a = item.anchor else { return false }
            return a.paragraphIndex < target
        }) {
            previousIndex = idx
        }
        guard let idx = previousIndex else { return }
        let targetItem = playbackHistory.remove(at: idx)
        queue.insert(targetItem, at: 0)
        queueCount = queue.count
        player?.stop()
        player = nil
        nextPlayer?.stop()
        nextPlayer = nil
        nextItem = nil
        self.currentAnchor = nil
        currentItem = nil
        isPlaying = false
        stopRMS()
        playNextSeamlessly()
    }

    private func advanceQueueToNextMatch(_ predicate: (PlaybackAnchor) -> Bool) {
        guard let anchor = currentAnchor else { return }
        let matched = queue.filter { item in
            guard let a = item.anchor else { return false }
            return predicate(a)
        }
        guard !matched.isEmpty else {
            stop()
            return
        }
        queue.removeAll(keepingCapacity: false)
        queue = matched
        queueCount = queue.count
        player?.stop()
        player = nil
        nextPlayer?.stop()
        nextPlayer = nil
        nextItem = nil
        self.currentAnchor = nil
        currentItem = nil
        isPlaying = false
        stopRMS()
        playNextSeamlessly()
    }

    func skipCurrentSentence() {
        guard let anchor = currentAnchor else { return }
        let targetParagraph = anchor.paragraphIndex
        let targetSentence = anchor.sentenceIndex + 1
        advanceQueueToNextMatch { a in
            a.paragraphIndex > targetParagraph || (a.paragraphIndex == targetParagraph && a.sentenceIndex > targetSentence)
        }
    }

    func skipCurrentParagraph() {
        guard let anchor = currentAnchor else { return }
        let target = anchor.paragraphIndex + 1
        advanceQueueToNextMatch { a in
            a.paragraphIndex >= target
        }
    }
    func seek(to time: TimeInterval) {
        player?.currentTime = time
        updateNowPlaying()
    }

    func seekForward(_ seconds: TimeInterval) {
        if let p = player { p.currentTime = min(p.currentTime + seconds, p.duration) }
    }
    func seekBackward(_ seconds: TimeInterval) {
        if let p = player { p.currentTime = max(p.currentTime - seconds, 0) }
    }

    func playFilesAndWait(_ urls: [URL], characterName: String = "旁白") async {
        guard playbackContinuation == nil else { return }
        // Pre-load audio data off main thread to avoid synchronous Data(contentsOf:) in playNextSeamlessly
        var items: [TTSQueueItem] = []
        for (i, url) in urls.enumerated() {
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            items.append(TTSQueueItem(
                segment: ScriptSegment(id: UUID(), characterName: characterName, voice: "", rate: 0, pitch: 0, style: "neutral", text: "", emotionTag: nil),
                audioURL: data == nil ? url : nil,
                audioData: data,
                chapterTitle: "",
                bookTitle: "",
                bookID: "",
                chapterIndex: 0,
                segmentIndex: i,
                totalSegments: urls.count,
                paragraphIndex: nil,
                sentenceIndex: nil,
                anchor: nil
            ))
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            playbackContinuation = cont
            playQueue(items)
        }
    }

    private func flushPlayback() {
        player?.stop()
        player = nil
        nextPlayer?.stop()
        nextPlayer = nil
        nextItem = nil
        isPlaying = false
        currentAnchor = nil
        currentItem = nil
        queue.removeAll()
        queueCount = 0
        playbackHistory.removeAll(keepingCapacity: false)
        stopRMS()
        updateNowPlaying()
    }

    private func startRMS() {
        guard !rmsInstallRequested else { return }
        rmsInstallRequested = true
        let playerRef = player
        let isPlayingRef = isPlaying
        rmsTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let rms = playerRef?.averagePower(forChannel: 0) ?? -160
            let normalized = isPlayingRef ? max(0, (rms + 80) / 80) : 0
            Task { @MainActor in self.audioVolumeRMS = normalized }
        }
        RunLoop.main.add(rmsTimer!, forMode: .common)
    }

    private func stopRMS() {
        rmsInstallRequested = false
        rmsTimer?.invalidate()
        rmsTimer = nil
        audioVolumeRMS = 0
    }

    private func updateNowPlaying() {
        guard let player, let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let segment = item.segment
        let title = String(segment.text.prefix(30)).trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.isEmpty ? segment.characterName : "\(segment.characterName)：\(title)"
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: safeTitle,
            MPMediaItemPropertyArtist: item.chapterTitle.isEmpty ? "朗读" : item.chapterTitle,
            MPMediaItemPropertyAlbumTitle: "FeatureTTSReader",
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
    }

    private func installRMSTap() {}
    private func removeRMSTap() {}

    static func cleanupAllAudioFiles() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dirs = ["edge_audio", "tts_audio"]
        for dir in dirs {
            try? FileManager.default.removeItem(at: cachesDir.appendingPathComponent(dir, isDirectory: true))
        }
    }
}

extension AdvancedAudioPlaybackController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // 无缝切换：直接使用预加载好的 nextPlayer
            if let next = self.nextPlayer {
                if !self.queue.isEmpty { self.queue.removeFirst() }
                self.player?.delegate = nil
                self.player = next
                self.player?.delegate = self
                self.player?.rate = self.playbackRate
                self.player?.enableRate = true
                self.player?.volume = 1.0
                self.currentItem = self.nextItem
                self.currentAnchor = self.nextItem?.anchor
                self.nextPlayer = nil
                self.nextItem = nil
                self.queueCount = self.queue.count
                
                if self.player?.play() == true {
                    self.isPlaying = true
                    self.startRMS()
                    self.updateNowPlaying()
                    // 启动下一条的预加载
                    self.preloadNextIfNeeded()
                } else {
                    self.playNextSeamlessly() // 兜底
                }
            } else {
                // 没有预加载成功，走原逻辑
                self.playNextSeamlessly()
            }
        }
    }
}