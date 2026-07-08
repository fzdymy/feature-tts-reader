import Foundation
import AVFoundation
import MediaPlayer
import Combine
import os

@MainActor
final class AdvancedAudioPlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentAnchor: PlaybackAnchor?
    @Published private(set) var audioVolumeRMS: Float = 0.0
    @Published private(set) var queueCount: Int = 0
    var playbackRate: Float = 1.0

    // MARK: - Audio engine (lazy — avoid AVAudioEngine C++ init deadlock during SwiftUI first frame)
    private var audioEngine: AVAudioEngine?
    private var playerNodeA: AVAudioPlayerNode?
    private var playerNodeB: AVAudioPlayerNode?
    private var crossfadeMixer: AVAudioMixerNode?
    private var comfortNoiseNode: AVAudioSourceNode?

    private var isUsingNodeA = true
    private var activeNode: AVAudioPlayerNode? { isUsingNodeA ? playerNodeA : playerNodeB }
    private var upcomingNode: AVAudioPlayerNode? { isUsingNodeA ? playerNodeB : playerNodeA }

    private lazy var queueLock = OSAllocatedUnfairLock(initialState: QueueState())

    private struct QueueState {
        var items: [TTSQueueItem] = []
    }

    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private var rmsTapInstalled = false
    private var enginePrepared = false

    // MARK: - Init
    init() {
        // Pure — no AVAudioEngine/AVAudioPlayerNode allocations here
    }

    func restorePlaybackState() {}

    /// Must be called once before any playback, ideally from BookshelfView.onAppear
    func ensureEngineSetup() {
        guard !enginePrepared else { return }
        enginePrepared = true

        let engine = AVAudioEngine()
        let nodeA = AVAudioPlayerNode()
        let nodeB = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()

        audioEngine = engine
        playerNodeA = nodeA
        playerNodeB = nodeB
        crossfadeMixer = mixer

        Self.writeAudioMarker("engine_session")
        configureAudioSession()

        Self.writeAudioMarker("engine_format")
        let format = engine.outputNode.outputFormat(forBus: 0)
        engine.attach(nodeA)
        engine.attach(nodeB)
        engine.attach(mixer)
        engine.connect(nodeA, to: mixer, format: format)
        engine.connect(nodeB, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)

        Self.writeAudioMarker("engine_noise")
        let noiseNode = AVAudioSourceNode(format: format) { _, _, frameLength, audioBufferList in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for i in 0..<abl.count {
                guard let mData = abl[i].mData else { continue }
                memset(mData, 0, Int(frameLength) * MemoryLayout<Float>.size)
            }
            return noErr
        }
        comfortNoiseNode = noiseNode
        engine.attach(noiseNode)
        engine.connect(noiseNode, to: engine.mainMixerNode, format: format)
        noiseNode.volume = 0

        engine.prepare()

        setupRemoteCommands()
        // RMS tap installed lazily on first playback, not at setup
    }

    func ensureEngineStarted() {
        guard enginePrepared, let engine = audioEngine, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            Logger.log(error: error, message: "engine.start")
        }
    }

    nonisolated static func writeAudioMarker(_ marker: String) {
        UserDefaults.standard.set(marker, forKey: "last_audio_marker")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let url = docs?.appendingPathComponent("audio_marker.txt") {
            let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let line = "\(ts) \(marker)\n"
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.synchronize()
                    handle.closeFile()
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        } catch {
            Logger.log(error: error, message: "configureAudioSession")
        }
    }

    private func installRMSTap() {
        guard !rmsTapInstalled, let engine = audioEngine else { return }
        rmsTapInstalled = true
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = UInt32(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<Int(frameLength) { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frameLength))
            DispatchQueue.main.async { [weak self] in
                self?.audioVolumeRMS = self?.isPlaying == true ? rms : 0
            }
        }
    }

    private func removeRMSTap() {
        guard rmsTapInstalled, let engine = audioEngine else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        rmsTapInstalled = false
    }

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

    // MARK: - Queue management
    func playQueue(_ items: [TTSQueueItem], startingAt index: Int = 0) {
        installRMSTap()
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

    // MARK: - Playback core
    private func playNextSeamlessly(isFirst: Bool = false) {
        let itemOpt: TTSQueueItem? = queueLock.withLock { $0.items.isEmpty ? nil : $0.items.removeFirst() }
        guard let item = itemOpt else {
            finishPlayback()
            return
        }

        currentAnchor = item.anchor
        isPlaying = true
        queueCount = queueLock.withLock { $0.items.count }
        updateNowPlayingInfo(for: item)

        guard let file = try? AVAudioFile(forReading: item.audioURL),
              let upcoming = upcomingNode else {
            playNextSeamlessly()
            return
        }

        upcoming.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor [weak self] in
                self?.cleanupAudioFile(item.audioURL)
                self?.playNextSeamlessly()
            }
        }

        if isFirst {
            upcoming.volume = 1.0
            activeNode?.volume = 0.0
            upcoming.play()
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
        upcomingNode?.volume = 0.0
        upcomingNode?.play()

        let crossfadeMs: Int = 50
        let stepMs: Int = 10
        let totalSteps = crossfadeMs / stepMs
        for step in 0...totalSteps {
            try? await Task.sleep(nanoseconds: UInt64(stepMs) * 1_000_000)
            let progress = Float(step) / Float(totalSteps)
            activeNode?.volume = cos(progress * .pi / 2)
            upcomingNode?.volume = sin(progress * .pi / 2)
        }

        activeNode?.stop()
        isUsingNodeA.toggle()
    }

    private func cleanupAudioFile(_ url: URL) {
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Control
    func pause() {
        playerNodeA?.pause()
        playerNodeB?.pause()
        isPlaying = false
    }

    func resume() {
        guard isPlaying == false else { return }
        isPlaying = true
        activeNode?.play()
    }

    func stop() {
        flushPlayback()
        playbackContinuation?.resume()
        playbackContinuation = nil
    }

    private func flushPlayback() {
        playerNodeA?.stop()
        playerNodeB?.stop()
        playerNodeA?.volume = 1.0
        playerNodeB?.volume = 0.0
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

    func immediateInterrupt() {
        flushPlayback()
    }

    func skipForward() {
        activeNode?.stop()
        activeNode?.volume = 1.0
        upcomingNode?.volume = 0.0
        isUsingNodeA = true
        playNextSeamlessly(isFirst: true)
    }

    func skipBackward() {
        activeNode?.stop()
        activeNode?.volume = 1.0
        upcomingNode?.volume = 0.0
        isUsingNodeA = true
        playNextSeamlessly(isFirst: true)
    }

    func seek(to time: TimeInterval) {}
    func seekForward(_ seconds: TimeInterval) { skipForward() }
    func seekBackward(_ seconds: TimeInterval) { skipForward() }

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
