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
    enum CodingKeys: String, CodingKey { case id, title, importedAt } // ⚠️ text 故意不编入 JSON（体积太大），但必须通过 Core Data 持久化！见 PersistenceController.saveBooks/fetchBooks
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
    var gender: CharacterGender
    var age: String
    var tone: String
    var voiceID: String
    var rate: Int
    var pitch: Int
    var style: String
    var sensitivity: Int
    var isNarrator: Bool = false
    var role: CharacterRole = .character
    var appearanceCount: Int = 0
    var bookID: UUID?
    var preferredRate: Double?
    var preferredPitch: Double?

    var info: String {
        [gender.rawValue, age, tone].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    init(id: UUID, name: String, aliases: [String] = [], gender: CharacterGender, age: String, tone: String, voiceID: String, rate: Int, pitch: Int, style: String, sensitivity: Int, isNarrator: Bool = false, role: CharacterRole = .character, appearanceCount: Int = 0, bookID: UUID? = nil, preferredRate: Double? = nil, preferredPitch: Double? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.gender = gender
        self.age = age
        self.tone = tone
        self.voiceID = voiceID
        self.rate = rate
        self.pitch = pitch
        self.style = style
        self.sensitivity = sensitivity
        self.isNarrator = isNarrator
        self.role = role
        self.appearanceCount = appearanceCount
        self.bookID = bookID
        self.preferredRate = preferredRate
        self.preferredPitch = preferredPitch
    }

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, gender, age, tone, voiceID, rate, pitch, style, sensitivity, isNarrator, role, appearanceCount, bookID, preferredRate, preferredPitch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        gender = try c.decodeIfPresent(CharacterGender.self, forKey: .gender) ?? .unknown
        age = try c.decode(String.self, forKey: .age)
        tone = try c.decode(String.self, forKey: .tone)
        voiceID = try c.decode(String.self, forKey: .voiceID)
        rate = try c.decode(Int.self, forKey: .rate)
        pitch = try c.decode(Int.self, forKey: .pitch)
        style = try c.decode(String.self, forKey: .style)
        sensitivity = try c.decode(Int.self, forKey: .sensitivity)
        isNarrator = try c.decodeIfPresent(Bool.self, forKey: .isNarrator) ?? false
        role = try c.decodeIfPresent(CharacterRole.self, forKey: .role) ?? .character
        appearanceCount = try c.decodeIfPresent(Int.self, forKey: .appearanceCount) ?? 0
        bookID = try c.decodeIfPresent(UUID.self, forKey: .bookID)
        preferredRate = try c.decodeIfPresent(Double.self, forKey: .preferredRate)
        preferredPitch = try c.decodeIfPresent(Double.self, forKey: .preferredPitch)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(gender, forKey: .gender)
        try c.encode(age, forKey: .age)
        try c.encode(tone, forKey: .tone)
        try c.encode(voiceID, forKey: .voiceID)
        try c.encode(rate, forKey: .rate)
        try c.encode(pitch, forKey: .pitch)
        try c.encode(style, forKey: .style)
        try c.encode(sensitivity, forKey: .sensitivity)
        try c.encode(isNarrator, forKey: .isNarrator)
        try c.encode(role, forKey: .role)
        try c.encode(appearanceCount, forKey: .appearanceCount)
        try c.encodeIfPresent(bookID, forKey: .bookID)
        try c.encodeIfPresent(preferredRate, forKey: .preferredRate)
        try c.encodeIfPresent(preferredPitch, forKey: .preferredPitch)
    }
}

enum CharacterGender: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .male: return "男性"
        case .female: return "女性"
        case .unknown: return "未知"
        }
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

