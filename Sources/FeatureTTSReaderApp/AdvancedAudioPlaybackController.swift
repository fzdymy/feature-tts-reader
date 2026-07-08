import Foundation
import AVFoundation
import MediaPlayer
import Combine
import os

@MainActor
final class AdvancedAudioPlaybackController: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentAnchor: PlaybackAnchor?
    @Published private(set) var audioVolumeRMS: Float = 0.0
    @Published private(set) var queueCount: Int = 0
    var playbackRate: Float = 1.0

    // MARK: - Audio engine
    private let audioEngine = AVAudioEngine()
    private let playerNodeA = AVAudioPlayerNode()
    private let playerNodeB = AVAudioPlayerNode()
    private let crossfadeMixer = AVAudioMixerNode()
    private let comfortNoiseNode: AVAudioSourceNode

    private var isUsingNodeA = true
    private var activeNode: AVAudioPlayerNode { isUsingNodeA ? playerNodeA : playerNodeB }
    private var upcomingNode: AVAudioPlayerNode { isUsingNodeA ? playerNodeB : playerNodeA }

    private let queueLock = OSAllocatedUnfairLock(initialState: QueueState())

    private struct QueueState {
        var items: [TTSQueueItem] = []
    }

    // Continuation for playFilesAndWait compatibility
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private var rmsTapInstalled = false

    // MARK: - Init
    override init() {
        comfortNoiseNode = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<Int(frameCount) {
                    pointer[frame] = Float.random(in: -0.00005...0.00005)
                }
            }
            return noErr
        }
        super.init()
        setupAudioEngine()
        setupRemoteCommands()
    }

    /// Compatibility stub — new controller starts fresh.
    func restorePlaybackState() {}

    private func setupAudioEngine() {
        let format = audioEngine.outputNode.outputFormat(forBus: 0)

        audioEngine.attach(playerNodeA)
        audioEngine.attach(playerNodeB)
        audioEngine.attach(crossfadeMixer)
        audioEngine.attach(comfortNoiseNode)

        // Dual nodes → crossfade mixer → main mixer
        audioEngine.connect(playerNodeA, to: crossfadeMixer, format: format)
        audioEngine.connect(playerNodeB, to: crossfadeMixer, format: format)
        audioEngine.connect(crossfadeMixer, to: audioEngine.mainMixerNode, format: format)

        // Comfort noise injected at main mixer level
        audioEngine.connect(comfortNoiseNode, to: audioEngine.mainMixerNode, format: format)

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            Logger.log(error: error)
        }

        installRMSTap()
    }

    private func installRMSTap() {
        guard !rmsTapInstalled else { return }
        rmsTapInstalled = true
        audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = UInt32(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<Int(frameLength) { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frameLength))
            Task { @MainActor [weak self] in
                self?.audioVolumeRMS = self?.isPlaying == true ? rms : 0
            }
        }
    }

    private func removeRMSTap() {
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        rmsTapInstalled = false
    }

    // MARK: - Remote commands
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }; return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipForward() }; return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipBackward() }; return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let ev = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: ev.positionTime) }; return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seekForward(15) }; return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seekBackward(15) }; return .success
        }
    }

    // MARK: - Queue management (F3: multi-item continuous queue)
    func playQueue(_ items: [TTSQueueItem], startingAt index: Int = 0) {
        flushPlayback()
        queueLock.withLock { $0.items = items }
        let startIdx = min(index, max(0, items.count - 1))
        queueCount = items.count
        if startIdx > 0 {
            queueLock.withLock { $0.items.removeFirst(startIdx) }
        }
        playNextSeamlessly(isFirst: true)
    }

    func appendToQueue(_ items: [TTSQueueItem]) {
        let wasEmpty: Bool = queueLock.withLock {
            let empty = $0.items.isEmpty
            $0.items.append(contentsOf: items)
            return empty
        }
        queueCount = queueLock.withLock { $0.items.count }
        if wasEmpty && queueCount > 0 {
            playNextSeamlessly(isFirst: true)
        }
    }

    func appendToQueue(_ item: TTSQueueItem) {
        appendToQueue([item])
    }

    /// playFilesAndWait-compatible async method for previews/e2e tests
    func playFilesAndWait(_ urls: [URL]) async {
        let items = urls.map {
            TTSQueueItem(
                segment: ScriptSegment(id: UUID(), characterName: "", voice: "", rate: 0, pitch: 0, style: "", text: ""),
                audioURL: $0, chapterTitle: "", bookTitle: "", bookID: "", chapterIndex: 0,
                segmentIndex: 0, totalSegments: urls.count, paragraphIndex: nil, sentenceIndex: nil, anchor: nil
            )
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.playbackContinuation = cont
            self.playQueue(items)
        }
    }

    // MARK: - Playback core (dual-node crossfade)
    private func playNextSeamlessly(isFirst: Bool = false) {
        let itemOpt: TTSQueueItem? = queueLock.withLock { $0.items.isEmpty ? nil : $0.items.removeFirst() }
        guard let item = itemOpt else {
            finishPlayback()
            return
        }

        currentAnchor = item.anchor
        isPlaying = true
        queueCount = queueLock.withLock { $0.items.count }

        // Update NowPlaying metadata
        updateNowPlayingInfo(for: item)

        guard let file = try? AVAudioFile(forReading: item.audioURL) else {
            playNextSeamlessly()
            return
        }

        upcomingNode.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor [weak self] in
                self?.cleanupAudioFile(item.audioURL)
                self?.playNextSeamlessly()
            }
        }

        if isFirst {
            upcomingNode.volume = 1.0
            activeNode.volume = 0.0
            upcomingNode.play()
            isUsingNodeA.toggle()
        } else {
            Task {
                await performCrossfade(fileDuration: file.length > 0
                    ? Double(file.length) / file.processingFormat.sampleRate
                    : 0)
            }
        }
    }

    private func performCrossfade(fileDuration: Double) async {
        upcomingNode.volume = 0.0
        upcomingNode.play()

        let crossfadeMs: Int = 50
        let stepMs: Int = 10
        let totalSteps = crossfadeMs / stepMs  // 5 steps → 50ms
        for step in 0...totalSteps {
            try? await Task.sleep(nanoseconds: UInt64(stepMs) * 1_000_000)
            let progress = Float(step) / Float(totalSteps)
            activeNode.volume = cos(progress * .pi / 2)
            upcomingNode.volume = sin(progress * .pi / 2)
        }

        activeNode.stop()
        isUsingNodeA.toggle()
    }

    private func cleanupAudioFile(_ url: URL) {
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Control
    func pause() {
        playerNodeA.pause()
        playerNodeB.pause()
        isPlaying = false
    }

    func resume() {
        guard isPlaying == false else { return }
        isPlaying = true
        activeNode.play()
    }

    func stop() {
        flushPlayback()
        playbackContinuation?.resume()
        playbackContinuation = nil
    }

    private func flushPlayback() {
        playerNodeA.stop()
        playerNodeB.stop()
        playerNodeA.volume = 1.0
        playerNodeB.volume = 0.0
        isUsingNodeA = true

        let staleURLs: [URL] = queueLock.withLock {
            let urls = $0.items.map(\.audioURL)
            $0.items.removeAll()
            return urls
        }
        queueCount = 0

        isPlaying = false
        currentAnchor = nil
        audioVolumeRMS = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        DispatchQueue.global(qos: .utility).async {
            for url in staleURLs { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Hard reset & flush — for high-frequency user seeking (G6)
    func immediateInterrupt() {
        flushPlayback()
    }

    func skipForward() {
        // Skip current file, move to next
        activeNode.stop()
        activeNode.volume = 1.0
        upcomingNode.volume = 0.0
        isUsingNodeA = true
        playNextSeamlessly(isFirst: true)
    }

    func skipBackward() {
        // Simplification: go back to start of current; full backward queue reload is handled externally
        activeNode.stop()
        activeNode.volume = 1.0
        upcomingNode.volume = 0.0
        isUsingNodeA = true
        playNextSeamlessly(isFirst: true)
    }

    func seek(to time: TimeInterval) { /* not meaningful for streaming node model */ }
    func seekForward(_ seconds: TimeInterval) { skipForward() }
    func seekBackward(_ seconds: TimeInterval) { skipForward() }

    /// Compatibility aliases for callers expecting the old AudioPlaybackController API.
    func playNext() { skipForward() }
    func playPrevious() { skipBackward() }

    func finishPlayback() {
        isPlaying = false
        currentAnchor = nil
        audioVolumeRMS = 0
        queueCount = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        playbackContinuation?.resume()
        playbackContinuation = nil
    }

    // MARK: - Now Playing Info
    private func updateNowPlayingInfo(for item: TTSQueueItem) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.chapterTitle,
            MPMediaItemPropertyArtist: item.bookTitle,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]

        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .medium),
                .foregroundColor: UIColor.label
            ]
            let text = "🎧"; let ts = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - ts.width)/2, y: (size.height - ts.height)/2), withAttributes: attrs)
        }
        let artwork = MPMediaItemArtwork(boundsSize: size) { _ in image }
        info[MPMediaItemPropertyArtwork] = artwork

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    static func cleanupAllAudioFiles() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dirs = ["tts_audio", "cosy_audio"]
        for dir in dirs {
            try? FileManager.default.removeItem(at: cachesDir.appendingPathComponent(dir, isDirectory: true))
        }
    }
}