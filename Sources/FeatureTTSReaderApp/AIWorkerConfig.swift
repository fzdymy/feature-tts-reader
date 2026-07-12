import Foundation

/// AI 剧本解析 Worker 配置（用户可配置多个，像 TTS 服务器一样管理）
struct AIWorkerConfig: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var baseURL: String
    var authKey: String
    var model: String
    var sliceCharLimit: Int
    var timeout: TimeInterval
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        authKey: String,
        model: String = "qwen-plus",
        sliceCharLimit: Int = 1000,
        timeout: TimeInterval = 30,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.authKey = authKey
        self.model = model
        self.sliceCharLimit = sliceCharLimit
        self.timeout = timeout
        self.isDefault = isDefault
    }
}

/// AI Worker 返回的单个剧本片段
struct AISegment: Codable, Hashable {
    let speaker: String
    let emotion: Emotion
    let tone: String
    let text: String
}

/// 情绪枚举（与 Worker schema 对齐）
enum Emotion: String, Codable, CaseIterable {
    case angry, sad, cheerful, neutral, fearful, surprised, disgusted, calm

    /// 映射到 Edge TTS SSML style
    var ssmlStyle: String {
        switch self {
        case .angry: return "angry"
        case .sad: return "sad"
        case .cheerful: return "cheerful"
        case .fearful: return "fearful"
        case .surprised: return "cheerful"  // 惊讶用 cheerful 近似
        case .disgusted: return "angry"     // 厌恶用 angry 近似
        case .calm, .neutral: return "neutral"
        }
    }
}

/// AI Worker 处理结果
struct AIWorkerResult: Codable {
    let segments: [AISegment]
    let nextContext: String?
}

/// AI Worker 请求体
struct AIWorkerRequest: Codable {
    let text: String
    let sliceIndex: Int
    let totalSlices: Int
    let context: String?
}