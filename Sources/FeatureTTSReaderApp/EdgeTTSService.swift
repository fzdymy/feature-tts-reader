import Foundation

struct EdgeTTSServerConfig: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var url: String
    var apiKey: String

    init(id: UUID = UUID(), name: String = "默认", url: String, apiKey: String = "") {
        self.id = id
        self.name = name
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum EdgeTTSError: LocalizedError {
    case missingServerURL
    case invalidServerURL
    case invalidResponse(String)
    case emptyResponse
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingServerURL:
            return "未配置 Edge TTS 服务地址"
        case .invalidServerURL:
            return "Edge TTS 服务地址无效"
        case .invalidResponse(let message):
            return "服务器返回异常: \(message)"
        case .emptyResponse:
            return "服务器未返回音频数据"
        case .networkError(let message):
            return "网络请求失败: \(message)"
        }
    }
}

actor EdgeTTSService {
    static let shared = EdgeTTSService()
    static let defaultServerURL = "http://192.168.0.68:37788"
    private static let oldDefaultServerURL = "http://10.0.1.45/tts"
    private static let serverListKey = "edge_tts_server_list"
    private static let legacyServerURLKey = "edge_tts_server_url"
    private static let apiKeyKey = "edge_tts_api_key"

    private let session: URLSession

    var configuredServers: [EdgeTTSServerConfig] {
        if let data = UserDefaults.standard.data(forKey: Self.serverListKey),
           let decoded = try? JSONDecoder().decode([EdgeTTSServerConfig].self, from: data),
           !decoded.isEmpty {
            let filtered = decoded.filter { !$0.url.isEmpty }
            return filtered.map { config in
                let normalizedURL: String
                if config.url == Self.oldDefaultServerURL || config.url == "http://10.0.1.45" {
                    normalizedURL = Self.defaultServerURL
                } else {
                    normalizedURL = config.url
                }
                return EdgeTTSServerConfig(id: config.id, name: config.name, url: normalizedURL, apiKey: config.apiKey)
            }
        }

        let legacyURL = UserDefaults.standard.string(forKey: Self.legacyServerURLKey) ?? Self.defaultServerURL
        let normalizedLegacy = legacyURL == Self.oldDefaultServerURL || legacyURL == "http://10.0.1.45" ? Self.defaultServerURL : legacyURL
        return [EdgeTTSServerConfig(name: "默认", url: normalizedLegacy, apiKey: apiKey)]
    }

    var serverURLString: String {
        get {
            configuredServers.first?.url ?? Self.defaultServerURL
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = trimmed.isEmpty ? Self.defaultServerURL : trimmed
            setServers([EdgeTTSServerConfig(name: "默认", url: url, apiKey: apiKey)])
        }
    }

    var serverListText: String {
        get {
            configuredServers.map(\.url).joined(separator: "\n")
        }
        set {
            setServers(parseServerListText(newValue))
        }
    }

    var apiKey: String {
        get {
            UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.apiKeyKey)
            let updated = configuredServers.map { EdgeTTSServerConfig(id: $0.id, name: $0.name, url: $0.url, apiKey: newValue) }
            if !updated.isEmpty {
                setServers(updated)
            }
        }
    }

    var isConfigured: Bool {
        !configuredServers.isEmpty
    }

    init(session: URLSession = .shared) {
        self.session = session
        if UserDefaults.standard.data(forKey: Self.serverListKey) == nil,
           (UserDefaults.standard.string(forKey: Self.legacyServerURLKey) == nil ||
            UserDefaults.standard.string(forKey: Self.legacyServerURLKey) == Self.oldDefaultServerURL ||
            UserDefaults.standard.string(forKey: Self.legacyServerURLKey) == "http://10.0.1.45") {
            setServers([EdgeTTSServerConfig(name: "默认", url: Self.defaultServerURL, apiKey: apiKey)])
        }
    }

    func setServerURL(_ raw: String) {
        serverURLString = raw
    }

    func setServerList(_ raw: String) {
        serverListText = raw
    }

    func setAPIKey(_ raw: String) {
        apiKey = raw
    }

    func synthesize(text: String, voice: String? = nil, rate: Double = 0, pitch: Double = 0, emotionTag: String? = nil) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EdgeTTSError.emptyResponse }

        let servers = configuredServers
        guard !servers.isEmpty else { throw EdgeTTSError.missingServerURL }

        var lastError: Error?
        for server in servers {
            guard let baseURL = URL(string: server.url) else {
                lastError = EdgeTTSError.invalidServerURL
                continue
            }
            let endpoint = baseURL.appendingPathComponent("tts")
            do {
                let request = try buildPostRequest(to: endpoint, text: trimmed, voice: voice, rate: rate, pitch: pitch, emotionTag: emotionTag, apiKey: server.apiKey)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw EdgeTTSError.invalidResponse("无效响应")
                }
                if (200...299).contains(http.statusCode) {
                    guard !data.isEmpty else { throw EdgeTTSError.emptyResponse }
                    return data
                }
                lastError = EdgeTTSError.invalidResponse("HTTP \(http.statusCode)")
            } catch let error as EdgeTTSError {
                lastError = error
            } catch {
                lastError = EdgeTTSError.networkError(error.localizedDescription)
            }
        }

        if let lastError {
            throw lastError
        }
        throw EdgeTTSError.networkError("未知错误")
    }

    func healthCheck() async -> String {
        let servers = configuredServers
        guard !servers.isEmpty else { return "未配置服务地址" }

        var results: [String] = []
        for server in servers {
            guard let baseURL = URL(string: server.url) else { continue }
            let endpoints = [
                baseURL.appendingPathComponent("health"),
                baseURL
            ]

            var serverOk = false
            for endpoint in endpoints {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "GET"
                request.timeoutInterval = 3
                if !server.apiKey.isEmpty {
                    request.setValue(server.apiKey, forHTTPHeaderField: "X-API-Key")
                }
                do {
                    let (_, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { continue }
                    if (200...299).contains(http.statusCode) {
                        serverOk = true
                        break
                    }
                } catch {
                    continue
                }
            }
            results.append(serverOk ? "\(server.name): 就绪" : "\(server.name): 暂不可达")
        }

        return results.joined(separator: "  ")
    }

    private func setServers(_ servers: [EdgeTTSServerConfig]) {
        let trimmed = servers.map { EdgeTTSServerConfig(id: $0.id, name: $0.name, url: $0.url, apiKey: $0.apiKey) }.filter { !$0.url.isEmpty }
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: Self.serverListKey)
        }
        if let first = trimmed.first {
            UserDefaults.standard.set(first.url, forKey: Self.legacyServerURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.legacyServerURLKey)
        }
    }

    private func parseServerListText(_ text: String) -> [EdgeTTSServerConfig] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        var result: [EdgeTTSServerConfig] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let separatorRange = trimmed.range(of: "="), separatorRange.lowerBound < separatorRange.upperBound {
                let name = String(trimmed[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let url = String(trimmed[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(EdgeTTSServerConfig(name: name.isEmpty ? "服务器 \(result.count + 1)" : name, url: url, apiKey: apiKey))
            } else {
                result.append(EdgeTTSServerConfig(name: "服务器 \(result.count + 1)", url: trimmed, apiKey: apiKey))
            }
        }
        return result.isEmpty ? [EdgeTTSServerConfig(name: "默认", url: Self.defaultServerURL, apiKey: apiKey)] : result
    }

    private func buildPostRequest(to endpoint: URL, text: String, voice: String?, rate: Double, pitch: Double, emotionTag: String?, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mp3", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let ssml = buildSSML(text: text, voice: voice, rate: rate, pitch: pitch, emotionTag: emotionTag)
        let payload: [String: Any] = [
            "text": text,
            "ssml": ssml,
            "voice": voice ?? "",
            "rate": rate,
            "pitch": pitch,
            "emotion": emotionTag ?? "",
            "api_key": apiKey
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private func buildSSML(text: String, voice: String?, rate: Double, pitch: Double, emotionTag: String?) -> String {
        let normalizedVoice = (voice ?? "")
        let voiced = normalizedVoice.isEmpty ? "zh-CN-XiaoyiNeural" : normalizedVoice
        let emotion = (emotionTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rateValue: String
        switch rate {
        case let r where r > 20: rateValue = "+20%"
        case let r where r < -20: rateValue = "-20%"
        default: rateValue = "\(Int(rate))%"
        }
        let pitchValue: String
        switch pitch {
        case let p where p > 20: pitchValue = "+20%"
        case let p where p < -20: pitchValue = "-20%"
        default: pitchValue = "\(Int(pitch))%"
        }

        var ssml = "<speak version=\"1.0\" xml:lang=\"zh-CN\" xmlns:mstts=\"http://www.w3.org/2001/mstts\">"
        ssml += "<voice name=\"\(voiced)\">"
        if !emotion.isEmpty && Self.supportedEmotions.contains(emotion) {
            ssml += "<mstts:express-as type=\"\(emotion)\">"
        }
        ssml += "<prosody rate=\"\(rateValue)\" pitch=\"\(pitchValue)\">"
        ssml += text
        ssml += "</prosody>"
        if !emotion.isEmpty && Self.supportedEmotions.contains(emotion) {
            ssml += "</mstts:express-as>"
        }
        ssml += "</voice>"
        ssml += "</speak>"
        return ssml
    }

    private static let supportedEmotions: Set<String> = ["angry", "cheerful", "excited", "friendly", "hopeful", "sad", "shouting", "terrified", "unfriendly", "whispering"]
}