struct VoiceItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let locale: String
    let gender: VoiceGender
    let styleList: [String]?

    var displayName: String {
        name.isEmpty ? id : name
    }

    static func defaultItems() -> [VoiceItem] { [] }
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
    var id: UUID
    let segment: ScriptSegment
    let audioURL: URL?
    let audioData: Data?  // optional in-memory audio; preferred over audioURL when present
    let chapterTitle: String
    let bookTitle: String
    let bookID: String
    let chapterIndex: Int
    let segmentIndex: Int
    let totalSegments: Int
    let paragraphIndex: Int?  // index into chapter paragraphs for highlight sync
    let sentenceIndex: Int?   // index within paragraph sentences
    let anchor: PlaybackAnchor?  // unified cross-stack sync anchor

    init(id: UUID = UUID(), segment: ScriptSegment, audioURL: URL? = nil, audioData: Data? = nil, chapterTitle: String, bookTitle: String, bookID: String, chapterIndex: Int, segmentIndex: Int, totalSegments: Int, paragraphIndex: Int? = nil, sentenceIndex: Int? = nil, anchor: PlaybackAnchor? = nil) {
        self.id = id
        self.segment = segment
        self.audioURL = audioURL
        self.audioData = audioData
        self.chapterTitle = chapterTitle
        self.bookTitle = bookTitle
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.segmentIndex = segmentIndex
        self.totalSegments = totalSegments
        self.paragraphIndex = paragraphIndex
        self.sentenceIndex = sentenceIndex
        self.anchor = anchor
    }

    enum CodingKeys: String, CodingKey {
        case id, segment, audioURL, chapterTitle, bookTitle, bookID, chapterIndex, segmentIndex, totalSegments, paragraphIndex, sentenceIndex, anchor
        // audioData intentionally excluded: never persist large audio buffers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        segment = try c.decode(ScriptSegment.self, forKey: .segment)
        audioURL = try c.decodeIfPresent(URL.self, forKey: .audioURL)
        audioData = nil
        chapterTitle = try c.decode(String.self, forKey: .chapterTitle)
        bookTitle = try c.decode(String.self, forKey: .bookTitle)
        bookID = try c.decode(String.self, forKey: .bookID)
        chapterIndex = try c.decode(Int.self, forKey: .chapterIndex)
        segmentIndex = try c.decode(Int.self, forKey: .segmentIndex)
        totalSegments = try c.decode(Int.self, forKey: .totalSegments)
        paragraphIndex = try c.decodeIfPresent(Int.self, forKey: .paragraphIndex)
        sentenceIndex = try c.decodeIfPresent(Int.self, forKey: .sentenceIndex)
        anchor = try c.decodeIfPresent(PlaybackAnchor.self, forKey: .anchor)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(segment, forKey: .segment)
        try c.encodeIfPresent(audioURL, forKey: .audioURL)
        try c.encode(chapterTitle, forKey: .chapterTitle)
        try c.encode(bookTitle, forKey: .bookTitle)
        try c.encode(bookID, forKey: .bookID)
        try c.encode(chapterIndex, forKey: .chapterIndex)
        try c.encode(segmentIndex, forKey: .segmentIndex)
        try c.encode(totalSegments, forKey: .totalSegments)
        try c.encodeIfPresent(paragraphIndex, forKey: .paragraphIndex)
        try c.encodeIfPresent(sentenceIndex, forKey: .sentenceIndex)
        try c.encodeIfPresent(anchor, forKey: .anchor)
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
    let emotionTag: String?  // Edge TTS 情绪标签: "angry"/"sad"/"happy"/nil
    let paragraphIndex: Int?  // index into chapter paragraphs for highlight sync

    init(id: UUID, characterName: String, voice: String, rate: Int, pitch: Int, style: String, text: String, emotionTag: String? = nil, paragraphIndex: Int? = nil) {
        self.id = id
        self.characterName = characterName
        self.voice = voice
        self.rate = rate
        self.pitch = pitch
        self.style = style
        self.text = text
        self.emotionTag = emotionTag
        self.paragraphIndex = paragraphIndex
    }
}

