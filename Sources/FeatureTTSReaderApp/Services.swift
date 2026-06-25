import Foundation
import AVFoundation

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

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "TTSHttpClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取语音列表失败，状态码：\(http.statusCode)"])
        }

        return try decodeVoiceList(from: data)
    }

    func synthesizeAudio(text: String, voice: String, rate: Int, pitch: Int, style: String) async throws -> URL {
        let url = baseURL.appendingPathComponent("api/v1/tts")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "text": text,
            "voice": voice,
            "rate": rate,
            "pitch": pitch,
            "style": style
        ]
        if let apiKey = apiKey, !apiKey.isEmpty {
            body["api_key"] = apiKey
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

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
            let displayName: String?
            let locale: String?

            enum CodingKeys: String, CodingKey {
                case voice, name, id, displayName, locale
            }
        }

        if let wrapper = try? JSONDecoder().decode([String: [VoiceListItem]].self, from: data), let values = wrapper["voices"] ?? wrapper["data"] {
            return values.compactMap { item in
                guard let voiceId = item.voice ?? item.id else { return nil }
                return VoiceItem(id: voiceId, name: item.name ?? item.displayName ?? voiceId, locale: item.locale ?? "zh-CN")
            }
        }

        if let items = try? JSONDecoder().decode([VoiceListItem].self, from: data) {
            return items.compactMap { item in
                guard let voiceId = item.voice ?? item.id else { return nil }
                return VoiceItem(id: voiceId, name: item.name ?? item.displayName ?? voiceId, locale: item.locale ?? "zh-CN")
            }
        }

        if let fallbackText = String(data: data, encoding: .utf8), fallbackText.contains("voice") || fallbackText.contains("name") {
            throw NSError(domain: "TTSHttpClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析语音列表失败，返回数据不符合预期。\n\(fallbackText)"])
        }

        return [
            VoiceItem(id: "zh-CN-XiaoxiaoNeural", name: "标准女声", locale: "zh-CN"),
            VoiceItem(id: "zh-CN-YunxiNeural", name: "年轻男声", locale: "zh-CN"),
            VoiceItem(id: "zh-CN-XiaohanNeural", name: "活力女声", locale: "zh-CN"),
            VoiceItem(id: "zh-CN-YunjianNeural", name: "成熟男声", locale: "zh-CN"),
            VoiceItem(id: "zh-CN-XiaomoNeural", name: "温柔女声", locale: "zh-CN")
        ]
    }
}

final class AudioPlaybackController: NSObject, AVAudioPlayerDelegate, ObservableObject {
    @Published private(set) var isPlaying = false

    private var queue: [URL] = []
    private var player: AVAudioPlayer?

    func playFiles(_ urls: [URL]) {
        stop()
        queue = urls
        playNext()
    }

    func stop() {
        player?.stop()
        player = nil
        queue.removeAll()
        isPlaying = false
    }

    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            return
        }
        let next = queue.removeFirst()
        do {
            player = try AVAudioPlayer(contentsOf: next)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
        } catch {
            playNext()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playNext()
    }
}
