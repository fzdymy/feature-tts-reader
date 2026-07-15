import Foundation

/// Edge TTS 服务器配置
struct EdgeTTSServerConfig: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var url: String
    private var _apiKey: String = ""
    var lastLatencyMs: Double?
    var lastChecked: Date?

    var apiKey: String {
        get {
            do {
                return try KeychainUtility.loadString(key: KeychainUtility.accountKey(for: id, suffix: "apiKey"))
            } catch {
                return _apiKey
            }
        }
        set {
            _apiKey = newValue
            try? KeychainUtility.saveString(key: KeychainUtility.accountKey(for: id, suffix: "apiKey"), value: newValue)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url, lastLatencyMs, lastChecked
    }

    init(id: UUID = UUID(), name: String = "默认", url: String, apiKey: String = "", lastLatencyMs: Double? = nil, lastChecked: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastLatencyMs = lastLatencyMs
        self.lastChecked = lastChecked
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        lastLatencyMs = try c.decodeIfPresent(Double.self, forKey: .lastLatencyMs)
        lastChecked = try c.decodeIfPresent(Date.self, forKey: .lastChecked)
        _apiKey = ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(lastLatencyMs, forKey: .lastLatencyMs)
        try c.encodeIfPresent(lastChecked, forKey: .lastChecked)
    }
}