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
}

struct BookBookmark: Identifiable, Hashable, Codable {
    let id: UUID
    let chapterID: UUID
    let chapterTitle: String
    let percent: Double
    let note: String
    let createdAt: Date
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
    var defaultVoice: String
    var defaultRate: Int
    var defaultPitch: Int
    var defaultStyle: String
    var bookmarks: [BookBookmark]
    var bookProgressByChapter: [UUID: Double]
    var defaultSensitivity: Int

    private enum CodingKeys: String, CodingKey {
           case bookText, chapters, characters, scriptSegments, selectedChapterID, apiEndpoint, apiKey,
               books, currentBookTitle, currentBookID, currentBookProgress, readerFontSize, readerLineSpacing,
               readerTheme, defaultVoice, defaultRate, defaultPitch, defaultStyle, bookmarks, bookProgressByChapter, defaultSensitivity
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
        defaultVoice: String = "zh-CN-XiaoxiaoNeural",
        defaultRate: Int = 0,
        defaultPitch: Int = 0,
        defaultStyle: String = "neutral",
        bookmarks: [BookBookmark] = [],
        bookProgressByChapter: [UUID: Double] = [:],
        defaultSensitivity: Int = 50
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
        self.defaultVoice = defaultVoice
        self.defaultRate = defaultRate
        self.defaultPitch = defaultPitch
        self.defaultStyle = defaultStyle
        self.bookmarks = bookmarks
        self.bookProgressByChapter = bookProgressByChapter
        self.defaultSensitivity = defaultSensitivity
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
        defaultVoice = try container.decodeIfPresent(String.self, forKey: .defaultVoice) ?? "zh-CN-XiaoxiaoNeural"
        defaultRate = try container.decodeIfPresent(Int.self, forKey: .defaultRate) ?? 0
        defaultPitch = try container.decodeIfPresent(Int.self, forKey: .defaultPitch) ?? 0
        defaultStyle = try container.decodeIfPresent(String.self, forKey: .defaultStyle) ?? "neutral"
        bookmarks = try container.decodeIfPresent([BookBookmark].self, forKey: .bookmarks) ?? []
        bookProgressByChapter = try container.decodeIfPresent([UUID: Double].self, forKey: .bookProgressByChapter) ?? [:]
        defaultSensitivity = try container.decodeIfPresent(Int.self, forKey: .defaultSensitivity) ?? 50
    }
}
