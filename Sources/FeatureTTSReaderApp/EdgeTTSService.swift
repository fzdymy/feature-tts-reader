import Foundation

struct EdgeVoiceInfo: Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var gender: String
    var locale: String
    var styles: [String]?

    /// 本地化显示名：中文名 + 性别图标
    var displayName: String {
        let base = EdgeVoiceInfo.baseVoiceID(id)
        let chineseName: String = {
            switch base {
            // zh-CN 女声
            case "zh-CN-Xiaoxiao": return "小晓"
            case "zh-CN-Xiaochen": return "晓辰"
            case "zh-CN-Xiaohan": return "晓涵"
            case "zh-CN-Xiaomo": return "晓墨"
            case "zh-CN-Xiaomeng": return "晓萌"
            case "zh-CN-Xiaorui": return "晓睿"
            case "zh-CN-Xiaoshuang": return "晓双"
            case "zh-CN-Xiaoxuan": return "晓萱"
            case "zh-CN-Xiaoyan": return "晓颜"
            case "zh-CN-Xiaoyi": return "晓伊"
            case "zh-CN-Xiaozhen": return "晓臻"
            case "zh-CN-Xiaoyu": return "晓雨"
            // zh-CN 男声
            case "zh-CN-Yunxi": return "云希"
            case "zh-CN-Yunyang": return "云扬"
            case "zh-CN-Yunye": return "云野"
            case "zh-CN-Yunjian": return "云健"
            case "zh-CN-Yunfeng": return "云峰"
            case "zh-CN-Yunxia": return "云夏"
            case "zh-CN-Yunze": return "云泽"
            case "zh-CN-Yunhao": return "云皓"
            case "zh-CN-Yunqi": return "云奇"
            case "zh-CN-Yunyi": return "云逸"
            case "zh-CN-Yunxiao": return "云霄"
            case "zh-CN-Yunjia": return "云嘉"
            // 方言
            case "zh-CN-henan-Yundeng": return "云登"
            case "zh-CN-shaanxi-Xiaoni": return "晓妮"
            case "zh-CN-sichuan-Xiaomo": return "晓墨"
            case "zh-CN-sichuan-Yunxi": return "云希"
            // 粤语
            case "zh-HK-HiuGaai": return "晓佳"
            case "zh-HK-HiuMaan": return "晓曼"
            case "zh-HK-WanLung": return "云龙"
            // 台语
            case "zh-TW-HsiaoChen": return "晓臻"
            case "zh-TW-HsiaoYu": return "晓雨"
            case "zh-TW-YunJhe": return "云哲"
            default: return base
            }
        }()
        let genderIcon = gender == "Male" ? "♂" : "♀"
        return "\(chineseName) \(genderIcon)"
    }

    /// 剥离服务器后缀 & Neural 尾缀
    static func baseVoiceID(_ id: String) -> String {
        var base = id
        if let colon = id.firstIndex(of: ":") { base = String(id[..<colon]) }
        if base.hasSuffix("Neural") { base = String(base.dropLast(6)) }
        return base
    }

    /// 提取服务器模型后缀（如 :DragonHDFlashLatestNeural → :DragonHD）
    static func shortModelSuffix(_ id: String) -> String {
        guard let colon = id.firstIndex(of: ":") else { return "" }
        var suffix = String(id[id.index(after: colon)...])
        for strip in ["FlashLatestNeural", "LatestNeural", "FlashLatest", "Latest", "Neural"] {
            guard suffix.hasSuffix(strip) else { continue }
            suffix = String(suffix.dropLast(strip.count))
            break
        }
        return ":\(suffix)"
    }

    /// 音色显示标签：中文名/英文短名:模型后缀（如 晓晓/Xiaoxiao:DragonHD）
    static func shortVoiceLabel(_ id: String, name: String) -> String {
        let base = baseVoiceID(id)
        let engName = base
            .replacingOccurrences(of: "zh-CN-", with: "")
            .replacingOccurrences(of: "zh-HK-", with: "")
            .replacingOccurrences(of: "zh-TW-", with: "")
        let suffix = shortModelSuffix(id)
        return "\(name)/\(engName)\(suffix)"
    }

    /// 拼音 → 中文名映射（键不含 Neural 后缀）
    static func chineseVoiceName(for voiceID: String) -> String {
        let base = baseVoiceID(voiceID)
        let map: [String: String] = [
            // zh-CN 女声
            "zh-CN-Xiaoxiao": "小晓", "zh-CN-Xiaochen": "晓辰",
            "zh-CN-Xiaohan": "晓涵", "zh-CN-Xiaomo": "晓墨",
            "zh-CN-Xiaomeng": "晓萌", "zh-CN-Xiaorui": "晓睿",
            "zh-CN-Xiaoshuang": "晓双", "zh-CN-Xiaoxuan": "晓萱",
            "zh-CN-Xiaoyan": "晓颜", "zh-CN-Xiaoyi": "晓伊",
            "zh-CN-Xiaozhen": "晓臻", "zh-CN-Xiaoyu": "晓雨",
            // zh-CN 男声
            "zh-CN-Yunxi": "云希", "zh-CN-Yunyang": "云扬",
            "zh-CN-Yunye": "云野", "zh-CN-Yunjian": "云健",
            "zh-CN-Yunfeng": "云峰", "zh-CN-Yunxia": "云夏",
            "zh-CN-Yunze": "云泽", "zh-CN-Yunhao": "云皓",
            "zh-CN-Yunqi": "云奇", "zh-CN-Yunyi": "云逸",
            "zh-CN-Yunxiao": "云霄", "zh-CN-Yunjia": "云嘉",
            // 方言
            "zh-CN-henan-Yundeng": "云登",
            "zh-CN-shaanxi-Xiaoni": "晓妮",
            "zh-CN-sichuan-Xiaomo": "晓墨",
            "zh-CN-sichuan-Yunxi": "云希",
            // 粤语
            "zh-HK-HiuGaai": "晓佳", "zh-HK-HiuMaan": "晓曼",
            "zh-HK-WanLung": "云龙",
            // 台语
            "zh-TW-HsiaoChen": "晓臻", "zh-TW-HsiaoYu": "晓雨",
            "zh-TW-YunJhe": "云哲",
        ]
        return map[base] ?? base
    }
}

