import Foundation
import AVFoundation
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
    private var queue: [TTSQueueItem] = []
    private var currentIndex = 0
    private var currentItem: TTSQueueItem?
    private var playbackHistory: [TTSQueueItem] = []
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private let rmsQueue = DispatchQueue(label: "rms", qos: .background)
    private var rmsTimer: Timer?
    private var rmsInstallRequested = false
    private var remoteCommandCenter = MPRemoteCommandCenter.shared()

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
        currentIndex = 0
        queueCount = queue.count
        playbackHistory.removeAll(keepingCapacity: false)
        playNextSeamlessly(isFirst: true)
    }

    func appendToQueue(_ items: [TTSQueueItem]) {
        let wasEmpty = queue.isEmpty
        queue.append(contentsOf: items)
        queueCount = queue.count
        if wasEmpty { playNextSeamlessly(isFirst: true) }
    }

    private func playNextSeamlessly(isFirst: Bool = false) {
        guard !queue.isEmpty else {
            isPlaying = false
            currentAnchor = nil
            currentItem = nil
            queueCount = 0
            updateNowPlaying()
            playbackContinuation?.resume()
            playbackContinuation = nil
            return
        }
        if let currentItem {
            playbackHistory.append(currentItem)
        }
        let item = queue.removeFirst()
        currentItem = item
        currentIndex += 1
        queueCount = queue.count
        currentAnchor = item.anchor

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: item.audioURL)
            player?.delegate = self
            player?.rate = playbackRate
            player?.enableRate = true
            player?.volume = 1.0
            player?.prepareToPlay()
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

    func stop() {
        flushPlayback()
        playbackContinuation?.resume()
        playbackContinuation = nil
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
        currentIndex = 0
        queueCount = queue.count
        player?.stop()
        player = nil
        self.currentAnchor = nil
        currentItem = nil
        isPlaying = false
        stopRMS()
        playNextSeamlessly(isFirst: true)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func playNext() { playNextSeamlessly() }
    func playPrevious() { flushPlayback() }
    func skipForward() { playNextSeamlessly() }
    func skipBackward() { flushPlayback() }

    func skipPreviousSentence() {
        guard let anchor = currentAnchor else { return }
        let targetParagraph = anchor.paragraphIndex ?? 0
        let targetSentence = anchor.sentenceIndex ?? 0
        guard let previousIndex = playbackHistory.lastIndex(where: { item in
            guard let a = item.anchor else { return false }
            let paragraph = a.paragraphIndex ?? 0
            let sentence = a.sentenceIndex ?? 0
            return paragraph < targetParagraph || (paragraph == targetParagraph && sentence < targetSentence)
        }) else { return }
        let target = playbackHistory.remove(at: previousIndex)
        queue.insert(target, at: 0)
        currentIndex = 0
        queueCount = queue.count
        player?.stop()
        player = nil
        self.currentAnchor = nil
        currentItem = nil
        isPlaying = false
        stopRMS()
        playNextSeamlessly(isFirst: true)
    }

    func skipPreviousParagraph() {
        guard let anchor = currentAnchor else { return }
        let target = (anchor.paragraphIndex ?? 0) - 1
        guard let previousIndex = playbackHistory.lastIndex(where: { item in
            guard let a = item.anchor else { return false }
            return (a.paragraphIndex ?? 0) <= target
        }) else { return }
        let targetItem = playbackHistory.remove(at: previousIndex)
        queue.insert(targetItem, at: 0)
        currentIndex = 0
        queueCount = queue.count
        player?.stop()
        player = nil
        self.currentAnchor = nil
        currentItem = nil
        isPlaying = false
        stopRMS()
        playNextSeamlessly(isFirst: true)
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
        currentIndex = 0
        queueCount = queue.count
        player?.stop()
        player = nil
        self.currentAnchor = nil
        currentItem = nil
        isPlaying = false
        stopRMS()
        playNextSeamlessly(isFirst: true)
    }

    func skipCurrentSentence() {
        guard let anchor = currentAnchor else { return }
        let targetParagraph = anchor.paragraphIndex ?? 0
        let targetSentence = (anchor.sentenceIndex ?? 0) + 1
        advanceQueueToNextMatch { a in
            let paragraph = a.paragraphIndex ?? 0
            let sentence = a.sentenceIndex ?? 0
            return paragraph > targetParagraph || (paragraph == targetParagraph && sentence >= targetSentence)
        }
    }

    func skipCurrentParagraph() {
        guard let anchor = currentAnchor else { return }
        let target = (anchor.paragraphIndex ?? 0) + 1
        advanceQueueToNextMatch { a in
            (a.paragraphIndex ?? 0) >= target
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

    func playFilesAndWait(_ urls: [URL]) async {
        let items = urls.enumerated().map { (i, url) in
            TTSQueueItem(
                segment: ScriptSegment(id: UUID(), characterName: "旁白", voice: "", rate: 0, pitch: 0, style: "neutral", text: "", emotionTag: nil),
                audioURL: url,
                chapterTitle: "",
                bookTitle: "",
                bookID: "",
                chapterIndex: 0,
                segmentIndex: i,
                totalSegments: urls.count,
                paragraphIndex: nil,
                sentenceIndex: nil,
                anchor: nil
            )
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            playbackContinuation = cont
            playQueue(items)
        }
    }

    private func flushPlayback() {
        player?.stop()
        player = nil
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
        rmsTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let rms = self.player?.averagePower(forChannel: 0) ?? -160
            let normalized = self.isPlaying ? max(0, (rms + 80) / 80) : 0
            Task { @MainActor in self.audioVolumeRMS = normalized }
        }
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "\(segment.characterName)：\(segment.text.prefix(30))",
            MPMediaItemPropertyArtist: item.chapterTitle,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
        ]
    }

    private func installRMSTap() {}
    private func removeRMSTap() {}

    static func cleanupAllAudioFiles() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dirs = ["tts_audio", "cosy_audio"]
        for dir in dirs {
            try? FileManager.default.removeItem(at: cachesDir.appendingPathComponent(dir, isDirectory: true))
        }
    }
}

extension AdvancedAudioPlaybackController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playNextSeamlessly()
        }
    }
}