import Foundation

// MARK: - Sort Option
enum SortOption: String, CaseIterable, Identifiable {
    case recent = "recent"
    case title = "title"
    case progress = "progress"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .recent: return "最近阅读"
        case .title: return "标题"
        case .progress: return "阅读进度"
        }
    }
}

struct BookChapter: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    var text: String

    enum CodingKeys: String, CodingKey { case id, title }

    init(id: UUID, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        text = ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
    }

    var preview: String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 120 { return cleaned }
        return String(cleaned.prefix(120)) + "..."
    }
}

struct Book: Identifiable, Hashable {
    let id: UUID
    var title: String
    var text: String
    var importedAt: Date

    init(id: UUID, title: String, text: String, importedAt: Date) {
        self.id = id
        self.title = title
        self.text = text
        self.importedAt = importedAt
    }

    var preview: String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 120 { return cleaned }
        return String(cleaned.prefix(120)) + "..."
    }
}

extension Book: Codable {
    enum CodingKeys: String, CodingKey { case id, title, importedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        text = ""
        importedAt = try c.decode(Date.self, forKey: .importedAt)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(importedAt, forKey: .importedAt)
    }
}

struct CharacterProfile: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var aliases: [String]
    var gender: String
    var age: String
    var tone: String
    var voice: String
    var rate: Int
    var pitch: Int
    var style: String
    var sensitivity: Int
    var isNarrator: Bool = false
    var role: CharacterRole = .character

    var info: String {
        [gender, age, tone].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    init(id: UUID, name: String, aliases: [String] = [], gender: String, age: String, tone: String, voice: String, rate: Int, pitch: Int, style: String, sensitivity: Int, isNarrator: Bool = false, role: CharacterRole = .character) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.gender = gender
        self.age = age
        self.tone = tone
        self.voice = voice
        self.rate = rate
        self.pitch = pitch
        self.style = style
        self.sensitivity = sensitivity
        self.isNarrator = isNarrator
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, gender, age, tone, voice, rate, pitch, style, sensitivity, isNarrator, role
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        gender = try c.decode(String.self, forKey: .gender)
        age = try c.decode(String.self, forKey: .age)
        tone = try c.decode(String.self, forKey: .tone)
        voice = try c.decode(String.self, forKey: .voice)
        rate = try c.decode(Int.self, forKey: .rate)
        pitch = try c.decode(Int.self, forKey: .pitch)
        style = try c.decode(String.self, forKey: .style)
        sensitivity = try c.decode(Int.self, forKey: .sensitivity)
        isNarrator = try c.decodeIfPresent(Bool.self, forKey: .isNarrator) ?? false
        role = try c.decodeIfPresent(CharacterRole.self, forKey: .role) ?? .character
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(gender, forKey: .gender)
        try c.encode(age, forKey: .age)
        try c.encode(tone, forKey: .tone)
        try c.encode(voice, forKey: .voice)
        try c.encode(rate, forKey: .rate)
        try c.encode(pitch, forKey: .pitch)
        try c.encode(style, forKey: .style)
        try c.encode(sensitivity, forKey: .sensitivity)
        try c.encode(isNarrator, forKey: .isNarrator)
        try c.encode(role, forKey: .role)
    }
}

enum CharacterRole: String, Codable, CaseIterable {
    case narrator = "narrator"
    case character = "character"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .narrator: return "旁白"
        case .character: return "角色"
        case .unknown: return "未知"
        }
    }
}

enum VoiceGender: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"

    var displayName: String {
        switch self {
        case .male: return "男声"
        case .female: return "女声"
        }
    }
}

/// 音质等级
enum VoiceTier: Int, Comparable, Codable {
    case standard = 0
    case multilingual = 1
    case hd = 2
    case mai = 3

    static func < (lhs: VoiceTier, rhs: VoiceTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .standard: return "标准"
        case .multilingual: return "多语言"
        case .hd: return "高清"
        case .mai: return "超拟真"
        }
    }
}

struct VoiceItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let locale: String
    let gender: VoiceGender
    let styleList: [String]?

    var displayName: String {
        name.isEmpty ? id : name
    }

    static func defaultItems() -> [VoiceItem] {
        [VoiceCatalog.chinese35.first ?? VoiceItem(id: "zh-CN-XiaoxiaoNeural", name: "晓晓", locale: "zh-CN", gender: .female, styleList: nil)]
    }
}