private struct ServerConfigResponse: Decodable {
    var voices: [EdgeVoiceInfo]
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
    
    // TTS Synthesis Cache with LRU eviction (max 200 entries)
    private var ttsCache: [String: (data: Data, timestamp: Date)] = [:]
    private let ttsCacheMaxSize = 200
    private let ttsCacheMaxAge: TimeInterval = 7 * 24 * 3600 // 7 days

    var configuredServers: [EdgeTTSServerConfig] {
        if let data = UserDefaults.standard.data(forKey: Self.serverListKey),
           let decoded = try? JSONDecoder().decode([EdgeTTSServerConfig].self, from: data),
           !decoded.isEmpty {
            let filtered = decoded.filter { !$0.url.isEmpty }
            return filtered.map { config in
                var c = config
                if let key = try? KeychainUtility.loadString(key: "server_\(config.id.uuidString)_apiKey") {
                    c.apiKey = key
                }
                return c
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
            do {
                return try KeychainUtility.loadString(key: "global_apiKey")
            } catch {
                return ""
            }
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try? KeychainUtility.delete(key: "global_apiKey")
            } else {
                try? KeychainUtility.saveString(key: "global_apiKey", value: trimmed)
            }
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

    func synthesize(text: String, voice: String? = nil, rate: Double = 0, pitch: Double = 0, style: String = "", volume: String = "default", serverID: UUID? = nil) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EdgeTTSError.emptyResponse }

        let cacheKey = cacheKey(text: trimmed, voice: voice, rate: rate, pitch: pitch, style: style, volume: volume)
        if let cached = getCachedData(for: cacheKey) {
            DebugLogger.log(flow: "edge_tts", step: "synthesize_cache_hit", details: ["key": cacheKey])
            return cached
        }

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
            "volume": volume,
            "server_id": serverID?.uuidString ?? "(first_available)",
        ])

        var lastError: Error?
        for server in candidates {
            guard let baseURL = URL(string: server.url) else {
                lastError = EdgeTTSError.invalidServerURL
                continue
            }
            let endpoint = Self.ttsAPIEndpoint(from: baseURL)
            do {
                let request = try buildGetRequest(to: endpoint, text: trimmed, voice: voice, rate: Int(rate), pitch: Int(pitch), style: style, volume: volume, apiKey: server.apiKey)
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
                    setCachedData(data, for: cacheKey)
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

        let cacheKey = "ssml_\(trimmed.stableHash)"
        if let cached = getCachedData(for: cacheKey) {
            DebugLogger.log(flow: "edge_tts", step: "synthesizeSSML_cache_hit", details: ["key": cacheKey])
            return cached
        }

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
            let endpoint = Self.ttsAPIEndpoint(from: baseURL)
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
                    setCachedData(data, for: cacheKey)
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

    /// 从服务器 base URL 解析 TTS API 端点 (/api/v1/tts)
    private static func ttsAPIEndpoint(from baseURL: URL) -> URL {
        let urlStr = baseURL.absoluteString
        let normalized: URL
        if urlStr.hasSuffix("/") {
            normalized = URL(string: String(urlStr.dropLast())) ?? baseURL
        } else {
            normalized = baseURL
        }
        if normalized.lastPathComponent == "tts" {
            return normalized.deletingLastPathComponent().appendingPathComponent("api/v1/tts")
        }
        return normalized.appendingPathComponent("api/v1/tts")
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
        let ttsURL = baseURL.appendingPathComponent("api/v1/tts")
        var request = URLRequest(url: ttsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        do {
            let (_, response) = try await session.data(for: request)
            let ms = Int(Date().timeIntervalSince(startTime) * 1000)
            guard let http = response as? HTTPURLResponse else {
                return "\(server.name): 暂不可达 (\(ms)ms)"
            }
            // 代理 / captive portal 通常返回 HTML 登录页，识别为异常而非就绪
            if (http.mimeType ?? "").contains("html") {
                return "\(server.name): 响应异常 (\(ms)ms)"
            }
            // 2xx 或 4xx 均说明服务器在线并已响应（405 方法不允许也代表端点存在）
            if (200...499).contains(http.statusCode) {
                return "\(server.name): 就绪 (\(ms)ms)"
            }
            return "\(server.name): 响应异常 (\(ms)ms)"
        } catch {
            let ms = Int(Date().timeIntervalSince(startTime) * 1000)
            return "\(server.name): 暂不可达 (\(ms)ms)"
        }
    }

    /// Probe all configured servers and update latency tracking
    func probeServerLatencies() async {
        let servers = configuredServers
        for server in servers {
            let start = Date()
            guard let url = URL(string: server.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            do {
                _ = try await session.data(for: request)
                let latency = Date().timeIntervalSince(start) * 1000
                updateServerLatency(id: server.id, latencyMs: latency)
            } catch {
                updateServerLatency(id: server.id, latencyMs: nil)
            }
        }
    }

    /// Auto-discover Edge TTS servers on common local addresses
    /// Returns list of discovered server URLs that respond to health check
    nonisolated static func autoDiscoverServers() async -> [String] {
        let commonHosts = ["localhost", "127.0.0.1", "192.168.1.100", "192.168.1.101", "192.168.0.100", "10.0.0.100"]
        let commonPorts = [5000, 5002, 5003, 8080, 8081, 9880]
        var discovered: [String] = []

        await withTaskGroup(of: String?.self) { group in
            for host in commonHosts {
                for port in commonPorts {
                    let url = "http://\(host):\(port)"
                    group.addTask {
                        let url = URL(string: url)!
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 2
                        do {
                            _ = try await URLSession.shared.data(for: request)
                            return url.absoluteString
                        } catch {
                            return nil
                        }
                    }
                }
            }
            for await result in group {
                if let url = result { discovered.append(url) }
            }
        }
        return discovered
    }

    /// Auto-configure TTS server on first launch if no servers configured
    func autoConfigureIfNeeded() async {
        let currentServers = configuredServers
        if currentServers.isEmpty {
            let discovered = await Self.autoDiscoverServers()
            if let first = discovered.first {
                let config = EdgeTTSServerConfig(name: "Auto-discovered", url: first, apiKey: "")
                setServers([config])
                DebugLogger.log(flow: "edge_tts", step: "auto_configure", details: ["discovered": discovered, "selected": first])
            }
        }
    }

    /// Update a specific server config's latency fields
    private func updateServerLatency(id: UUID, latencyMs: Double?) {
        guard var data = UserDefaults.standard.data(forKey: Self.serverListKey),
              var configs = try? JSONDecoder().decode([EdgeTTSServerConfig].self, from: data) else { return }
        if let idx = configs.firstIndex(where: { $0.id == id }) {
            configs[idx].lastLatencyMs = latencyMs
            configs[idx].lastChecked = Date()
            if let encoded = try? JSONEncoder().encode(configs) {
                UserDefaults.standard.set(encoded, forKey: Self.serverListKey)
            }
        }
    }

    /// Get fastest server (lowest latency)
    func fastestServer() -> EdgeTTSServerConfig? {
        let servers = configuredServers
        return servers
            .filter { $0.lastLatencyMs != nil }
            .min(by: { ($0.lastLatencyMs ?? .infinity) < ($1.lastLatencyMs ?? .infinity) })
    }

    func setServers(_ servers: [EdgeTTSServerConfig]) {
        let trimmed = servers.map { EdgeTTSServerConfig(id: $0.id, name: $0.name, url: $0.url, apiKey: $0.apiKey) }.filter { !$0.url.isEmpty }
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: Self.serverListKey)
        }
        // Persist apiKeys to Keychain
        for server in trimmed {
            _ = try? KeychainUtility.saveString(key: KeychainUtility.accountKey(for: server.id, suffix: "apiKey"), value: server.apiKey)
        }
        // Clean up orphaned keys
        let validIDs = Set(trimmed.map { $0.id })
        if let allKeys = try? KeychainUtility.allKeys(for: KeychainUtility.service) {
            for key in allKeys {
                if let uuidStr = key.split(separator: "_").first, let uuid = UUID(uuidString: String(uuidStr)), !validIDs.contains(uuid) {
                    try? KeychainUtility.delete(key: key)
                }
            }
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

    private func buildGetRequest(to endpoint: URL, text: String, voice: String?, rate: Int, pitch: Int, style: String, volume: String = "default", apiKey: String) throws -> URLRequest {
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
        if volume != "default" {
            items.append(URLQueryItem(name: "vol", value: volume))
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

    static func buildSSML(text: String, voice: String?, rate: Double, pitch: Double, emotionTag: String?, volume: String = "default") -> String {
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
        let volumeAttr: String
        if volume != "default" {
            volumeAttr = " volume=\"\(volume)\""
        } else {
            volumeAttr = ""
        }

        var result = "<prosody rate=\"\(rateValue)\" pitch=\"\(pitchValue)\"\(volumeAttr)>"
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

    private func cacheKey(text: String, voice: String?, rate: Double, pitch: Double, style: String, volume: String) -> String {
        "\(text)|\(voice ?? "")|\(rate)|\(pitch)|\(style)|\(volume)".stableHash
    }

    private func getCachedData(for key: String) -> Data? {
        evictExpiredCache()
        if let entry = ttsCache[key] {
            ttsCache[key] = (entry.data, Date()) // Update timestamp for LRU
            return entry.data
        }
        return nil
    }

    private func setCachedData(_ data: Data, for key: String) {
        evictExpiredCache()
        if ttsCache.count >= ttsCacheMaxSize {
            // Remove oldest entry (LRU)
            if let oldestKey = ttsCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                ttsCache.removeValue(forKey: oldestKey)
            }
        }
        ttsCache[key] = (data, Date())
    }

    private func evictExpiredCache() {
        let now = Date()
        let expiredKeys = ttsCache.compactMap { key, entry in
            now.timeIntervalSince(entry.timestamp) > ttsCacheMaxAge ? key : nil
        }
        for key in expiredKeys {
            ttsCache.removeValue(forKey: key)
        }
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
