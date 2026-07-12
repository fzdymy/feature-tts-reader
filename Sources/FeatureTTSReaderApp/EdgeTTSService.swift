import Foundation

struct EdgeVoiceInfo: Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var gender: String
    var locale: String
    var styles: [String]?

    var displayName: String {
        "\(name)（\(gender == "Male" ? "男" : "女")）"
    }
}

private struct ServerConfigResponse: Decodable {
    var voices: [EdgeVoiceInfo]
}

struct EdgeTTSServerConfig: Codable, Equatable, Sendable, Identifiable {
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
    static let defaultServerURL = "http://localhost"
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
                EdgeTTSServerConfig(id: config.id, name: config.name, url: config.url, apiKey: config.apiKey)
            }
        }

        let legacyURL = UserDefaults.standard.string(forKey: Self.legacyServerURLKey) ?? Self.defaultServerURL
        return [EdgeTTSServerConfig(name: "默认", url: legacyURL, apiKey: apiKey)]
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
        }
    }

    var isConfigured: Bool {
        !configuredServers.isEmpty
    }

    init(session: URLSession = .shared) {
        self.session = session
        let key = UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? ""
        if UserDefaults.standard.data(forKey: Self.serverListKey) == nil,
           let legacy = UserDefaults.standard.string(forKey: Self.legacyServerURLKey) {
            let config = EdgeTTSServerConfig(name: "默认", url: legacy, apiKey: key)
            if let data = try? JSONEncoder().encode([config]) {
                UserDefaults.standard.set(data, forKey: Self.serverListKey)
            }
            UserDefaults.standard.set(legacy, forKey: Self.legacyServerURLKey)
        } else if UserDefaults.standard.data(forKey: Self.serverListKey) == nil {
            let config = EdgeTTSServerConfig(name: "默认", url: Self.defaultServerURL, apiKey: key)
            if let data = try? JSONEncoder().encode([config]) {
                UserDefaults.standard.set(data, forKey: Self.serverListKey)
            }
            UserDefaults.standard.set(Self.defaultServerURL, forKey: Self.legacyServerURLKey)
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

    func fetchVoices(serverID: UUID? = nil) async -> [EdgeVoiceInfo] {
        let servers = configuredServers
        let candidates: [EdgeTTSServerConfig]
        if let serverID {
            candidates = servers.filter { $0.id == serverID }
        } else {
            candidates = servers
        }
        for server in candidates {
            guard let baseURL = URL(string: server.url) else { continue }
            let configURL = baseURL.appendingPathComponent("api/v1/config")
            var request = URLRequest(url: configURL)
            request.timeoutInterval = 5
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                let config = try JSONDecoder().decode(ServerConfigResponse.self, from: data)
                return config.voices
            } catch {
                continue
            }
        }
        return []
    }

    func synthesize(text: String, voice: String? = nil, rate: Double = 0, pitch: Double = 0, style: String = "", serverID: UUID? = nil) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EdgeTTSError.emptyResponse }

        let servers = configuredServers
        guard !servers.isEmpty else { throw EdgeTTSError.missingServerURL }

        let candidates: [EdgeTTSServerConfig]
        if let serverID {
            candidates = servers.filter { $0.id == serverID }
            if candidates.isEmpty {
                throw EdgeTTSError.invalidServerURL
            }
        } else {
            candidates = servers
        }

        DebugLogger.log(flow: "edge_tts", step: "synthesize_start", details: [
            "text_preview": String(trimmed.prefix(200)),
            "text_length": trimmed.count,
            "voice": voice ?? "(default)",
            "rate": rate,
            "pitch": pitch,
            "style": style,
            "server_id": serverID?.uuidString ?? "(first_available)",
        ])

        var lastError: Error?
        for server in candidates {
            guard let baseURL = URL(string: server.url) else {
                lastError = EdgeTTSError.invalidServerURL
                continue
            }
            let normalizedURL: URL = {
                let urlStr = baseURL.absoluteString
                if urlStr.hasSuffix("/") {
                    return URL(string: String(urlStr.dropLast())) ?? baseURL
                }
                return baseURL
            }()
            let endpoint: URL
            if normalizedURL.lastPathComponent == "tts" {
                endpoint = normalizedURL.deletingLastPathComponent().appendingPathComponent("tts")
            } else {
                endpoint = normalizedURL.appendingPathComponent("tts")
            }
            do {
                let request = try buildGetRequest(to: endpoint, text: trimmed, voice: voice, rate: Int(rate), pitch: Int(pitch), style: style, apiKey: server.apiKey)
                DebugLogger.log(flow: "edge_tts", step: "synthesize_request", details: [
                    "url": endpoint.absoluteString,
                    "query_items": request.url?.query ?? "",
                ])
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw EdgeTTSError.invalidResponse("无效响应")
                }
                DebugLogger.log(flow: "edge_tts", step: "synthesize_response", details: [
                    "status_code": http.statusCode,
                    "data_length": data.count,
                    "server_url": server.url,
                ])
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
            DebugLogger.log(flow: "edge_tts", step: "synthesize_error", details: [
                "error": (lastError as? EdgeTTSError)?.localizedDescription ?? lastError.localizedDescription,
            ])
            throw lastError
        }
        DebugLogger.log(flow: "edge_tts", step: "synthesize_error", details: [
            "error": "未知错误",
        ])
        throw EdgeTTSError.networkError("未知错误")
    }

    /// 直接发送 SSML（用于情绪表达）
    func synthesizeSSML(ssml: String, serverID: UUID? = nil) async throws -> Data {
        let trimmed = ssml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EdgeTTSError.emptyResponse }

        let servers = configuredServers
        guard !servers.isEmpty else { throw EdgeTTSError.missingServerURL }

        let candidates: [EdgeTTSServerConfig]
        if let serverID {
            candidates = servers.filter { $0.id == serverID }
            if candidates.isEmpty {
                throw EdgeTTSError.invalidServerURL
            }
        } else {
            candidates = servers
        }

        DebugLogger.log(flow: "edge_tts", step: "synthesizeSSML_start", details: [
            "ssml_preview": String(trimmed.prefix(300)),
            "ssml_length": trimmed.count,
            "server_id": serverID?.uuidString ?? "(first_available)",
        ])

        var lastError: Error?
        for server in candidates {
            guard let baseURL = URL(string: server.url) else {
                lastError = EdgeTTSError.invalidServerURL
                continue
            }
            let normalizedURL: URL = {
                let urlStr = baseURL.absoluteString
                if urlStr.hasSuffix("/") {
                    return URL(string: String(urlStr.dropLast())) ?? baseURL
                }
                return baseURL
            }()
            let endpoint: URL
            if normalizedURL.lastPathComponent == "tts" {
                endpoint = normalizedURL.deletingLastPathComponent().appendingPathComponent("tts")
            } else {
                endpoint = normalizedURL.appendingPathComponent("tts")
            }
            do {
                var request = try buildPostRequest(to: endpoint, ssml: trimmed, apiKey: server.apiKey)
                let bodyPreview = (request.httpBody).flatMap { String(data: $0, encoding: .utf8) } ?? "(binary)"
                DebugLogger.log(flow: "edge_tts", step: "synthesizeSSML_request", details: [
                    "url": endpoint.absoluteString,
                    "http_method": "POST",
                    "headers": request.allHTTPHeaderFields ?? [:],
                    "body_preview": String(bodyPreview.prefix(300)),
                ])
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw EdgeTTSError.invalidResponse("无效响应")
                }
                DebugLogger.log(flow: "edge_tts", step: "synthesizeSSML_response", details: [
                    "status_code": http.statusCode,
                    "data_length": data.count,
                    "server_url": server.url,
                ])
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
            DebugLogger.log(flow: "edge_tts", step: "synthesizeSSML_error", details: [
                "error": (lastError as? EdgeTTSError)?.localizedDescription ?? lastError.localizedDescription,
            ])
            throw lastError
        }
        DebugLogger.log(flow: "edge_tts", step: "synthesizeSSML_error", details: [
            "error": "未知错误",
        ])
        throw EdgeTTSError.networkError("未知错误")
    }

    private func buildPostRequest(to endpoint: URL, ssml: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "api_key")
        }
        request.httpBody = ssml.data(using: .utf8)
        return request
    }

    /// 直接发送 SSML（用于情绪表达）

    func healthCheck() async -> String {
        let servers = configuredServers
        guard !servers.isEmpty else { return "未配置服务地址" }

        var results: [String] = []
        for server in servers {
            let result = await checkServer(server)
            results.append(result)
        }
        return results.joined(separator: "  ")
    }

    func healthCheck(serverID: UUID) async -> String {
        let servers = configuredServers
        guard let server = servers.first(where: { $0.id == serverID }) else {
            return "未找到服务器"
        }
        return await checkServer(server)
    }

    private func checkServer(_ server: EdgeTTSServerConfig) async -> String {
        let startTime = Date()
        guard let baseURL = URL(string: server.url) else {
            return "\(server.name): 无效地址"
        }
        let configURL = baseURL.appendingPathComponent("api/v1/config")
        var request = URLRequest(url: configURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        do {
            let (data, response) = try await session.data(for: request)
            let ms = Int(Date().timeIntervalSince(startTime) * 1000)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return "\(server.name): 暂不可达 (\(ms)ms)"
            }
            guard let decoded = try? JSONDecoder().decode(ServerConfigResponse.self, from: data),
                  !decoded.voices.isEmpty else {
                return "\(server.name): 响应异常 (\(ms)ms)"
            }
            return "\(server.name): 就绪 (\(ms)ms)"
        } catch {
            let ms = Int(Date().timeIntervalSince(startTime) * 1000)
            return "\(server.name): 暂不可达 (\(ms)ms)"
        }
    }

    func setServers(_ servers: [EdgeTTSServerConfig]) {
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

    private func buildGetRequest(to endpoint: URL, text: String, voice: String?, rate: Int, pitch: Int, style: String, apiKey: String) throws -> URLRequest {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw EdgeTTSError.invalidServerURL
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "t", value: text),
            URLQueryItem(name: "r", value: "\(rate * 4)"),
            URLQueryItem(name: "p", value: "\(pitch)"),
        ]
        if !style.isEmpty {
            items.append(URLQueryItem(name: "s", value: style))
        }
        if let voice = voice, !voice.isEmpty {
            items.append(URLQueryItem(name: "v", value: voice))
        }
        if !apiKey.isEmpty {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url ?? endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        return request
    }

    static func buildSSML(text: String, voice: String?, rate: Double, pitch: Double, emotionTag: String?) -> String {
        let emotion = (emotionTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rateValue: String
        switch rate {
        case let r where r > 20: rateValue = "+20%"
        case let r where r < -20: rateValue = "-20%"
        case let r where r > 0: rateValue = "+\(Int(r))%"
        case let r where r < 0: rateValue = "\(Int(r))%"
        default: rateValue = "0%"
        }
        let pitchValue: String
        switch pitch {
        case let p where p > 20: pitchValue = "+20%"
        case let p where p < -20: pitchValue = "-20%"
        case let p where p > 0: pitchValue = "+\(Int(p))%"
        case let p where p < 0: pitchValue = "\(Int(p))%"
        default: pitchValue = "0%"
        }

        var result = "<prosody rate=\"\(rateValue)\" pitch=\"\(pitchValue)\">"
        if !emotion.isEmpty && Self.supportedEmotions.contains(emotion) {
            result = "<mstts:express-as type=\"\(emotion)\" xmlns:mstts=\"http://www.w3.org/2001/mstts\">" + result
        }
        result += Self.escapeXML(text)
        result += "</prosody>"
        if !emotion.isEmpty && Self.supportedEmotions.contains(emotion) {
            result += "</mstts:express-as>"
        }
        if let voice = voice, !voice.isEmpty {
            result = "<voice name=\"\(voice)\">\(result)</voice>"
        }
        return result
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let supportedEmotions: Set<String> = ["angry", "cheerful", "excited", "friendly", "hopeful", "sad", "shouting", "terrified", "unfriendly", "whispering"]

    static func isMP3Data(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let id3Header: [UInt8] = [0x49, 0x44, 0x33]
        if data.starts(with: id3Header) { return true }
        return data[0] == 0xFF && (data[1] & 0xE0) == 0xE0
    }
}