enum VoiceCatalogSource: String, CaseIterable, Codable, Identifiable {
    case chinese35
    case fullChinese

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .chinese35: return "经典音色 (40)"
        case .fullChinese: return "全音色 (76)"
        }
    }

    var voices: [VoiceItem] {
        switch self {
        case .chinese35: return VoiceCatalog.chinese35
        case .fullChinese: return VoiceCatalog.fullChinese
        }
    }
}

struct BookBookmark: Identifiable, Hashable, Codable {
    let id: UUID
    let chapterID: UUID
    let chapterTitle: String
    let percent: Double
    let note: String
    let createdAt: Date
}

struct TTSQueueItem: Identifiable, Codable, Hashable {
    let id = UUID()
    let segment: ScriptSegment
    let audioURL: URL
    let chapterTitle: String
    let bookTitle: String
    let bookID: String
    let chapterIndex: Int
    let segmentIndex: Int
    let totalSegments: Int

    enum CodingKeys: String, CodingKey {
        case segment, audioURL, chapterTitle, bookTitle, bookID, chapterIndex, segmentIndex, totalSegments
    }
}

enum ReaderTheme: String, CaseIterable, Codable, Identifiable {
    case light
    case dark
    case sepia

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .light: return "日间"
        case .dark: return "夜间"
        case .sepia: return "护眼"
        }
    }
}

struct ScriptSegment: Identifiable, Hashable, Codable {
    let id: UUID
    let characterName: String
    let voice: String
    let rate: Int
    let pitch: Int
    let style: String
    let text: String
}

struct CharacterRecommendation: Identifiable, Hashable, Codable {
    let id: UUID
    var profile: CharacterProfile
    var count: Int
    var suggestedVoices: [VoiceItem]
}

// MARK: - TTS 服务器

struct TTSServer: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var isActive: Bool
    var maxTextLength: Int

    init(id: UUID = UUID(), name: String, baseURL: String, apiKey: String = "", isActive: Bool = false, maxTextLength: Int = 1024) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.isActive = isActive
        self.maxTextLength = maxTextLength
    }
}

// MARK: - 音色微调档案

struct VoiceProfileTuning: Identifiable, Hashable, Codable {
    let id: UUID
    var sourceVoiceID: String
    var alias: String
    var tags: [String]
    var rateOffset: Int
    var pitchOffset: Int
    var style: String

    init(id: UUID = UUID(), sourceVoiceID: String, alias: String, tags: [String] = [],
         rateOffset: Int = 0, pitchOffset: Int = 0, style: String = "neutral") {
        self.id = id
        self.sourceVoiceID = sourceVoiceID
        self.alias = alias
        self.tags = tags
        self.rateOffset = rateOffset
        self.pitchOffset = pitchOffset
        self.style = style
    }
}

// MARK: - 标签预设

enum TagCategory: String, Codable, CaseIterable, Identifiable {
    case role       // 角色定位
    case age        // 年龄段
    case trait      // 性格
    case roleType   // 角色类型

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .role: return "角色定位"
        case .age: return "年龄段"
        case .trait: return "性格"
        case .roleType: return "角色类型"
        }
    }
}

struct TagPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var category: TagCategory

    init(id: UUID = UUID(), name: String, category: TagCategory) {
        self.id = id
        self.name = name
        self.category = category
    }
}

// MARK: - 导出格式

struct TTSExport: Codable {
    let version: Int
    let exportedAt: Date
    var profiles: [VoiceProfileTuning]
    var tags: [TagPreset]
}

// MARK: - 推荐模板

struct RoleTemplate: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var roles: [TemplateRole]
    // 未匹配角色的容灾
    var fallbackMaleVoiceID: String
    var fallbackFemaleVoiceID: String
    var fallbackRateOffset: Int
    var fallbackPitchOffset: Int
    var fallbackStyle: String

    init(id: UUID = UUID(), name: String, roles: [TemplateRole] = [],
         fallbackMaleVoiceID: String = "", fallbackFemaleVoiceID: String = "",
         fallbackRateOffset: Int = 0, fallbackPitchOffset: Int = 0, fallbackStyle: String = "neutral") {
        self.id = id
        self.name = name
        self.roles = roles
        self.fallbackMaleVoiceID = fallbackMaleVoiceID
        self.fallbackFemaleVoiceID = fallbackFemaleVoiceID
        self.fallbackRateOffset = fallbackRateOffset
        self.fallbackPitchOffset = fallbackPitchOffset
        self.fallbackStyle = fallbackStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        roles = try container.decode([TemplateRole].self, forKey: .roles)
        fallbackMaleVoiceID = try container.decodeIfPresent(String.self, forKey: .fallbackMaleVoiceID) ?? ""
        fallbackFemaleVoiceID = try container.decodeIfPresent(String.self, forKey: .fallbackFemaleVoiceID) ?? ""
        fallbackRateOffset = try container.decodeIfPresent(Int.self, forKey: .fallbackRateOffset) ?? 0
        fallbackPitchOffset = try container.decodeIfPresent(Int.self, forKey: .fallbackPitchOffset) ?? 0
        fallbackStyle = try container.decodeIfPresent(String.self, forKey: .fallbackStyle) ?? "neutral"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, roles, fallbackMaleVoiceID, fallbackFemaleVoiceID, fallbackRateOffset, fallbackPitchOffset, fallbackStyle
    }
}

