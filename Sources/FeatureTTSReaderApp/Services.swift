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

    func fetchVoiceList() async throws -> [VoiceItem] {
        var url = baseURL.appendingPathComponent("api/v1/voices")
        if let apiKey = apiKey, !apiKey.isEmpty {
            url = url.appending(queryItems: [URLQueryItem(name: "api_key", value: apiKey)])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "TTSHttpClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取语音列表失败，状态码：\(http.statusCode)"])
        }

        return try decodeVoiceList(from: data)
    }

    func synthesizeAudio(text: String, voice: String, rate: Int, pitch: Int, style: String) async throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
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
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "TTSHttpClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "合成失败，状态码：\(http.statusCode)，返回：\(message)"])
        }

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts-speak-\(UUID().uuidString).mp3")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private func decodeVoiceList(from data: Data) throws -> [VoiceItem] {
        struct VoiceListItem: Decodable {
            let voice: String?
            let name: String?
            let id: String?
            let short_name: String?
            let displayName: String?
            let locale: String?
            let style_list: [String]?
            let styleList: [String]?

            var voiceId: String { voice ?? id ?? short_name ?? "" }

            enum CodingKeys: String, CodingKey {
                case voice, name, id, short_name, displayName, locale, style_list, styleList
            }
        }

        if let wrapper = try? JSONDecoder().decode([String: [VoiceListItem]].self, from: data), let values = wrapper["voices"] ?? wrapper["data"] {
            return values
                .filter { !$0.voiceId.isEmpty }
                .map { VoiceItem(id: $0.voiceId, name: $0.name ?? $0.displayName ?? $0.voiceId, locale: $0.locale ?? "zh-CN", gender: .female, styleList: nil) }
        }

        if let items = try? JSONDecoder().decode([VoiceListItem].self, from: data) {
            return items
                .filter { !$0.voiceId.isEmpty }
                .map { VoiceItem(id: $0.voiceId, name: $0.name ?? $0.displayName ?? $0.voiceId, locale: $0.locale ?? "zh-CN", gender: .female, styleList: nil) }
        }

        if let fallbackText = String(data: data, encoding: .utf8), fallbackText.contains("voice") || fallbackText.contains("name") {
            throw NSError(domain: "TTSHttpClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析语音列表失败，返回数据不符合预期。\n\(fallbackText)"])
        }

        return [
            VoiceItem(id: "zh-CN-XiaoxiaoNeural", name: "标准女声", locale: "zh-CN", gender: .female, styleList: nil),
            VoiceItem(id: "zh-CN-YunxiNeural", name: "年轻男声", locale: "zh-CN", gender: .male, styleList: nil),
            VoiceItem(id: "zh-CN-XiaohanNeural", name: "活力女声", locale: "zh-CN", gender: .female, styleList: nil),
            VoiceItem(id: "zh-CN-YunjianNeural", name: "成熟男声", locale: "zh-CN", gender: .male, styleList: nil),
            VoiceItem(id: "zh-CN-XiaomoNeural", name: "温柔女声", locale: "zh-CN", gender: .female, styleList: nil)
        ]
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
        queue.removeAll()
        currentIndex = 0
        currentProgress = 0
        currentDuration = 0
        currentTitle = ""
        currentAuthor = ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        clearPlaybackState()
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
        playNext()
    }
}