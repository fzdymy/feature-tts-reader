import Foundation

/// Edge TTS 服务器配置
struct EdgeTTSServerConfig: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var url: String
    var apiKey: String
    var lastLatencyMs: Double?
    var lastChecked: Date?

    init(id: UUID = UUID(), name: String = "默认", url: String, apiKey: String = "", lastLatencyMs: Double? = nil, lastChecked: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastLatencyMs = lastLatencyMs
        self.lastChecked = lastChecked
    }
}