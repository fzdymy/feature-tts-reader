import Foundation

struct BookChapter: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let text: String

    var preview: String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 120 { return cleaned }
        return String(cleaned.prefix(120)) + "..."
    }
}

struct Book: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var text: String
    var importedAt: Date

    var preview: String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 120 { return cleaned }
        return String(cleaned.prefix(120)) + "..."
    }
}

struct CharacterProfile: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var gender: String
    var age: String
    var tone: String
    var voice: String
    var rate: Int
    var pitch: Int
    var style: String
    var sensitivity: Int

    var info: String {
        [gender, age, tone].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct VoiceItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let locale: String
    let styleList: [String]?

    var displayName: String {
        name.isEmpty ? id : name
    }

    static func defaultItems() -> [VoiceItem] {
        [
            VoiceItem(id: "zh-CN-XiaoxiaoNeural", name: "标准女声", locale: "zh-CN", styleList: nil),
            VoiceItem(id: "zh-CN-YunxiNeural", name: "年轻男声", locale: "zh-CN", styleList: nil),
            VoiceItem(id: "zh-CN-XiaohanNeural", name: "活力女声", locale: "zh-CN", styleList: nil),
            VoiceItem(id: "zh-CN-YunjianNeural", name: "成熟男声", locale: "zh-CN", styleList: nil),
            VoiceItem(id: "zh-CN-XiaomoNeural", name: "温柔女声", locale: "zh-CN", styleList: nil)
        ]
    }
}

enum VoiceCatalogSource: String, CaseIterable, Codable, Identifiable {
    case remote
    case chinese35
    case fullChinese

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .remote: return "远程服务"
        case .chinese35: return "本地 35 种音色"
        case .fullChinese: return "本地 full 音色"
        }
    }

    var resourceName: String? {
        switch self {
        case .remote: return nil
        case .chinese35: return "chinese_voices_35"
        case .fullChinese: return "full_chinese_voices"
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
    let chapterIndex: Int
    let bookID: UUID
    let segmentIndex: Int
    let totalSegments: Int
}

enum ReaderTheme: String, CaseIterable, Codable {
    case light
    case dark
    case sepia

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

struct ReaderState: Codable {
    var bookText: String
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
    var ttsQueue: [TTSQueueItem]?
    var ttsCurrentIndex: Int?
    var ttsIsPlaying: Bool?
    var ttsChapterTitle: String?
    var ttsSegmentTitle: String?

    private enum CodingKeys: String, CodingKey {
        case bookText, chapters, characters, scriptSegments, selectedChapterID, apiEndpoint, apiKey,
             books, currentBookTitle, currentBookID, currentBookProgress, readerFontSize, readerLineSpacing,
             readerTheme, selectedVoiceCatalog, defaultVoice, defaultRate, defaultPitch, defaultStyle, bookmarks, bookProgressByChapter, lastReadChapterIndexByBook, defaultSensitivity, lastScannedBookText, playTimeoutSeconds, readerFontName, readerParagraphSpacing, customBackgroundImage, showChapterTitle, showProgressBar, showPageNumber, showTime, showBattery, ttsQueue, ttsCurrentIndex, ttsIsPlaying, ttsChapterTitle, ttsSegmentTitle
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
        selectedVoiceCatalog: VoiceCatalogSource = .remote,
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
        ttsQueue: [TTSQueueItem]? = nil,
        ttsCurrentIndex: Int? = nil,
        ttsIsPlaying: Bool? = nil,
        ttsChapterTitle: String? = nil,
        ttsSegmentTitle: String? = nil
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookText = try container.decodeIfPresent(String.self, forKey: .bookText) ?? ""
        chapters = try container.decodeIfPresent([BookChapter].self, forKey: .chapters) ?? []
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
        selectedVoiceCatalog = try container.decodeIfPresent(VoiceCatalogSource.self, forKey: .selectedVoiceCatalog) ?? .remote
        defaultVoice = try container.decodeIfPresent(String.self, forKey: .defaultVoice) ?? "zh-CN-XiaoxiaoNeural"
        defaultRate = try container.decodeIfPresent(Int.self, forKey: .defaultRate) ?? 0
        defaultPitch = try container.decodeIfPresent(Int.self, forKey: .defaultPitch) ?? 0
        defaultStyle = try container.decodeIfPresent(String.self, forKey: .defaultStyle) ?? "neutral"
        bookmarks = try container.decodeIfPresent([BookBookmark].self, forKey: .bookmarks) ?? []
        bookProgressByChapter = try container.decodeIfPresent([UUID: Double].self, forKey: .bookProgressByChapter) ?? [:]
        lastReadChapterIndexByBook = try container.decodeIfPresent([UUID: Int].self, forKey: .lastReadChapterIndexByBook) ?? [:]
        defaultSensitivity = try container.decodeIfPresent(Int.self, forKey: .defaultSensitivity) ?? 50
        lastScannedBookText = try container.decodeIfPresent(String.self, forKey: .lastScannedBookText) ?? ""
        playTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .playTimeoutSeconds) ?? 30.0
        ttsQueue = try container.decodeIfPresent([TTSQueueItem].self, forKey: .ttsQueue)
        ttsCurrentIndex = try container.decodeIfPresent(Int.self, forKey: .ttsCurrentIndex)
        ttsIsPlaying = try container.decodeIfPresent(Bool.self, forKey: .ttsIsPlaying)
        ttsChapterTitle = try container.decodeIfPresent(String.self, forKey: .ttsChapterTitle)
        ttsSegmentTitle = try container.decodeIfPresent(String.self, forKey: .ttsSegmentTitle)
    }
}