struct TemplateRole: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var sourceVoiceID: String
    var voiceSuggestion: String
    var rateOffset: Int
    var pitchOffset: Int
    var style: String

    init(id: UUID = UUID(), title: String, sourceVoiceID: String = "",
         voiceSuggestion: String = "",
         rateOffset: Int = 0, pitchOffset: Int = 0, style: String = "neutral") {
        self.id = id
        self.title = title
        self.sourceVoiceID = sourceVoiceID
        self.voiceSuggestion = voiceSuggestion
        self.rateOffset = rateOffset
        self.pitchOffset = pitchOffset
        self.style = style
    }
}

struct TemplateExport: Codable {
    let version: Int
    let exportedAt: Date
    var templates: [RoleTemplate]
}

struct ReaderState: Codable {
    var bookText: String = ""
    var chapters: [BookChapter]
    var characters: [CharacterProfile]
    var scriptSegments: [ScriptSegment]
    var selectedChapterID: UUID?
    var apiEndpoint: String
    var apiKey: String
    var books: [Book]
    var currentBookTitle: String
    var currentBookID: String
    var currentBookProgress: Double
    var readerFontSize: Double
    var readerLineSpacing: Double
    var readerTheme: ReaderTheme
    var selectedVoiceCatalog: VoiceCatalogSource
    var defaultVoice: String
    var defaultRate: Int
    var defaultPitch: Int
    var defaultStyle: String
    var bookmarks: [BookBookmark]
    var bookProgressByChapter: [UUID: Double]
    var lastReadChapterIndexByBook: [UUID: Int]
    var defaultSensitivity: Int
    var playTimeoutSeconds: Double = 30.0
    var lastScannedBookText: String = ""
    var readerFontName: String = "PingFang SC"
    var readerParagraphSpacing: Double = 8
    var customBackgroundImage: Data?
    var showChapterTitle: Bool = true
    var showProgressBar: Bool = true
    var showPageNumber: Bool = true
    var showTime: Bool = true
    var showBattery: Bool = true
    var showBookCover: Bool = true
    var showReadingProgress: Bool = true
    var ttsQueue: [TTSQueueItem]?
    var ttsCurrentIndex: Int?
    var ttsIsPlaying: Bool?
    var ttsChapterTitle: String?
    var ttsSegmentTitle: String?
    var recommendations: [CharacterRecommendation]?
    var statusMessage: String = "请导入小说或粘贴文本。"
    var isBusy: Bool = false
    var currentPlayingLine: String = ""
    var playProgress: Double = 0.0
    var isSpeaking: Bool = false
    var defaultMaleVoiceID: String = ""
    var defaultFemaleVoiceID: String = ""
    var defaultFallbackRateOffset: Int = 0
    var defaultFallbackPitchOffset: Int = 0
    var defaultFallbackStyle: String = "neutral"

    private enum CodingKeys: String, CodingKey {
        case characters, scriptSegments, selectedChapterID, apiEndpoint, apiKey,
             books, currentBookTitle, currentBookID, currentBookProgress, readerFontSize, readerLineSpacing,
             readerTheme, selectedVoiceCatalog, defaultVoice, defaultRate, defaultPitch, defaultStyle, bookmarks, bookProgressByChapter, lastReadChapterIndexByBook, defaultSensitivity, playTimeoutSeconds, readerFontName, readerParagraphSpacing, customBackgroundImage, showChapterTitle, showProgressBar, showPageNumber, showTime, showBattery, showBookCover, showReadingProgress, ttsQueue, ttsCurrentIndex, ttsIsPlaying, ttsChapterTitle, ttsSegmentTitle, recommendations, statusMessage, isBusy, currentPlayingLine, playProgress, isSpeaking, defaultMaleVoiceID, defaultFemaleVoiceID, defaultFallbackRateOffset, defaultFallbackPitchOffset, defaultFallbackStyle
    }

