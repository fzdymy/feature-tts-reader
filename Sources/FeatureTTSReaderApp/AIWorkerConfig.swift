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
    var isEnabled: Bool
    var priority: Int

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        authKey: String,
        model: String = "qwen-plus",
        sliceCharLimit: Int = 1000,
        timeout: TimeInterval = 30,
        isDefault: Bool = false,
        isEnabled: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.authKey = authKey
        self.model = model
        self.sliceCharLimit = sliceCharLimit
        self.timeout = timeout
        self.isDefault = isDefault
        self.isEnabled = isEnabled
        self.priority = priority
    }
}

/// AI Worker 返回的单个剧本片段
struct AISegment: Codable, Hashable {
    let speaker: String
    let emotion: Emotion
    let tone: String
    let text: String
    let gender: Gender

    enum CodingKeys: String, CodingKey {
        case speaker, emotion, tone, text, gender
    }

    init(speaker: String, emotion: Emotion, tone: String, text: String, gender: Gender = .unknown) {
        self.speaker = speaker
        self.emotion = emotion
        self.tone = tone
        self.text = text
        self.gender = gender
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speaker = try c.decode(String.self, forKey: .speaker)
        emotion = try c.decode(Emotion.self, forKey: .emotion)
        tone = (try? c.decode(String.self, forKey: .tone)) ?? ""
        text = try c.decode(String.self, forKey: .text)
        gender = (try? c.decode(Gender.self, forKey: .gender)) ?? .unknown
    }
}

/// 性别（AI Worker 检测，客户端名字关键词兜底）
enum Gender: String, Codable, Hashable {
    case male, female, unknown

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self))?.lowercased() ?? "unknown"
        switch raw {
        case "male", "m", "男": self = .male
        case "female", "f", "女": self = .female
        default: self = .unknown
        }
    }
}

/// 情绪枚举（与 Worker schema 和 Edge TTS styles 对齐）
enum Emotion: Codable, CaseIterable {
    case neutral, happy, angry, sad, fearful, whispering, excited
    case cheerful, calm, surprised, disgusted, shouting, hopeful
    case embarrassed, relieved, confused, determined, gentle, affectionate

    var rawValue: String {
        switch self {
        case .neutral: return "neutral"
        case .happy: return "happy"
        case .angry: return "angry"
        case .sad: return "sad"
        case .fearful: return "fearful"
        case .whispering: return "whispering"
        case .excited: return "excited"
        case .cheerful: return "cheerful"
        case .calm: return "calm"
        case .surprised: return "surprised"
        case .disgusted: return "disgusted"
        case .shouting: return "shouting"
        case .hopeful: return "hopeful"
        case .embarrassed: return "embarrassed"
        case .relieved: return "relieved"
        case .confused: return "confused"
        case .determined: return "determined"
        case .gentle: return "gentle"
        case .affectionate: return "affectionate"
        }
    }

    var chineseLabel: String {
        switch self {
        case .neutral: return "中性"
        case .happy: return "开心"
        case .angry: return "愤怒"
        case .sad: return "悲伤"
        case .fearful: return "恐惧"
        case .whispering: return "低语"
        case .excited: return "激动"
        case .cheerful: return "愉快"
        case .calm: return "平静"
        case .surprised: return "惊讶"
        case .disgusted: return "厌恶"
        case .shouting: return "喊叫"
        case .hopeful: return "希望"
        case .embarrassed: return "尴尬"
        case .relieved: return "如释重负"
        case .confused: return "困惑"
        case .determined: return "坚定"
        case .gentle: return "温柔"
        case .affectionate: return "深情"
        }
    }

    /// 映射到 Edge TTS style 名称
    var ssmlStyle: String {
        switch self {
        case .angry: return "angry"
        case .sad: return "sad"
        case .fearful: return "fearful"
        case .whispering: return "whispering"
        case .excited: return "excited"
        case .happy: return "happy"
        case .cheerful: return "cheerful"
        case .calm: return "calm"
        case .surprised: return "surprised"
        case .disgusted: return "disgusted"
        case .shouting: return "shouting"
        case .hopeful: return "hopeful"
        case .embarrassed: return "embarrassed"
        case .relieved: return "relieved"
        case .confused: return "confused"
        case .determined: return "determined"
        case .gentle: return "gentle"
        case .affectionate: return "affectionate"
        case .neutral: return "neutral"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self).lowercased()
        switch raw {
        case "neutral": self = .neutral
        case "happy", "happiness": self = .happy
        case "angry", "anger": self = .angry
        case "sad", "sadness": self = .sad
        case "fearful", "fear": self = .fearful
        case "whispering", "whisper": self = .whispering
        case "excited", "excitement": self = .excited
        case "cheerful": self = .cheerful
        case "calm": self = .calm
        case "surprised", "surprise": self = .surprised
        case "disgusted", "disgust": self = .disgusted
        case "shouting": self = .shouting
        case "hopeful", "hope": self = .hopeful
        case "embarrassed", "embarrassment": self = .embarrassed
        case "relieved", "relief": self = .relieved
        case "confused", "confusion": self = .confused
        case "determined", "determination": self = .determined
        case "gentle": self = .gentle
        case "affectionate": self = .affectionate
        default: self = .neutral
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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
    let focusFromParagraph: Int?
}