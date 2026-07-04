import Foundation
import AVFoundation
import MediaPlayer
import Combine

actor TTSHttpClient {
    let baseURL: URL
    let apiKey: String?

    init(baseURL: URL, apiKey: String?) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    func synthesizeAudio(text: String, voice: String, rate: Int, pitch: Int, style: String) async throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        if !components.path.hasSuffix("/tts") {
            components.path = (components.path as NSString).appendingPathComponent("tts")
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "t", value: text),
            URLQueryItem(name: "v", value: voice),
            URLQueryItem(name: "r", value: "\(rate)"),
            URLQueryItem(name: "p", value: "\(pitch)"),
            URLQueryItem(name: "s", value: style),
        ]
        if let apiKey = apiKey, !apiKey.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "TTSHttpClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "合成失败，状态码：\(http.statusCode)，Content-Type: \(contentType)，返回：\(message)"])
        }

        guard !data.isEmpty else {
            throw NSError(domain: "TTSHttpClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "服务器返回空数据 (Content-Type: \(contentType))"])
        }

        debugPrint("TTS response: \(data.count) bytes, Content-Type: \(contentType)")

        let ext: String
        if contentType.contains("mpeg") || contentType.contains("mp3") { ext = "mp3" }
        else if contentType.contains("wav") || contentType.contains("wave") { ext = "wav" }
        else if contentType.contains("aac") { ext = "aac" }
        else if contentType.contains("ogg") { ext = "ogg" }
        else if contentType.contains("pcm") || contentType.contains("L16") || contentType.contains("raw") { ext = "wav" }
        else { ext = "mp3" }

        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let ttsDir = cachesDir.appendingPathComponent("tts_audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: ttsDir, withIntermediateDirectories: true)
        let outputURL = ttsDir.appendingPathComponent("tts-speak-\(UUID().uuidString).\(ext)")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    }

final class AudioPlaybackController: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentProgress: Double = 0
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var currentTitle: String = ""
    @Published private(set) var currentAuthor: String = ""
    @Published private(set) var queue: [TTSQueueItem] = []
    @Published private(set) var currentIndex: Int = 0

    private var player: AVAudioPlayer?
    var playbackRate: Float = 1.0
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private var progressTimer: Timer?
    private let session = AVAudioSession.sharedInstance()
    private var nowPlayingInfo: [String: Any] = [:]
    private var remoteCommandCenter = MPRemoteCommandCenter.shared()

    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
        restorePlaybackState()
        // Safety net: clean any stray audio files from previous runs
        DispatchQueue.global(qos: .utility).async {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let ttsDir = cachesDir.appendingPathComponent("tts_audio", isDirectory: true)
            try? FileManager.default.removeItem(at: ttsDir)
        }
    }

    private func setupAudioSession() {
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .allowAirPlay, .mixWithOthers])
            try session.setActive(true)
        } catch {
            Logger.log(error: error)
        }
    }

    private func setupRemoteCommands() {
        remoteCommandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        remoteCommandCenter.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }
        remoteCommandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        remoteCommandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
        remoteCommandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }
        remoteCommandCenter.skipForwardCommand.preferredIntervals = [15]
        remoteCommandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.seekForward(15)
            return .success
        }
        remoteCommandCenter.skipBackwardCommand.preferredIntervals = [15]
        remoteCommandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.seekBackward(15)
            return .success
        }
    }

    func playQueue(_ items: [TTSQueueItem], startingAt index: Int = 0) {
        stop()
        queue = items
        currentIndex = min(index, max(0, items.count - 1))
        playCurrent()
    }

    func appendToQueue(_ items: [TTSQueueItem]) {
        let wasEmpty = queue.isEmpty
        queue.append(contentsOf: items)
        if wasEmpty && !queue.isEmpty {
            playCurrent()
        }
        savePlaybackState()
    }

    func playFilesAndWait(_ urls: [URL]) async {
        let items = urls.map { TTSQueueItem(segment: ScriptSegment(id: UUID(), characterName: "", voice: "", rate: 0, pitch: 0, style: "", text: ""), audioURL: $0, chapterTitle: "", bookTitle: "", bookID: "", chapterIndex: 0, segmentIndex: 0, totalSegments: urls.count) }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            playbackContinuation = cont
            playQueue(items)
        }
    }

    private func playCurrent() {
        guard currentIndex < queue.count else {
            finishPlayback()
            return
        }

        let item = queue[currentIndex]
        do {
            player = try AVAudioPlayer(contentsOf: item.audioURL)
            player?.delegate = self
            player?.enableRate = true
            player?.rate = playbackRate
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
            currentTitle = "\(item.segment.characterName)：\(String(item.segment.text.prefix(30)))"
            currentAuthor = item.chapterTitle
            currentDuration = player?.duration ?? 0
            currentProgress = 0
            startProgressTimer()
            updateNowPlayingInfo()
            savePlaybackState()
        } catch {
            Logger.log(error: error)
            playNext()
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            self.currentProgress = player.currentTime / max(1, player.duration)
            self.updateNowPlayingInfo(progress: player.currentTime)
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
        updateNowPlayingInfo()
        savePlaybackState()
    }

    func resume() {
        player?.play()
        isPlaying = player?.isPlaying ?? false
        startProgressTimer()
        updateNowPlayingInfo()
        savePlaybackState()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        stopProgressTimer()
        let urls = queue.map(\.audioURL)
        queue.removeAll()
        currentIndex = 0
        currentProgress = 0
        currentDuration = 0
        currentTitle = ""
        currentAuthor = ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        clearPlaybackState()
        DispatchQueue.global(qos: .utility).async {
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
    }

    func playNext() {
        guard currentIndex + 1 < queue.count else {
            finishPlayback()
            return
        }
        currentIndex += 1
        playCurrent()
    }

    func playPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        playCurrent()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentProgress = time / max(1, player?.duration ?? 1)
        updateNowPlayingInfo(progress: time)
        savePlaybackState()
    }

    func seekForward(_ seconds: TimeInterval) {
        guard let player = player else { return }
        let newTime = min(player.currentTime + seconds, player.duration)
        seek(to: newTime)
    }

    func seekBackward(_ seconds: TimeInterval) {
        guard let player = player else { return }
        let newTime = max(player.currentTime - seconds, 0)
        seek(to: newTime)
    }

    func skipToSegment(_ index: Int) {
        guard index >= 0 && index < queue.count else { return }
        currentIndex = index
        playCurrent()
    }

    private func finishPlayback() {
        stopProgressTimer()
        player?.stop()
        player = nil
        isPlaying = false
        currentProgress = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        clearPlaybackState()
        playbackContinuation?.resume()
        playbackContinuation = nil
    }

    static func cleanupAllAudioFiles() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let ttsDir = cachesDir.appendingPathComponent("tts_audio", isDirectory: true)
        try? FileManager.default.removeItem(at: ttsDir)
    }

    private func updateNowPlayingInfo(progress: TimeInterval? = nil) {
        guard let player = player else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let currentItem = currentIndex < queue.count ? queue[currentIndex] : nil
        let elapsedTime = progress ?? player.currentTime

        nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyArtist: currentAuthor,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyBookmarkTime: elapsedTime
        ]

        if let artwork = currentItem.flatMap({ _ in generateArtwork() }) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func generateArtwork() -> MPMediaItemArtwork? {
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .medium),
                .foregroundColor: UIColor.label
            ]
            let text = "🎧"
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - textSize.width)/2, y: (size.height - textSize.height)/2), withAttributes: attrs)
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }

    private func savePlaybackState() {
        let state = PlaybackState(
            queue: queue,
            currentIndex: currentIndex,
            currentTime: player?.currentTime ?? 0,
            isPlaying: isPlaying,
            bookID: queue.first?.bookID ?? "",
            chapterIndex: queue.first?.chapterIndex ?? 0,
            segmentIndex: currentIndex
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "ttsPlaybackState")
        }
    }

    func restorePlaybackState() {
        guard let data = UserDefaults.standard.data(forKey: "ttsPlaybackState"),
              let state = try? JSONDecoder().decode(PlaybackState.self, from: data) else { return }

        // Check if audio files still exist before restoring
        let staleFiles = state.queue.contains { !FileManager.default.fileExists(atPath: $0.audioURL.path) }
        guard !staleFiles else {
            clearPlaybackState()
            return
        }

        queue = state.queue
        currentIndex = state.currentIndex
        isPlaying = state.isPlaying

        if !queue.isEmpty && currentIndex < queue.count {
            let item = queue[currentIndex]
            do {
                player = try AVAudioPlayer(contentsOf: item.audioURL)
                player?.delegate = self
                player?.prepareToPlay()
                player?.currentTime = state.currentTime
                if state.isPlaying {
                    player?.play()
                    isPlaying = true
                    startProgressTimer()
                }
                currentTitle = "\(item.segment.characterName)：\(String(item.segment.text.prefix(30)))"
                currentAuthor = item.chapterTitle
                currentDuration = player?.duration ?? 0
                currentProgress = state.currentTime / max(1, currentDuration)
                updateNowPlayingInfo()
            } catch {
                Logger.log(error: error)
                queue.removeAll()
                currentIndex = 0
                clearPlaybackState()
            }
        }
    }

    private func clearPlaybackState() {
        UserDefaults.standard.removeObject(forKey: "ttsPlaybackState")
    }

    struct PlaybackState: Codable {
        let queue: [TTSQueueItem]
        let currentIndex: Int
        let currentTime: TimeInterval
        let isPlaying: Bool
        let bookID: String
        let chapterIndex: Int
        let segmentIndex: Int
    }
}

extension AudioPlaybackController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        deleteCurrentAudioFile()
        if flag {
            playNext()
        } else {
            finishPlayback()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            Logger.log(error: error)
        }
        deleteCurrentAudioFile()
        playNext()
    }

    private func deleteCurrentAudioFile() {
        guard currentIndex < queue.count else { return }
        let url = queue[currentIndex].audioURL
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: url)
        }
    }
}