    init(
        bookText: String = "",
        chapters: [BookChapter] = [],
        characters: [CharacterProfile] = [],
        scriptSegments: [ScriptSegment] = [],
        selectedChapterID: UUID? = nil,
        apiEndpoint: String = "http://127.0.0.1:8080",
        apiKey: String = "",
        books: [Book] = [],
        currentBookTitle: String = "",
        currentBookID: String = UUID().uuidString,
        currentBookProgress: Double = 0,
        readerFontSize: Double = 18,
        readerLineSpacing: Double = 8,
        readerTheme: ReaderTheme = .light,
        selectedVoiceCatalog: VoiceCatalogSource = .chinese35,
        defaultVoice: String = "zh-CN-XiaoxiaoNeural",
        defaultRate: Int = 0,
        defaultPitch: Int = 0,
        defaultStyle: String = "neutral",
        bookmarks: [BookBookmark] = [],
        bookProgressByChapter: [UUID: Double] = [:],
        lastReadChapterIndexByBook: [UUID: Int] = [:],
        defaultSensitivity: Int = 50,
        lastScannedBookText: String = "",
        playTimeoutSeconds: Double = 30.0,
        readerFontName: String = "PingFang SC",
        readerParagraphSpacing: Double = 8,
        customBackgroundImage: Data? = nil,
        showChapterTitle: Bool = true,
        showProgressBar: Bool = true,
        showPageNumber: Bool = true,
        showTime: Bool = true,
        showBattery: Bool = true,
        showBookCover: Bool = true,
        showReadingProgress: Bool = true,
        ttsQueue: [TTSQueueItem]? = nil,
        ttsCurrentIndex: Int? = nil,
        ttsIsPlaying: Bool? = nil,
        ttsChapterTitle: String? = nil,
        ttsSegmentTitle: String? = nil,
        recommendations: [CharacterRecommendation]? = nil,
        statusMessage: String = "请导入小说或粘贴文本。",
        isBusy: Bool = false,
        currentPlayingLine: String = "",
        playProgress: Double = 0.0,
        isSpeaking: Bool = false,
        defaultMaleVoiceID: String = "",
        defaultFemaleVoiceID: String = "",
        defaultFallbackRateOffset: Int = 0,
        defaultFallbackPitchOffset: Int = 0,
        defaultFallbackStyle: String = "neutral"
    ) {
        self.bookText = bookText
        self.chapters = chapters
        self.characters = characters
        self.scriptSegments = scriptSegments
        self.selectedChapterID = selectedChapterID
        self.apiEndpoint = apiEndpoint
        self.apiKey = apiKey
        self.books = books
        self.currentBookTitle = currentBookTitle
        self.currentBookID = currentBookID
        self.currentBookProgress = currentBookProgress
        self.readerFontSize = readerFontSize
        self.readerLineSpacing = readerLineSpacing
        self.readerTheme = readerTheme
        self.selectedVoiceCatalog = selectedVoiceCatalog
        self.defaultVoice = defaultVoice
        self.defaultRate = defaultRate
        self.defaultPitch = defaultPitch
        self.defaultStyle = defaultStyle
        self.bookmarks = bookmarks
        self.bookProgressByChapter = bookProgressByChapter
        self.lastReadChapterIndexByBook = lastReadChapterIndexByBook
        self.defaultSensitivity = defaultSensitivity
        self.lastScannedBookText = lastScannedBookText
        self.playTimeoutSeconds = playTimeoutSeconds
        self.readerFontName = readerFontName
        self.readerParagraphSpacing = readerParagraphSpacing
        self.customBackgroundImage = customBackgroundImage
        self.showChapterTitle = showChapterTitle
        self.showProgressBar = showProgressBar
        self.showPageNumber = showPageNumber
        self.showTime = showTime
        self.showBattery = showBattery
        self.showBookCover = showBookCover
        self.showReadingProgress = showReadingProgress
        self.ttsQueue = ttsQueue
        self.ttsCurrentIndex = ttsCurrentIndex
        self.ttsIsPlaying = ttsIsPlaying
        self.ttsChapterTitle = ttsChapterTitle
        self.ttsSegmentTitle = ttsSegmentTitle
        self.recommendations = recommendations
        self.statusMessage = statusMessage
        self.isBusy = isBusy
        self.currentPlayingLine = currentPlayingLine
        self.playProgress = playProgress
        self.isSpeaking = isSpeaking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chapters = []
        bookText = ""
        characters = try container.decodeIfPresent([CharacterProfile].self, forKey: .characters) ?? []
        scriptSegments = try container.decodeIfPresent([ScriptSegment].self, forKey: .scriptSegments) ?? []
        selectedChapterID = try container.decodeIfPresent(UUID.self, forKey: .selectedChapterID)
        apiEndpoint = try container.decodeIfPresent(String.self, forKey: .apiEndpoint) ?? "http://127.0.0.1:8080"
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        books = try container.decodeIfPresent([Book].self, forKey: .books) ?? []
        currentBookTitle = try container.decodeIfPresent(String.self, forKey: .currentBookTitle) ?? ""
        currentBookID = try container.decodeIfPresent(String.self, forKey: .currentBookID) ?? UUID().uuidString
        currentBookProgress = try container.decodeIfPresent(Double.self, forKey: .currentBookProgress) ?? 0
        readerFontSize = try container.decodeIfPresent(Double.self, forKey: .readerFontSize) ?? 18
        readerLineSpacing = try container.decodeIfPresent(Double.self, forKey: .readerLineSpacing) ?? 8
        readerTheme = try container.decodeIfPresent(ReaderTheme.self, forKey: .readerTheme) ?? .light
        selectedVoiceCatalog = {
            let raw = try? container.decodeIfPresent(String.self, forKey: .selectedVoiceCatalog)
            return raw.flatMap(VoiceCatalogSource.init(rawValue:)) ?? .chinese35
        }()
        defaultVoice = try container.decodeIfPresent(String.self, forKey: .defaultVoice) ?? "zh-CN-XiaoxiaoNeural"
        defaultRate = try container.decodeIfPresent(Int.self, forKey: .defaultRate) ?? 0
        defaultPitch = try container.decodeIfPresent(Int.self, forKey: .defaultPitch) ?? 0
        defaultStyle = try container.decodeIfPresent(String.self, forKey: .defaultStyle) ?? "neutral"
        bookmarks = try container.decodeIfPresent([BookBookmark].self, forKey: .bookmarks) ?? []
        bookProgressByChapter = try container.decodeIfPresent([UUID: Double].self, forKey: .bookProgressByChapter) ?? [:]
        lastReadChapterIndexByBook = try container.decodeIfPresent([UUID: Int].self, forKey: .lastReadChapterIndexByBook) ?? [:]
        defaultSensitivity = try container.decodeIfPresent(Int.self, forKey: .defaultSensitivity) ?? 50
        playTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .playTimeoutSeconds) ?? 30.0
        ttsQueue = try container.decodeIfPresent([TTSQueueItem].self, forKey: .ttsQueue)
        ttsCurrentIndex = try container.decodeIfPresent(Int.self, forKey: .ttsCurrentIndex)
        ttsIsPlaying = try container.decodeIfPresent(Bool.self, forKey: .ttsIsPlaying)
        ttsChapterTitle = try container.decodeIfPresent(String.self, forKey: .ttsChapterTitle)
        ttsSegmentTitle = try container.decodeIfPresent(String.self, forKey: .ttsSegmentTitle)
        recommendations = try container.decodeIfPresent([CharacterRecommendation].self, forKey: .recommendations)
        statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage) ?? "请导入小说或粘贴文本。"
        isBusy = try container.decodeIfPresent(Bool.self, forKey: .isBusy) ?? false
        currentPlayingLine = try container.decodeIfPresent(String.self, forKey: .currentPlayingLine) ?? ""
        playProgress = try container.decodeIfPresent(Double.self, forKey: .playProgress) ?? 0.0
        isSpeaking = try container.decodeIfPresent(Bool.self, forKey: .isSpeaking) ?? false
        defaultMaleVoiceID = try container.decodeIfPresent(String.self, forKey: .defaultMaleVoiceID) ?? ""
        defaultFemaleVoiceID = try container.decodeIfPresent(String.self, forKey: .defaultFemaleVoiceID) ?? ""
        defaultFallbackRateOffset = try container.decodeIfPresent(Int.self, forKey: .defaultFallbackRateOffset) ?? 0
        defaultFallbackPitchOffset = try container.decodeIfPresent(Int.self, forKey: .defaultFallbackPitchOffset) ?? 0
        defaultFallbackStyle = try container.decodeIfPresent(String.self, forKey: .defaultFallbackStyle) ?? "neutral"
    }
}