struct CharacterRecommendation: Identifiable, Hashable, Codable {
    let id: UUID
    var profile: CharacterProfile
    var count: Int
    var suggestedVoices: [VoiceItem]
}



struct ReaderState: Codable {
    var bookText: String = ""
    var chapters: [BookChapter]
    var characters: [CharacterProfile]
    var scriptSegments: [ScriptSegment]
    var selectedChapterID: UUID?
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
    var lastReadChapterIndexByBook: [UUID: Int]
    var defaultSensitivity: Int
    var playTimeoutSeconds: Double = 30.0
    var lastScannedBookText: String = ""
    var readerFontName: String = "PingFang SC"
    var readerParagraphSpacing: Double = 8
    var readerFirstLineIndent: Double = 0
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
        case characters, scriptSegments, selectedChapterID,
             books, currentBookTitle, currentBookID, currentBookProgress, readerFontSize, readerLineSpacing,
             readerTheme, defaultVoice, defaultRate, defaultPitch, defaultStyle, bookmarks, bookProgressByChapter, lastReadChapterIndexByBook, defaultSensitivity, playTimeoutSeconds, readerFontName, readerParagraphSpacing, readerFirstLineIndent, customBackgroundImage, showChapterTitle, showProgressBar, showPageNumber, showTime, showBattery, showBookCover, showReadingProgress, ttsQueue, ttsCurrentIndex, ttsIsPlaying, ttsChapterTitle, ttsSegmentTitle, recommendations, statusMessage, isBusy, currentPlayingLine, playProgress, isSpeaking, defaultMaleVoiceID, defaultFemaleVoiceID, defaultFallbackRateOffset, defaultFallbackPitchOffset, defaultFallbackStyle
    }

    init(
        bookText: String = "",
        chapters: [BookChapter] = [],
        characters: [CharacterProfile] = [],
        scriptSegments: [ScriptSegment] = [],
        selectedChapterID: UUID? = nil,
        books: [Book] = [],
        currentBookTitle: String = "",
        currentBookID: String = UUID().uuidString,
        currentBookProgress: Double = 0,
        readerFontSize: Double = 18,
        readerLineSpacing: Double = 8,
        readerTheme: ReaderTheme = .light,
        defaultVoice: String = "",
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
         readerFirstLineIndent: Double = 0,
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
        self.lastReadChapterIndexByBook = lastReadChapterIndexByBook
        self.defaultSensitivity = defaultSensitivity
        self.lastScannedBookText = lastScannedBookText
        self.playTimeoutSeconds = playTimeoutSeconds
        self.readerFontName = readerFontName
        self.readerParagraphSpacing = readerParagraphSpacing
        self.readerFirstLineIndent = readerFirstLineIndent
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
        books = try container.decodeIfPresent([Book].self, forKey: .books) ?? []
        currentBookTitle = try container.decodeIfPresent(String.self, forKey: .currentBookTitle) ?? ""
        currentBookID = try container.decodeIfPresent(String.self, forKey: .currentBookID) ?? UUID().uuidString
        currentBookProgress = try container.decodeIfPresent(Double.self, forKey: .currentBookProgress) ?? 0
        readerFontSize = try container.decodeIfPresent(Double.self, forKey: .readerFontSize) ?? 18
        readerLineSpacing = try container.decodeIfPresent(Double.self, forKey: .readerLineSpacing) ?? 8
        readerFirstLineIndent = try container.decodeIfPresent(Double.self, forKey: .readerFirstLineIndent) ?? 0
        readerParagraphSpacing = try container.decodeIfPresent(Double.self, forKey: .readerParagraphSpacing) ?? 8
        readerFontName = try container.decodeIfPresent(String.self, forKey: .readerFontName) ?? "PingFang SC"
        readerTheme = try container.decodeIfPresent(ReaderTheme.self, forKey: .readerTheme) ?? .light
        defaultVoice = try container.decodeIfPresent(String.self, forKey: .defaultVoice) ?? ""
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
