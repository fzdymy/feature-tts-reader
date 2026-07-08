import Foundation
import AVFoundation
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
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private let rmsQueue = DispatchQueue(label: "rms", qos: .background)
    private var rmsTimer: Timer?
    private var rmsInstallRequested = false

    override init() {}

    func restorePlaybackState() {}

    func ensureEngineSetup() {}
    func ensureEngineStarted() {}

    func playQueue(_ items: [TTSQueueItem], startingAt index: Int = 0) {
        flushPlayback()
        queue = Array(items.dropFirst(index))
        currentIndex = 0
        queueCount = queue.count
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
            queueCount = 0
            playbackContinuation?.resume()
            playbackContinuation = nil
            return
        }
        let item = queue.removeFirst()
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

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func playNext() { playNextSeamlessly() }
    func playPrevious() { flushPlayback() }
    func skipForward() { playNextSeamlessly() }
    func skipBackward() { flushPlayback() }
    func seek(to time: TimeInterval) { player?.currentTime = time }
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
        queue.removeAll()
        queueCount = 0
        stopRMS()
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

    private func updateNowPlaying() {}
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