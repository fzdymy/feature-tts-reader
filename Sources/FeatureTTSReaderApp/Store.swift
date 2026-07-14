import Foundation
import Combine
import AVFoundation
import SwiftUI
import MediaPlayer
import NaturalLanguage
import os

@MainActor
struct ChapterNavigate: Equatable {
    let bookID: UUID
    let chapterIndex: Int
}

@MainActor
final class ReaderStore: NSObject, ObservableObject {
    @Published var navigationPath: NavigationPath = NavigationPath()
    @Published var bookText: String = ""
    @Published var chapters: [BookChapter] = []
    @Published var characters: [CharacterProfile] = []
    @Published var scriptSegments: [ScriptSegment] = []
    @Published var voices: [VoiceItem] = []
    @Published var recommendations: [CharacterRecommendation] = []
    @Published var selectedChapterID: UUID?
    @Published var externalChapterNavigate: ChapterNavigate?
    @Published var statusMessage: String = "请导入小说或粘贴文本。"
    @Published var isBusy: Bool = false
    @Published var importProgress: Double = 0.0
    @Published var currentPlayingLine: String = ""
    @Published var playProgress: Double = 0.0
    @Published var books: [Book] = []
    @Published var currentBookTitle: String = ""
    @Published var currentBookID: String = UUID().uuidString
    @Published var currentBookProgress: Double = 0.0
    @Published var bookIDForChapters: UUID?
    @Published var isSpeaking: Bool = false
    @Published var playTimeoutSeconds: Double = 30.0
    @Published var isLoadingAISegments: Bool = false

    // Enhanced TTS playback state
    @Published var ttsQueue: [TTSQueueItem] = []
    @Published var ttsCurrentIndex: Int = 0
    @Published var ttsCurrentTime: TimeInterval = 0
    @Published var ttsDuration: TimeInterval = 0
    @Published var ttsIsPlaying: Bool = false
    @Published var ttsChapterTitle: String = ""
    @Published var ttsSegmentTitle: String = ""

    @Published var ttsProgressMessage: String = ""
    @Published var currentParagraphIndex: Int?
    @Published var currentSentenceIndex: Int?
    @Published var currentSentenceText: String?

    @Published var activeServerTestResult: String = ""
    @Published var isTestingServer: Bool = false

    // AI Worker Configs (shared with TTSViewModel)
    @Published var aiWorkerConfigs: [AIWorkerConfig] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(aiWorkerConfigs) {
                UserDefaults.standard.set(data, forKey: "aiWorkerConfigs")
            }
        }
    }
    @Published var selectedWorkerID: UUID? {
        didSet {
            if let id = selectedWorkerID {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedAIWorkerID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedAIWorkerID")
            }
        }
    }

    private var playbackTask: Task<Void, Never>?
    @Published private(set) var isStateLoaded = false

    /// 测试 Edge TTS relay 服务是否可用
    func testActiveServer() async {
        guard !isTestingServer else { return }
        isTestingServer = true
        activeServerTestResult = "测试中..."
        let status = await EdgeTTSService.shared.healthCheck()
        activeServerTestResult = status
        isTestingServer = false
    }

    // Chapter parse cache keyed by book ID
    var bookChaptersCache: [UUID: [BookChapter]] = [:]
    private static let maxCachedBooks = 20

    private func setCachedChapters(_ chapters: [BookChapter], for bookID: UUID) {
        if bookChaptersCache.count >= Self.maxCachedBooks {
            bookChaptersCache.removeValue(forKey: bookChaptersCache.keys.first!)
        }
        bookChaptersCache[bookID] = chapters
    }

    func chaptersForBook(_ bookID: UUID, text: String) -> [BookChapter] {
        if let cached = bookChaptersCache[bookID] { return cached }
        guard !text.isEmpty else { return [] }
        let parsed = Self.extractChapters(from: text)
        if !parsed.isEmpty {
            setCachedChapters(parsed, for: bookID)
        }
        return parsed
    }

    func chaptersForBookCached(_ bookID: UUID) -> [BookChapter]? {
        bookChaptersCache[bookID]
    }

// TTS Synthesis Cache with size limit
    private var ttsCache: [String: URL] = [:]
    private let ttsCacheMaxSize = 200

    @Published var lastScannedBookText: String = ""
    @Published var readerFontSize: Double = 18
    @Published var readerLineSpacing: Double = 8
    @Published var readerParagraphSpacing: Double = 8
    @Published var readerFirstLineIndent: Double = 0
    @Published var readerTheme: ReaderTheme = .light
    @Published var readerFontName: String = "PingFang SC"
    @Published var customBackgroundImage: Data?
    @Published var showChapterTitle: Bool = true
    @Published var showProgressBar: Bool = true
    @Published var showPageNumber: Bool = true
    @Published var showTime: Bool = true
    @Published var showBattery: Bool = true
    @Published var showBookCover: Bool = true
    @Published var showReadingProgress: Bool = true
    @Published var immersiveMode: Bool = false
    @Published var enableDoubleTapToSpeak: Bool = true
    @Published var enableLongPressSelect: Bool = true
    @Published var keepScreenOn: Bool = false
    @Published var ttsTestAudioURL: URL? = nil
    @Published var edgeTTSLastHealth: String = ""
    @Published var bookmarks: [BookBookmark] = []
    @Published var bookProgressByChapter: [UUID: Double] = [:]
    @Published var lastReadChapterIndexByBook: [UUID: Int] = [:]
    @Published var defaultSensitivity: Int = 50
    @Published var defaultRate: Int = 0
    @Published var defaultPitch: Int = 0
    @Published var defaultStyle: String = "neutral"
    @Published var defaultSortOption: SortOption = .recent
    @Published var defaultMaleVoiceID: String = ""
    @Published var defaultFemaleVoiceID: String = ""
    @Published var defaultFallbackRateOffset: Int = 0
    @Published var defaultFallbackPitchOffset: Int = 0
    @Published var defaultFallbackStyle: String = "neutral"

    let audioController = AdvancedAudioPlaybackController()
    private let persistence = PersistenceController.shared
    private let speechSynthesizer = AVSpeechSynthesizer()
    private lazy var speechDelegate = SpeechSynthesizerDelegateProxy(owner: self)
    private var autoSaveTimer: Timer?
    private let aiParseCache = AIParseCache()
    private var workerRotator = WorkerRotator()

    private var defaultWorkerConfig: AIWorkerConfig? {
        if let id = selectedWorkerID, let config = aiWorkerConfigs.first(where: { $0.id == id }) {
            return config
        }
        return aiWorkerConfigs.first(where: { $0.isDefault }) ?? aiWorkerConfigs.first
    }

    override init() {
        super.init()
        speechSynthesizer.delegate = speechDelegate
        voices = []
        observeAudioController()
        audioController.restorePlaybackState()

        if let data = UserDefaults.standard.data(forKey: "lastReadChapterIndexByBook"),
           let map = try? JSONDecoder().decode([UUID: Int].self, from: data) {
            lastReadChapterIndexByBook = map
        }
        
        // Load AI Worker configs
        loadWorkerConfigs()
    }

    private func loadWorkerConfigs() {
        if let data = UserDefaults.standard.data(forKey: "aiWorkerConfigs"),
           let decoded = try? JSONDecoder().decode([AIWorkerConfig].self, from: data) {
            aiWorkerConfigs = decoded
            if let savedID = UserDefaults.standard.string(forKey: "selectedAIWorkerID"),
               let id = UUID(uuidString: savedID),
               aiWorkerConfigs.contains(where: { $0.id == id }) {
                selectedWorkerID = id
            } else if aiWorkerConfigs.first?.isDefault == true {
                selectedWorkerID = aiWorkerConfigs.first?.id
            }
        }
    }

    /// Write a crash marker to a file in Documents directory + UserDefaults.
    /// The last written marker before the crash pinpoints the culprit.
    nonisolated static func writeCrashMarker(_: String) {}

    // Remote commands handled by AdvancedAudioPlaybackController.setupRemoteCommands()

    private func observeAudioController() {
        // Observe audio controller state changes and sync with published properties
        audioController.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                Task { @MainActor [weak self] in
                    self?.ttsIsPlaying = isPlaying
                    self?.isSpeaking = isPlaying
                }
            }
            .store(in: &cancellables)

        audioController.$currentAnchor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] anchor in
                Task { @MainActor [weak self] in
                    self?.currentParagraphIndex = anchor?.paragraphIndex
                    self?.currentSentenceIndex = anchor?.sentenceIndex
                    self?.ttsCurrentIndex = anchor.map { $0.paragraphIndex } ?? 0
                    self?.ttsSegmentTitle = anchor.map { "段 \($0.paragraphIndex):句 \($0.sentenceIndex)" } ?? ""
                }
            }
            .store(in: &cancellables)

        audioController.$queueCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.ttsIsPlaying = self?.audioController.isPlaying ?? false
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
    private var playbackContinuationCancellable: AnyCancellable?

    func loadSettings() {
    }

    func saveSettings() {
        saveState()
    }

    func restartAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        let interval = UserDefaults.standard.object(forKey: "autoSaveInterval") as? Double ?? 30
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: max(interval, 10), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveState()
            }
        }
    }

    private func startAutoSaveTimer() {
        restartAutoSaveTimer()
    }

    func loadStateAsync() async {
        guard !isStateLoaded else { return }
        let url = stateFileURL()
        let decoded: ReaderState? = await Task.detached {
            guard let data = try? Data(contentsOf: url),
                  let state = try? JSONDecoder().decode(ReaderState.self, from: data) else { return nil }
            return state
        }.value
        let loadedTexts: [(UUID, String)]? = await Task.detached {
            guard let state = decoded else { return nil }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let dir = docs.appendingPathComponent("book_texts", isDirectory: true)
            var results: [(UUID, String)] = []
            results.reserveCapacity(state.books.count)
            for book in state.books {
                let url = dir.appendingPathComponent("\(book.id.uuidString).txt")
                if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                    results.append((book.id, text))
                }
            }
            return results
        }.value
        await MainActor.run {
            guard let state = decoded else {
                loadPersistentLibrary()
                var changed = false
                for i in books.indices where books[i].text.isEmpty {
                    if let text = loadBookTextFromFile(bookID: books[i].id), !text.isEmpty {
                        books[i].text = text
                        changed = true
                    }
                }
                if changed {
                    let snapshot = books
                    books = snapshot
                }
                if bookText.isEmpty, let id = UUID(uuidString: currentBookID) {
                    bookText = loadBookTextFromFile(bookID: id) ?? ""
                    lastScannedBookText = bookText
                }
                if books.contains(where: { !$0.text.isEmpty }) {
                    persistLibrary()
                }
                isStateLoaded = true
                startAutoSaveTimer()
                return
            }
            var mergedBooks = state.books
            let persistedBooks = persistence.fetchBooks()
            if !persistedBooks.isEmpty {
                for persistedBook in persistedBooks where !mergedBooks.contains(where: { $0.id == persistedBook.id }) {
                    mergedBooks.append(persistedBook)
                }
                for i in mergedBooks.indices where mergedBooks[i].text.isEmpty {
                    if let persisted = persistedBooks.first(where: { $0.id == mergedBooks[i].id }), !persisted.text.isEmpty {
                        mergedBooks[i].text = persisted.text
                    }
                }
                let hadNewBooks = mergedBooks.count != state.books.count
                books = mergedBooks
                if hadNewBooks {
                    persistLibrary()
                }
            } else {
                books = state.books
            }
            chapters = state.chapters
            if let bid = UUID(uuidString: state.currentBookID) {
                bookChaptersCache[bid] = state.chapters
            }
            bookIDForChapters = UUID(uuidString: state.currentBookID)
            selectedChapterID = state.selectedChapterID
            bookProgressByChapter = state.bookProgressByChapter
            readerFontSize = state.readerFontSize
            readerLineSpacing = state.readerLineSpacing
            readerParagraphSpacing = state.readerParagraphSpacing
            readerFirstLineIndent = state.readerFirstLineIndent
            readerTheme = state.readerTheme
            readerFontName = state.readerFontName
            customBackgroundImage = state.customBackgroundImage
            showChapterTitle = state.showChapterTitle
            showProgressBar = state.showProgressBar
            showPageNumber = state.showPageNumber
            showTime = state.showTime
            showBattery = state.showBattery
            showBookCover = state.showBookCover
            showReadingProgress = state.showReadingProgress
            bookmarks = state.bookmarks
            currentBookTitle = state.currentBookTitle
            currentBookID = state.currentBookID
            currentBookProgress = state.currentBookProgress
            defaultSensitivity = state.defaultSensitivity
            playTimeoutSeconds = state.playTimeoutSeconds
            characters = state.characters
            scriptSegments = state.scriptSegments
            ttsQueue = state.ttsQueue ?? []
            ttsCurrentIndex = state.ttsCurrentIndex ?? 0
            ttsIsPlaying = state.ttsIsPlaying ?? false
            ttsChapterTitle = state.ttsChapterTitle ?? ""
            ttsSegmentTitle = state.ttsSegmentTitle ?? ""
            recommendations = state.recommendations ?? []
            statusMessage = state.statusMessage
            isBusy = state.isBusy
            currentPlayingLine = state.currentPlayingLine
            playProgress = state.playProgress
            isSpeaking = state.isSpeaking

            if let udData = UserDefaults.standard.data(forKey: "lastReadChapterIndexByBook"),
               let udMap = try? JSONDecoder().decode([UUID: Int].self, from: udData) {
                self.lastReadChapterIndexByBook = udMap
            } else if !state.lastReadChapterIndexByBook.isEmpty {
                self.lastReadChapterIndexByBook = state.lastReadChapterIndexByBook
            }

            if let loadedTexts {
                var changed = false
                for (id, text) in loadedTexts {
                    if let idx = books.firstIndex(where: { $0.id == id }) {
                        if books[idx].text != text {
                            books[idx].text = text
                            changed = true
                        }
                    }
                    if currentBookID == id.uuidString {
                        bookText = text
                        lastScannedBookText = text
                    }
                }
                if changed {
                    let snapshot = books
                    books = snapshot
                }
            }
            var changed = false
            for i in books.indices where books[i].text.isEmpty {
                if let text = loadBookTextFromFile(bookID: books[i].id), !text.isEmpty {
                    books[i].text = text
                    changed = true
                }
            }
            if changed {
                let snapshot = books
                books = snapshot
            }
            if bookText.isEmpty, let id = UUID(uuidString: currentBookID) {
                if let idx = books.firstIndex(where: { $0.id == id }), !books[idx].text.isEmpty {
                    bookText = books[idx].text
                } else {
                    bookText = loadBookTextFromFile(bookID: id) ?? ""
                }
                lastScannedBookText = bookText
            }
            // 持久化任何从文件备份加载的文本到 Core Data，确保下次启动 Core Data 中有文本
            if books.contains(where: { !$0.text.isEmpty }) {
                persistLibrary()
            }
            isStateLoaded = true
            startAutoSaveTimer()
        }
    }

    func loadState() {
        Task { await loadStateAsync() }
    }

    func restoreState(_ state: ReaderState) {
        saveAllTextsToFiles()
        chapters = state.chapters
        if let bid = UUID(uuidString: state.currentBookID) {
            setCachedChapters(state.chapters, for: bid)
        }
        characters = state.characters
        scriptSegments = state.scriptSegments
        selectedChapterID = state.selectedChapterID
        books = state.books
        currentBookTitle = state.currentBookTitle
        currentBookID = state.currentBookID
        bookIDForChapters = UUID(uuidString: state.currentBookID)
        currentBookProgress = state.currentBookProgress
        readerFontSize = state.readerFontSize
        readerLineSpacing = state.readerLineSpacing
        readerParagraphSpacing = state.readerParagraphSpacing
        readerFirstLineIndent = state.readerFirstLineIndent
        readerTheme = state.readerTheme
        readerFontName = state.readerFontName
        customBackgroundImage = state.customBackgroundImage
        showChapterTitle = state.showChapterTitle
        showProgressBar = state.showProgressBar
        showPageNumber = state.showPageNumber
        showTime = state.showTime
        showBattery = state.showBattery
        showBookCover = state.showBookCover
        showReadingProgress = state.showReadingProgress
        bookmarks = state.bookmarks
        bookProgressByChapter = state.bookProgressByChapter
        lastReadChapterIndexByBook = state.lastReadChapterIndexByBook
        defaultSensitivity = state.defaultSensitivity
        playTimeoutSeconds = state.playTimeoutSeconds
        ttsQueue = state.ttsQueue ?? []
        ttsCurrentIndex = state.ttsCurrentIndex ?? 0
        ttsIsPlaying = state.ttsIsPlaying ?? false
        ttsChapterTitle = state.ttsChapterTitle ?? ""
        ttsSegmentTitle = state.ttsSegmentTitle ?? ""
        recommendations = state.recommendations ?? []
        defaultMaleVoiceID = state.defaultMaleVoiceID
        defaultFemaleVoiceID = state.defaultFemaleVoiceID
        defaultFallbackRateOffset = state.defaultFallbackRateOffset
        defaultFallbackPitchOffset = state.defaultFallbackPitchOffset
        defaultFallbackStyle = state.defaultFallbackStyle
        loadAllTextsFromFiles()
        statusMessage = "数据已恢复。"
        saveState()
    }

    // MARK: - File-based text storage (avoids encoding 10-40MB into JSON)

    private func textFileURL(forBookID id: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("book_texts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.uuidString).txt")
    }

    private func saveBookTextToFile(bookID: UUID, text: String) {
        guard !text.isEmpty else { return }
        let url = textFileURL(forBookID: bookID)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadBookTextFromFile(bookID: UUID) -> String? {
        let url = textFileURL(forBookID: bookID)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func saveAllTextsToFiles() {
        if !bookText.isEmpty, let id = UUID(uuidString: currentBookID) {
            saveBookTextToFile(bookID: id, text: bookText)
        }
        for book in books {
            if !book.text.isEmpty {
                saveBookTextToFile(bookID: book.id, text: book.text)
            }
        }
    }

    private func loadAllTextsFromFiles() {
        if let id = UUID(uuidString: currentBookID) {
            bookText = loadBookTextFromFile(bookID: id) ?? ""
            lastScannedBookText = bookText
        }
        var changed = false
        for i in books.indices {
            if let text = loadBookTextFromFile(bookID: books[i].id), books[i].text != text {
                books[i].text = text
                changed = true
            }
        }
        if changed {
            let snapshot = books
            books = snapshot
        }
    }

    func saveState() {
        saveAllTextsToFiles()
        let state = ReaderState(
            bookText: "",
            chapters: [],
            characters: characters,
            scriptSegments: scriptSegments,
            selectedChapterID: selectedChapterID,
            books: books,
            currentBookTitle: currentBookTitle,
            currentBookID: currentBookID,
            currentBookProgress: currentBookProgress,
            readerFontSize: readerFontSize,
            readerLineSpacing: readerLineSpacing,
            readerTheme: readerTheme,
            defaultVoice: characters.first?.voice ?? "",
            defaultRate: characters.first?.rate ?? 0,
            defaultPitch: characters.first?.pitch ?? 0,
            defaultStyle: characters.first?.style ?? "neutral",
            bookmarks: bookmarks,
            bookProgressByChapter: bookProgressByChapter,
            lastReadChapterIndexByBook: lastReadChapterIndexByBook,
            defaultSensitivity: defaultSensitivity,
            lastScannedBookText: "",
            playTimeoutSeconds: playTimeoutSeconds,
            readerFontName: readerFontName,
            readerParagraphSpacing: readerParagraphSpacing,
            readerFirstLineIndent: readerFirstLineIndent,
            customBackgroundImage: customBackgroundImage,
            showChapterTitle: showChapterTitle,
            showProgressBar: showProgressBar,
            showPageNumber: showPageNumber,
            showTime: showTime,
            showBattery: showBattery,
            showBookCover: showBookCover,
            showReadingProgress: showReadingProgress,
            ttsQueue: ttsQueue,
            ttsCurrentIndex: ttsCurrentIndex,
            ttsIsPlaying: ttsIsPlaying,
            ttsChapterTitle: ttsChapterTitle,
            ttsSegmentTitle: ttsSegmentTitle,
            recommendations: recommendations,
            statusMessage: statusMessage,
            isBusy: isBusy,
            currentPlayingLine: currentPlayingLine,
            playProgress: playProgress,
            isSpeaking: isSpeaking,
            defaultMaleVoiceID: defaultMaleVoiceID,
            defaultFemaleVoiceID: defaultFemaleVoiceID,
            defaultFallbackRateOffset: defaultFallbackRateOffset,
            defaultFallbackPitchOffset: defaultFallbackPitchOffset,
            defaultFallbackStyle: defaultFallbackStyle
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        let targetURL = stateFileURL()
        do {
            try data.write(to: targetURL, options: .atomic)
        } catch {
            Logger.log(error: error, message: "saveState")
        }
        persistLibrary()
    }

    private func persistLibrary() {
        persistence.saveBooks(books)
        persistence.saveBookmarks(bookmarks)
        persistence.saveChapterProgressMap(bookProgressByChapter)
        persistence.saveLastReadChapterIndexMap(lastReadChapterIndexByBook)
    }

    private func loadPersistentLibrary() {
        var recoveredBooks = false
        let persistedBooks = persistence.fetchBooks()
        if !persistedBooks.isEmpty {
            books = persistedBooks
            loadAllTextsFromFiles()
        } else {
            let orphans = recoverOrphanTextFiles()
            if !orphans.isEmpty {
                books = orphans
                recoveredBooks = true
                persistence.saveBooks(orphans)
                persistence.saveBookmarks(bookmarks)
                persistence.saveChapterProgressMap(bookProgressByChapter)
                persistence.saveLastReadChapterIndexMap(lastReadChapterIndexByBook)
            }
        }
        let persistedBookmarks = persistence.fetchBookmarks()
        if !persistedBookmarks.isEmpty {
            bookmarks = persistedBookmarks
        }
        let persistedProgress = persistence.fetchChapterProgress()
        if !persistedProgress.isEmpty {
            bookProgressByChapter = persistedProgress
        }
        let persistedLastRead = persistence.fetchLastReadChapterIndexByBook()
        if !persistedLastRead.isEmpty {
            lastReadChapterIndexByBook = persistedLastRead
        }
        if recoveredBooks, let first = books.first {
            bookText = loadBookTextFromFile(bookID: first.id) ?? ""
            lastScannedBookText = bookText
            currentBookTitle = first.title
            currentBookID = first.id.uuidString
            statusMessage = "已从文件恢复 \(books.count) 本导入的书籍"
        }
    }

    /// Scans the book_texts directory for orphan .txt files not referenced by any CoreData record,
    /// and creates Book entries from their filenames (UUID-based).
    private func recoverOrphanTextFiles() -> [Book] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("book_texts", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) else {
            return []
        }
        var recovered: [Book] = []
        for url in files {
            guard url.pathExtension == "txt" else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            guard let bookID = UUID(uuidString: name) else { continue }
            if books.contains(where: { $0.id == bookID }) { continue }
            var title = "恢复的书籍"
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if let firstLine = lines.first {
                    title = String(firstLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
                }
            }
            let book = Book(id: bookID, title: title, text: "", importedAt: Date())
            recovered.append(book)
        }
        return recovered
    }

    private func ensureVoiceOptionsLoaded() {
        if voices.isEmpty {
            Task { await refreshVoices() }
        }
    }

    func testTTSSynthesize(serverID: UUID? = nil, text: String = "这是个多角色语音阅读器！", voice: String? = nil, style: String = "", rate: Double = 0, pitch: Double = 0) async -> String {
        do {
            let audioData = try await EdgeTTSService.shared.synthesize(text: text, voice: voice, rate: rate, pitch: pitch, style: style, serverID: serverID)
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
            let audioURL = cachesDir.appendingPathComponent("edge-test-\(UUID().uuidString).\(ext)")
            try audioData.write(to: audioURL, options: .atomic)
            await MainActor.run { ttsTestAudioURL = audioURL }
            return "合成成功！文件大小：\(String(format: "%.1f", Double(audioData.count) / 1024)) KB"
        } catch {
            return "合成测试失败：\(error.localizedDescription)"
        }
    }

    func addBookmark(note: String = "") {
          guard let chapterID = selectedChapterID,
              let chapter = chapters.first(where: { $0.id == chapterID }) else { return }
          let percent = bookProgressByChapter[chapterID] ?? currentBookProgress
          let entry = BookBookmark(id: UUID(), chapterID: chapterID, chapterTitle: chapter.title, percent: percent, note: note, createdAt: Date())
        bookmarks.append(entry)
        persistence.saveBookmarks(bookmarks)
        statusMessage = "已保存书签：\(chapter.title) \(Int(percent * 100))%"
        saveState()
    }

    func removeBookmark(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveState()
    }

    func setChapterProgress(_ chapterID: UUID, percent: Double) {
        let capped = min(max(percent, 0), 1)
        bookProgressByChapter[chapterID] = capped
        currentBookProgress = capped
        persistence.saveChapterProgressMap(bookProgressByChapter)
        saveState()
    }

    func getChapterProgress(_ chapterID: UUID) -> Double {
        return bookProgressByChapter[chapterID] ?? 0
    }

    func rememberLastReadChapter(bookID: UUID, chapterIndex: Int) {
        guard lastReadChapterIndexByBook[bookID] != chapterIndex else { return }
        lastReadChapterIndexByBook[bookID] = chapterIndex
        UserDefaults.standard.set(chapterIndex, forKey: "lr_\(bookID.uuidString)")
        if let data = try? JSONEncoder().encode(lastReadChapterIndexByBook) {
            UserDefaults.standard.set(data, forKey: "lastReadChapterIndexByBook")
        }
    }

    func lastReadChapterIndex(for bookID: UUID) -> Int? {
        return lastReadChapterIndexByBook[bookID]
    }

    func removeBook(at index: Int) {
        guard index >= 0, index < books.count else { return }
        let book = books[index]
        books.remove(at: index)
        // Clean up text file
        let url = textFileURL(forBookID: book.id)
        try? FileManager.default.removeItem(at: url)
        // Clean up position file
        let docs = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let posURL = docs.appendingPathComponent("book_position/\(book.id.uuidString).txt")
        try? FileManager.default.removeItem(at: posURL)
        saveState()
    }

    func clearLibrary() {
        books.removeAll()
        bookmarks.removeAll()
        bookProgressByChapter.removeAll()
        lastReadChapterIndexByBook.removeAll()
        bookText = ""
        chapters.removeAll()
        characters.removeAll()
        scriptSegments.removeAll()
        recommendations.removeAll()
        selectedChapterID = nil
        currentBookTitle = ""
        currentBookID = UUID().uuidString
        currentBookProgress = 0
        lastScannedBookText = ""
        statusMessage = "已清空书架。"
        // Clean up all book text files
        let docs = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let bookTextsDir = docs.appendingPathComponent("book_texts", isDirectory: true)
        try? FileManager.default.removeItem(at: bookTextsDir)
        let bookPosDir = docs.appendingPathComponent("book_position", isDirectory: true)
        try? FileManager.default.removeItem(at: bookPosDir)
        persistence.clearLibrary()
        saveState()
    }

    func importFile(at url: URL) async {
        // attempt to read with various encodings: UTF-8, UTF-16, UTF-16 variants
        let possibleEncodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .unicode,
            .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
            .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue))),
        ]
        var content: String? = nil
        // read file with progress reporting on a background thread
        await MainActor.run {
            importProgress = 0.0
            isBusy = true
            statusMessage = "正在导入文件..."
        }
        var fileData: Data? = nil
        do {
            fileData = try await readDataWithProgress(url) { progress in
                Task { @MainActor in
                    self.importProgress = progress
                }
            }
        } catch {
            fileData = nil
        }

        for enc in possibleEncodings {
            guard let data = fileData, let s = String(data: data, encoding: enc) else {
                continue
            }
            content = s
            break
        }
        guard var text = content else {
            statusMessage = "导入失败：无法识别文件编码。"
            await MainActor.run { isBusy = false }
            return
        }
        text = TextNormalizer.normalize(text)
        let title = url.deletingPathExtension().lastPathComponent
        let bookID = UUID()
        saveBookTextToFile(bookID: bookID, text: text)
        // Remove inbox copy to prevent accumulation
        DispatchQueue.global(qos: .utility).async {
            if url.path.contains("Inbox") { try? FileManager.default.removeItem(at: url) }
        }
        let book = Book(id: bookID, title: title, text: text, importedAt: Date())
        await MainActor.run { [book] in
            books.append(book)
            persistence.saveBooks(books)
            bookText = text
            currentBookTitle = title
            currentBookID = book.id.uuidString
            characters = []
            scriptSegments = []
            recommendations = []
            lastScannedBookText = ""
        }
        let extracted = await Task.detached { [text] in
            ReaderStore.extractChapters(from: text)
        }.value
        await MainActor.run {
            chapters = extracted
            if let currentBookID = UUID(uuidString: currentBookID) {
                setCachedChapters(extracted, for: currentBookID)
            }
            bookIDForChapters = UUID(uuidString: currentBookID)
            selectedChapterID = chapters.first?.id
            statusMessage = "已导入：\(title)，共 \(chapters.count) 章。"
            saveState()
            importProgress = 0.0
            isBusy = false
        }
    }

    private func stateFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("tts_reader_state.json")
    }

    static func debugLog(_ message: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = docs.appendingPathComponent("debug_log.txt")
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "\(timestamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func saveLastChapterIndex(_ index: Int, for bookID: UUID) {
        let key = bookID.uuidString
        Self.debugLog("[POS-SAVE] bookID=\(key) index=\(index)")
        UserDefaults.standard.set(index, forKey: "rp_\(key)")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let newDir = docs.appendingPathComponent("book_position", isDirectory: true)
        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        let newUrl = newDir.appendingPathComponent("\(key).txt")
        try? "\(index)".write(to: newUrl, atomically: true, encoding: .utf8)
        let legacyUrl = docs.appendingPathComponent("lastChapter_\(key).txt")
        try? "\(index)".write(to: legacyUrl, atomically: true, encoding: .utf8)
        UserDefaults.standard.set(index, forKey: "lastChapter_\(key)")
    }

    static func loadLastChapterIndex(for bookID: UUID) -> Int {
        let key = bookID.uuidString
        if let val = UserDefaults.standard.object(forKey: "rp_\(key)") as? Int {
            Self.debugLog("[POS-LOAD] bookID=\(key) found(rp)=\(val)")
            return val
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let newDir = docs.appendingPathComponent("book_position", isDirectory: true)
        let newUrl = newDir.appendingPathComponent("\(key).txt")
        if let data = try? String(contentsOf: newUrl, encoding: .utf8),
           let index = Int(data.trimmingCharacters(in: .whitespacesAndNewlines)) {
            Self.debugLog("[POS-LOAD] bookID=\(key) found(file)=\(index)")
            saveLastChapterIndex(index, for: bookID)
            return index
        }
        let legacyUrl = docs.appendingPathComponent("lastChapter_\(key).txt")
        if let data = try? String(contentsOf: legacyUrl, encoding: .utf8),
           let index = Int(data.trimmingCharacters(in: .whitespacesAndNewlines)) {
            Self.debugLog("[POS-LOAD] bookID=\(key) found(legacy)=\(index)")
            saveLastChapterIndex(index, for: bookID)
            return index
        }
        if let udIndex = UserDefaults.standard.object(forKey: "lastChapter_\(key)") as? Int {
            Self.debugLog("[POS-LOAD] bookID=\(key) found(ud)=\(udIndex)")
            saveLastChapterIndex(udIndex, for: bookID)
            return udIndex
        }
        if let lrIndex = UserDefaults.standard.object(forKey: "lr_\(key)") as? Int {
            Self.debugLog("[POS-LOAD] bookID=\(key) found(lr)=\(lrIndex)")
            saveLastChapterIndex(lrIndex, for: bookID)
            return lrIndex
        }
        Self.debugLog("[POS-LOAD] bookID=\(key) NOT FOUND → 0")
        return 0
    }

    private func readDataFromURL(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let d = try Data(contentsOf: url)
                    cont.resume(returning: d)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func readDataWithProgress(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fm = FileManager.default
                    let attrs = try? fm.attributesOfItem(atPath: url.path)
                    let fileSize = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                    let fh = try FileHandle(forReadingFrom: url)
                    var collected = Data()
                    let chunkSize = 64 * 1024
                    while true {
                        let chunk: Data
                        do {
                            chunk = try fh.read(upToCount: chunkSize) ?? Data()
                        } catch {
                            try? fh.close()
                            cont.resume(throwing: error)
                            return
                        }
                        if chunk.count > 0 {
                            collected.append(chunk)
                            if fileSize > 0 {
                                let p = Double(collected.count) / Double(max(1, fileSize))
                                let clampedP = min(max(p, 0), 1)
                                progress(clampedP)
                            }
                        }
                        if chunk.isEmpty {
                            try? fh.close()
                            cont.resume(returning: collected)
                            return
                        }
                    }
                } catch {
                    do {
                        let d = try Data(contentsOf: url)
                        progress(1.0)
                        cont.resume(returning: d)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    func importText(_ text: String) async {
        let trimmedText = TextNormalizer.normalize(text)
        guard !trimmedText.isEmpty else {
            await MainActor.run { statusMessage = "导入文本为空。" }
            return
        }

        // perform chapter extraction off-main-thread
        let extracted = await Task.detached { [trimmedText] in
            ReaderStore.extractChapters(from: trimmedText)
        }.value

        await MainActor.run {
            bookText = trimmedText
            currentBookTitle = "未命名文本"
            let bookID = UUID()
            currentBookID = bookID.uuidString
            chapters = extracted
            setCachedChapters(extracted, for: bookID)
            bookIDForChapters = bookID
            selectedChapterID = chapters.first?.id
            characters = []
            scriptSegments = []
            recommendations = []
            lastScannedBookText = ""
            statusMessage = "已导入文本，发现 \(chapters.count) 个章节。"

            saveBookTextToFile(bookID: bookID, text: bookText)
            let book = Book(id: bookID, title: currentBookTitle, text: bookText, importedAt: Date())
            books.append(book)
            saveState()
        }
    }

    func reformatBookText(bookID: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        let text = loadBookTextFromFile(bookID: bookID) ?? books[idx].text
        let normalized = TextNormalizer.normalize(text)
        saveBookTextToFile(bookID: bookID, text: normalized)
        books[idx].text = normalized
        if bookID.uuidString == currentBookID {
            bookText = normalized
            lastScannedBookText = normalized
            chapters = []
            scriptSegments = []
            recommendations = []
        }
        bookChaptersCache.removeValue(forKey: bookID)
        let oldLen = text.count.formatted()
        let newLen = normalized.count.formatted()
        saveState()
        statusMessage = "格式化完成：\(oldLen) → \(newLen) 字符"
    }

    func startParseChapters() {
        // synchronous wrapper kept for compatibility; prefer async version
        Task { await parseChaptersAsync() }
    }

    func parseChaptersAsync() async {
        let text = bookText
        await MainActor.run { isBusy = true; importProgress = 0.0; statusMessage = "正在扫描章节..." }
        let extracted = await Task.detached { [text] in
            // reuse existing extraction logic
            ReaderStore.extractChapters(from: text)
        }.value
        await MainActor.run {
            chapters = extracted
            if let currentBookID = UUID(uuidString: currentBookID) {
                setCachedChapters(extracted, for: currentBookID)
            }
            bookIDForChapters = UUID(uuidString: currentBookID)
            selectedChapterID = chapters.first?.id
            statusMessage = "已扫描 \(chapters.count) 个章节。"
            if currentBookTitle.isEmpty {
                currentBookTitle = "未命名文本"
            }
            importProgress = 0.0
            isBusy = false
            saveState()
        }
    }

    func scanCharacters(chapterText: String? = nil) async {
        ensureVoiceOptionsLoaded()
        let targetText = chapterText ?? bookText

        // Use AI Worker instead of local scanner
        guard let workerConfig = getDefaultWorkerConfig() else {
            await MainActor.run {
                statusMessage = "请先在设置中配置 AI Worker"
            }
            return
        }

        await MainActor.run { statusMessage = "正在通过 AI Worker 识别角色..." }

        do {
            let segments = try await AIWorkerService.shared.processChapter(
                text: targetText,
                config: workerConfig,
                progress: { progress, message in
                    await MainActor.run { self.statusMessage = message }
                }
            )

            // Convert AISegment to CharacterProfile
            let speakers = Array(Set(segments.map { $0.speaker })).sorted()
            var profiles: [CharacterProfile] = []
            for speaker in speakers {
                let speakerSegments = segments.filter { $0.speaker == speaker }
                let isNarrator = speaker == "旁白"
                let gender = isNarrator ? "Unknown" : (speaker.contains("女") || speaker.contains("小姐") || speaker.contains("姑娘") || speaker.contains("她") ? "Female" : "Male")
                let tone = isNarrator ? "平稳" : speakerSegments.first?.emotion.rawValue ?? "平稳"
                let voice = "" // Will be auto-assigned

                let profile = CharacterProfile(
                    id: UUID(),
                    name: speaker,
                    aliases: [],
                    gender: gender,
                    age: isNarrator ? "未知" : "青年",
                    tone: tone,
                    voice: voice,
                    rate: 0,
                    pitch: 0,
                    style: "neutral",
                    sensitivity: defaultSensitivity,
                    isNarrator: isNarrator,
                    role: isNarrator ? .narrator : .character,
                    bookID: UUID(uuidString: currentBookID)
                )
                profiles.append(profile)
            }

            await MainActor.run {
                // Assign voices
                var final = profiles.map { profile in
                    var p = profile
                    if p.voice.isEmpty {
                        p.voice = defaultVoice(for: p.gender, tone: p.tone, name: p.name, voices: voices)
                    }
                    return p
                }

                if final.isEmpty {
                    final = [CharacterProfile(id: UUID(), name: "叙述者", gender: "未知", age: "未知", tone: "中性", voice: defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: voices), rate: 0, pitch: 0, style: "neutral", sensitivity: defaultSensitivity)]
                    statusMessage = "未识别到明确人物，已创建默认叙述者。"
                } else {
                    statusMessage = "已识别 \(final.count) 个角色。"
                }
                characters.removeAll { $0.bookID == UUID(uuidString: currentBookID) || $0.bookID == nil }
                characters.append(contentsOf: final)
                lastScannedBookText = targetText
                updateRecommendations(from: targetText)
                saveState()
            }
        } catch {
            await MainActor.run {
                statusMessage = "识别失败: \(error.localizedDescription)"
            }
        }
    }

    private func getDefaultWorkerConfig() -> AIWorkerConfig? {
        if let data = UserDefaults.standard.data(forKey: "aiWorkerConfigs"),
           let decoded = try? JSONDecoder().decode([AIWorkerConfig].self, from: data) {
            if let savedID = UserDefaults.standard.string(forKey: "selectedAIWorkerID"),
               let id = UUID(uuidString: savedID),
               let config = decoded.first(where: { $0.id == id }) {
                return config
            }
            return decoded.first { $0.isDefault } ?? decoded.first
        }
        return nil
    }

    func createScriptSegmentsAsync(from text: String) async -> [ScriptSegment] {
        let currentCharacters = characters
        let currentVoices = voices
        let currentSensitivity = defaultSensitivity
        let currentMaleVoice = defaultMaleVoiceID
        let currentFemaleVoice = defaultFemaleVoiceID
        let currentFallbackRate = defaultFallbackRateOffset
        let currentFallbackPitch = defaultFallbackPitchOffset
        let currentFallbackStyle = defaultFallbackStyle
        return await Task.detached { [weak self, text, currentCharacters, currentVoices, currentSensitivity, currentMaleVoice, currentFemaleVoice, currentFallbackRate, currentFallbackPitch, currentFallbackStyle] in
            return self?.createScriptSegments(from: text, characters: currentCharacters, defaultSensitivity: currentSensitivity, voices: currentVoices, defaultMaleVoiceID: currentMaleVoice, defaultFemaleVoiceID: currentFemaleVoice, defaultFallbackRateOffset: currentFallbackRate, defaultFallbackPitchOffset: currentFallbackPitch, defaultFallbackStyle: currentFallbackStyle) ?? []
        }.value
    }

    func buildScript(for wholeBook: Bool) async {
        ensureVoiceOptionsLoaded()
        if characters.isEmpty || lastScannedBookText != bookText {
            await scanCharacters()
        }

        let targetText: String
        if wholeBook {
            targetText = bookText
        } else if let bookID = UUID(uuidString: currentBookID),
                  let chapter = (bookChaptersCache[bookID] ?? chapters).first(where: { $0.id == selectedChapterID }) {
            targetText = chapter.text
        } else {
            targetText = bookText
        }

        let segments = await createScriptSegmentsAsync(from: targetText)
        await MainActor.run {
            scriptSegments = segments
            if scriptSegments.isEmpty {
                statusMessage = "生成脚本失败，请先导入文本并扫描角色。"
            } else {
                statusMessage = "已生成 \(scriptSegments.count) 个朗读段落。"
            }
            updateRecommendations(from: targetText)
            saveState()
        }
    }

    func refreshVoices() async {
        voices = []
    }

    func previewVoice(for profile: CharacterProfile) async {
        isBusy = true
        let text = "你好，我是 \(profile.name)，这是我的声音示例。"
        do {
            let audioData = try await EdgeTTSService.shared.synthesize(text: text, voice: profile.voice.isEmpty ? nil : profile.voice)
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
            let audioURL = cachesDir.appendingPathComponent("preview-\(UUID().uuidString).\(ext)")
            try audioData.write(to: audioURL, options: .atomic)
            await audioController.playFilesAndWait([audioURL])
            statusMessage = "正在播放 \(profile.name) 语音示例。"
        } catch {
            statusMessage = "语音试听失败：\(error.localizedDescription)"
        }
        isBusy = false
    }

    func applyRecommendationsToUnmapped() {
        for rec in recommendations {
            if let idx = characters.firstIndex(where: { $0.id == rec.profile.id }) {
                if characters[idx].voice.isEmpty {
                    characters[idx].voice = ""
                }
            }
        }
        statusMessage = "已为未映射角色应用推荐。"
        saveState()
    }

    func autoApplyRecommendedToAll() {
        statusMessage = "Edge TTS 使用 relay 服务进行实时合成。"
        saveState()
    }

    func addCharacter(name: String, gender: String = "未知", age: String = "未知", tone: String = "平稳", bookID: UUID? = nil) {
        let newCharacter = CharacterProfile(
            id: UUID(),
            name: name,
            aliases: [],
            gender: gender,
            age: age,
            tone: tone,
            voice: defaultVoice(for: gender, tone: tone, voices: voices),
            rate: 0,
            pitch: 0,
            style: "neutral",
            sensitivity: defaultSensitivity,
            isNarrator: false,
            role: .character,
            bookID: bookID
        )
        characters.append(newCharacter)
        statusMessage = "已添加角色「\(name)」。"
        updateRecommendations()
        saveState()
    }

    func deleteCharacter(at id: UUID) {
        characters.removeAll { $0.id == id }
        recommendations.removeAll { $0.id == id }
        statusMessage = "角色已删除。"
        saveState()
    }

    func sortCharactersByAppearance() {
        let counts = countCharacterAppearances(in: bookText)
        characters.sort { (counts[$0.name] ?? 0) > (counts[$1.name] ?? 0) }
    }

    func playSelectedChapter() async {
        guard !bookText.isEmpty else {
            await MainActor.run { statusMessage = "请先导入小说文本。" }
            return
        }
        guard let chapterID = selectedChapterID,
              let bookID = UUID(uuidString: currentBookID) else {
            await MainActor.run { statusMessage = "未找到当前章节。" }
            return
        }
        let chapterList = bookChaptersCache[bookID] ?? chapters
        guard let chapter = chapterList.first(where: { $0.id == chapterID }) else {
            await MainActor.run { statusMessage = "未找到当前章节。" }
            return
        }
        if characters.isEmpty || lastScannedBookText != bookText {
            await scanCharacters()
        }
        do {
            try await playChapterStreaming(chapter: chapter)
        } catch {
            await MainActor.run { statusMessage = "远程 TTS 服务不可用，使用系统语音播放当前章节。" }
            await playLocalSpeech(bookText)
        }
    }

    func playWholeBook() async {
        guard !bookText.isEmpty else {
            await MainActor.run { statusMessage = "请先导入小说文本。" }
            return
        }
        if characters.isEmpty || lastScannedBookText != bookText {
            await scanCharacters()
        }
        let chapterList = UUID(uuidString: currentBookID).flatMap { bookChaptersCache[$0] } ?? chapters
        guard !chapterList.isEmpty else {
            await MainActor.run { statusMessage = "未找到章节。" }
            return
        }
        for chapter in chapterList {
            if Task.isCancelled { break }
            do {
                try await playChapterStreaming(chapter: chapter)
            } catch {
                await MainActor.run { statusMessage = "远程 TTS 服务不可用，使用系统语音播放整本小说。" }
                await playLocalSpeech(bookText)
                return
            }
        }
    }

    private func cancelPlaybackTaskAndWait() async {
        let task = playbackTask
        playbackTask = nil  // 先清空引用，防止并发赋值
        task?.cancel()
        await task?.value
    }

    func stopPlayback() {
        let task = playbackTask
        playbackTask = nil
        task?.cancel()
        audioController.stop()
        AdvancedAudioPlaybackController.cleanupAllAudioFiles()
        speechSynthesizer.stopSpeaking(at: .immediate)
        playbackContinuationCancellable?.cancel()
        playbackContinuationCancellable = nil
        isSpeaking = false
        ttsIsPlaying = false
        currentParagraphIndex = nil
        currentSentenceIndex = nil
        currentSentenceText = nil
        statusMessage = "已停止播放。"
        ttsProgressMessage = ""
    }

    func immediateInterruptAndSeek(chapter: BookChapter, fromParagraphIndex: Int, sentenceIndex: Int? = nil) async {
        await cancelPlaybackTaskAndWait()
        audioController.stop()
        AdvancedAudioPlaybackController.cleanupAllAudioFiles()
        speechSynthesizer.stopSpeaking(at: .immediate)
        playbackContinuationCancellable?.cancel()
        playbackContinuationCancellable = nil
        isSpeaking = false
        ttsIsPlaying = false
        currentParagraphIndex = nil
        currentSentenceIndex = nil
        currentSentenceText = nil
        ttsProgressMessage = ""

        playbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                try await self.playChapterStreaming(chapter: chapter, fromParagraphIndex: max(0, fromParagraphIndex), fromSentenceIndex: sentenceIndex)
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { self.statusMessage = "朗读失败：\(error.localizedDescription)" }
                }
            }
        }
    }

    func startPlaybackTask(chapter: BookChapter, fromParagraphIndex: Int? = nil, sentenceIndex: Int? = nil) async {
        await cancelPlaybackTaskAndWait()
        playbackTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try Task.checkCancellation()
                try await self.playChapterStreaming(chapter: chapter, fromParagraphIndex: fromParagraphIndex, fromSentenceIndex: sentenceIndex)
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { self.statusMessage = "朗读失败：\(error.localizedDescription)" }
                }
            }
        }
    }

    nonisolated private static let dialogueOpenQuotes: Set<Character> = ["\u{201C}", "\u{300C}", "\u{300E}", "\u{2018}"]

    private nonisolated static func hasDialogueQuote(_ s: String) -> Bool {
        dialogueOpenQuotes.contains(where: s.contains)
    }

    /// Split block into sentences at 。！？ preserving the punctuation.
    /// Does NOT strip \u{3000} (full‑width space) — indentation must survive.
    nonisolated static func splitBlockIntoSentences(_ text: String) -> [String] {
        let terminators = "。！？"
        let nonIndentWs = CharacterSet.whitespacesAndNewlines.subtracting(CharacterSet(charactersIn: "\u{3000}"))
        var sentences: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if terminators.contains(ch) {
                let trimmed = current.trimmingCharacters(in: nonIndentWs)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: nonIndentWs)
        if !trimmed.isEmpty { sentences.append(trimmed) }
        return sentences.isEmpty ? [text] : sentences
    }

    /// Group paragraphs into dialogue blocks: merge consecutive paragraphs containing quotes,
    /// splitting only after 2 consecutive non-quote paragraphs.
    nonisolated private static func buildDialogueBlocks(_ paragraphs: [String]) -> [(texts: [String], globalStart: Int)] {
        var blocks: [(texts: [String], globalStart: Int)] = []
        var i = 0
        while i < paragraphs.count {
            // Skip leading non-quote paragraphs
            if !hasDialogueQuote(paragraphs[i]) {
                blocks.append(([paragraphs[i]], i))
                i += 1
                continue
            }
            // Start a dialogue block
            var blockParas: [String] = [paragraphs[i]]
            let blockStart = i
            i += 1
            var consecutiveEmpty = 0
            while i < paragraphs.count && consecutiveEmpty < 2 {
                let hasQuote = hasDialogueQuote(paragraphs[i])
                if !hasQuote {
                    consecutiveEmpty += 1
                } else {
                    consecutiveEmpty = 0
                }
                blockParas.append(paragraphs[i])
                i += 1
            }
            // If we stopped because of consecutive empty, remove trailing empties from the block
            if consecutiveEmpty >= 2 {
                blockParas.removeLast(consecutiveEmpty)
                i -= consecutiveEmpty
            }
            blocks.append((blockParas, blockStart))
        }
        return blocks
    }

    /// 逐段落流水线：高亮段落 → 识别对白 → Edge TTS 合成 → 播放
    func playChapterStreaming(chapter: BookChapter, fromParagraphIndex: Int? = nil, fromSentenceIndex: Int? = nil) async throws {
        await MainActor.run {
            isBusy = true
            statusMessage = "正在朗读 \(chapter.title)..."
        }

        let paragraphs = chapter.text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace).isEmpty }
        guard !paragraphs.isEmpty else {
            await MainActor.run {
                statusMessage = "当前章节为空，无法朗读。"
                isBusy = false
            }
            return
        }

        let startParaIndex = max(0, min(paragraphs.count - 1, fromParagraphIndex ?? 0))
        let startSentenceIndex = max(0, fromSentenceIndex ?? 0)

        let bookTitle = currentBookTitle.isEmpty ? "未知书籍" : currentBookTitle
        let bookUUID = UUID(uuidString: currentBookID) ?? UUID()
        let chapterIndex = chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
        let blocks = Self.buildDialogueBlocks(paragraphs)

        // S14: 单遍扫描 —— 解析所有句子，构建 DramaDirector 上下文（不再有第 2 遍全量扫描）
        let director = DramaDirector()
        var lastSpeakerID: UUID?
        var lastEmotionTag: String?
        var previousDialogueContext: DramaDirector.SentenceContext?
        var lastSpeaker: String? = nil

        struct PendingUnit {
            let sentence: String
            let characterName: String
            let speakerID: UUID?
            let voice: String?
            let rate: Double
            let pitch: Double
            let emotionTag: String
            let paragraphIndex: Int
            let sentenceIndex: Int
        }
        var pendingUnits: [PendingUnit] = []

        // Helper: iterate paragraphs within blocks, yielding (pIdx, sIdx, sentence)
        func forEachSentence(in blocks: [(texts: [String], globalStart: Int)],
                             startParaIndex: Int, startSentenceIndex: Int,
                             body: (Int, Int, String, String, Bool, UUID?, CharacterProfile?, String) -> Void) {
            for block in blocks {
                guard block.globalStart + block.texts.count > startParaIndex else { continue }
                for (offset, paraText) in block.texts.enumerated() {
                    let pIdx = block.globalStart + offset
                    let sentences = Self.splitBlockIntoSentences(paraText)
                    for (sIdx, sentence) in sentences.enumerated() {
                        if pIdx == startParaIndex && sIdx < startSentenceIndex { continue }
                        let parts = Self.parseDialogueSegments(in: sentence, characters: characters, lastSpeaker: lastSpeaker)
                        let speaker = parts.first?.speaker ?? "叙述者"
                        let canonical = characters.first(where: { $0.name == speaker || $0.aliases.contains(speaker) })?.name ?? speaker
                        let profile = characters.first(where: { $0.name == canonical })
                        let isNarrator = profile?.isNarrator ?? (speaker == "叙述者" || speaker == "旁白")
                        let speakerID = profile?.id
                        if !isNarrator { lastSpeaker = speaker }
                        let emotionTag = parts.first?.emotionTag ?? "neutral"
                        body(pIdx, sIdx, sentence, canonical, isNarrator, speakerID, profile, emotionTag)
                    }
                }
            }
        }

        // Pass 1: collect all sentence contexts for upcoming-window lookahead
        struct SentenceCtx {
            let speakerID: UUID?
            let emotionTag: String
            let isNarrator: Bool
            let paragraphIndex: Int
        }
        var allCtxs: [SentenceCtx] = []
        forEachSentence(in: blocks, startParaIndex: startParaIndex, startSentenceIndex: startSentenceIndex) { pIdx, _, _, _, isNarrator, speakerID, _, emotionTag in
            allCtxs.append(SentenceCtx(speakerID: speakerID, emotionTag: emotionTag, isNarrator: isNarrator, paragraphIndex: pIdx))
        }

        // Pass 2: process with proper upcoming-window lookahead
        var ctxIndex = 0
        lastSpeaker = nil  // reset for second pass
        forEachSentence(in: blocks, startParaIndex: startParaIndex, startSentenceIndex: startSentenceIndex) { pIdx, sIdx, sentence, canonical, isNarrator, speakerID, profile, emotionTag in
            let unit = SentenceUnit(
                text: sentence, speakerID: speakerID,
                emotionTag: emotionTag,
                anchor: PlaybackAnchor(
                    bookID: bookUUID.uuidString, chapterIndex: chapterIndex,
                    paragraphIndex: pIdx, sentenceIndex: sIdx, speakerID: speakerID
                ),
                estimatedDuration: 2.0, estimatedSpeed: 1.0, estimatedPitch: 1.0
            )

            // Build upcoming window from pre-collected contexts (next 5 sentences)
            let upcomingSentences: [DramaDirector.SentenceContext] = {
                let start = ctxIndex + 1
                let end = min(start + 5, allCtxs.count)
                guard start < end else { return [] }
                return allCtxs[start..<end].map { c in
                    DramaDirector.SentenceContext(
                        text: "", speakerID: c.speakerID,
                        emotionTag: c.emotionTag, isNarrator: c.isNarrator,
                        speed: 1.0, pitch: 1.0, paragraphIndex: c.paragraphIndex
                    )
                }
            }()

            let contextWindow = DramaDirector.ContextWindow(
                previousDialogue: previousDialogueContext,
                upcomingSentences: upcomingSentences,
                lastSpeakerID: lastSpeakerID,
                lastEmotionTag: lastEmotionTag,
                paragraphIndex: pIdx,
                totalParagraphs: paragraphs.count
            )
            let refined = director.contextualize(unit, context: contextWindow)
            if let sid = refined.speakerID { lastSpeakerID = sid; lastEmotionTag = refined.emotionTag }
            previousDialogueContext = DramaDirector.SentenceContext(
                text: refined.text, speakerID: refined.speakerID,
                emotionTag: refined.emotionTag, isNarrator: isNarrator,
                speed: refined.estimatedSpeed, pitch: refined.estimatedPitch,
                paragraphIndex: pIdx
            )
            ctxIndex += 1

            pendingUnits.append(PendingUnit(
                sentence: sentence, characterName: canonical, speakerID: speakerID,
                voice: (profile?.voice.isEmpty == false) ? profile?.voice : nil,
                rate: Double(profile?.rate ?? 0), pitch: Double(profile?.pitch ?? 0),
                emotionTag: refined.emotionTag,
                paragraphIndex: pIdx, sentenceIndex: sIdx
            ))
        }

        guard !pendingUnits.isEmpty else {
            await MainActor.run { statusMessage = "没有可朗读的内容。" }
            await MainActor.run { isBusy = false }
            return
        }

        // S15: AudioPrefetcher —— 滑动窗口预取前 N 句音频
        let prefetcher = AudioPrefetcher()
        let prefetchWindowSize = 5
        // 立即预取前 N 句（HTTP 并行发出，不等响应）
        for i in 0..<min(prefetchWindowSize, pendingUnits.count) {
            let u = pendingUnits[i]
            await prefetcher.prefetch(index: i, text: u.sentence, voice: u.voice,
                                rate: u.rate, pitch: u.pitch, style: u.emotionTag)
        }

        // S16: 消费循环 —— 每句异步等待音频数据，立即入队播放，同步预取后续句子
        var consumed = 0
        var isFirst = true
        for (index, u) in pendingUnits.enumerated() {
            guard !Task.isCancelled else { break }
            let audioData = await prefetcher.waitFor(index: index)
            // 滑窗：预取后续句子
            let nextIndex = index + prefetchWindowSize
            if nextIndex < pendingUnits.count {
                let nu = pendingUnits[nextIndex]
                await prefetcher.prefetch(index: nextIndex, text: nu.sentence, voice: nu.voice,
                                    rate: nu.rate, pitch: nu.pitch, style: nu.emotionTag)
            }
            guard let audioData = audioData else { continue }

            let anchor = PlaybackAnchor(
                bookID: bookUUID.uuidString, chapterIndex: chapterIndex,
                paragraphIndex: u.paragraphIndex, sentenceIndex: u.sentenceIndex, speakerID: u.speakerID
            )
            let seg = ScriptSegment(
                id: UUID(), characterName: u.characterName,
                voice: u.voice ?? "", rate: Int(u.rate), pitch: Int(u.pitch), style: u.emotionTag,
                text: u.sentence, paragraphIndex: u.paragraphIndex
            )
            // S16: 内存 Data 播放，不再写临时文件
            let item = TTSQueueItem(
                segment: seg, audioURL: nil, audioData: audioData,
                chapterTitle: chapter.title, bookTitle: bookTitle,
                bookID: bookUUID.uuidString, chapterIndex: chapterIndex,
                segmentIndex: index, totalSegments: pendingUnits.count,
                paragraphIndex: u.paragraphIndex, sentenceIndex: u.sentenceIndex, anchor: anchor
            )

            await MainActor.run {
                ttsChapterTitle = chapter.title
                ttsSegmentTitle = u.characterName
                ttsIsPlaying = true; isSpeaking = true
                currentParagraphIndex = u.paragraphIndex
                currentSentenceIndex = u.sentenceIndex
                currentSentenceText = u.sentence
                statusMessage = "朗读中..."; ttsProgressMessage = ""
            }
            if isFirst {
                audioController.playQueue([item])
                isFirst = false
            } else {
                audioController.appendToQueue([item])
            }
            consumed += 1
        }

        guard consumed > 0 else {
            await MainActor.run { statusMessage = "没有可朗读的内容。" }
            await MainActor.run { isBusy = false }
            return
        }

        // Wait for playback completion with timeout
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if !audioController.isPlaying { cont.resume(); return }
            let c = audioController.$isPlaying
                .dropFirst().filter { !$0 }.first()
                .sink { _ in
                    self.playbackContinuationCancellable = nil
                    cont.resume()
                }
            playbackContinuationCancellable = c
            // 超时兜底: 10秒后无论是否播完都 resume，避免 permanent hang
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                guard let c = self.playbackContinuationCancellable else { return }
                self.playbackContinuationCancellable = nil
                c.cancel()
                cont.resume()
            }
        }
        playbackContinuationCancellable = nil

        // S16: 无需 cleanup 临时音频文件（已全部内存播放）

        await MainActor.run {
            isSpeaking = false; isBusy = false; ttsIsPlaying = false
            if !Task.isCancelled { statusMessage = "已播放完毕。" }
            ttsProgressMessage = ""
        }
    }

    func playChapterWithTTS(chapter: BookChapter, fromParagraphIndex: Int? = nil) async {
        await MainActor.run { statusMessage = "正在准备朗读章节..." }
        do {
            try await playChapterStreaming(chapter: chapter, fromParagraphIndex: fromParagraphIndex)
        } catch {
            await MainActor.run { statusMessage = "朗读失败: \(error.localizedDescription)" }
        }
    }

    /// 多角色 AI 朗读：使用 AI Worker 解析章节 → 分配音色 → 并发合成 → 流式播放
    func playChapterWithAI(chapter: BookChapter, fromParagraphIndex: Int? = nil) async {
        await MainActor.run {
            stopPlayback()
            isBusy = true
            isLoadingAISegments = true
            statusMessage = "正在解析章节角色..."
        }

        defer {
            Task { @MainActor in
                isBusy = false
                isLoadingAISegments = false
            }
        }

        guard !chapter.text.isEmpty else {
            await MainActor.run { statusMessage = "章节内容为空。" }
            return
        }

        let bookTitle = currentBookTitle.isEmpty ? "未知书籍" : currentBookTitle
        let bookUUID = UUID(uuidString: currentBookID) ?? UUID()
        let chapterIndex = chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0

        // 1. Check AIParseCache
        var aiSegments: [AISegment]
        if let cached = await aiParseCache.getSegments(chapter: chapter) {
            aiSegments = cached
            DebugLogger.log(flow: "ai_worker", step: "playChapterWithAI_cache_hit", details: [
                "chapter": chapter.title,
                "segments_count": cached.count,
            ])
            await MainActor.run { statusMessage = "使用缓存解析结果 (\(cached.count) 段)..." }
        } else {
            // 2. Get default worker config
            guard let workerConfig = defaultWorkerConfig else {
                await MainActor.run { statusMessage = "未配置 AI Worker，请在设置中添加。" }
                return
            }

            await MainActor.run { statusMessage = "正在调用 AI Worker 解析..." }
            DebugLogger.log(flow: "ai_worker", step: "playChapterWithAI_start", details: [
                "chapter": chapter.title,
                "text_length": chapter.text.count,
            ])

            do {
                aiSegments = try await AIWorkerService.shared.processChapter(
                    text: chapter.text,
                    config: workerConfig,
                    progress: { @Sendable [weak self] progress, message in
                        await MainActor.run { self?.statusMessage = message }
                    }
                )
            } catch {
                DebugLogger.log(flow: "ai_worker", step: "playChapterWithAI_error", details: [
                    "error": error.localizedDescription,
                ])
                await MainActor.run { statusMessage = "AI 解析失败: \(error.localizedDescription)" }
                return
            }

            // 3. Cache results
            await aiParseCache.save(chapter: chapter, segments: aiSegments)
        }

        guard !aiSegments.isEmpty, !Task.isCancelled else {
            await MainActor.run { statusMessage = "解析结果为空。" }
            return
        }

        // 4. Build speaker→voice mapping using autoMatchVoice
        await MainActor.run { statusMessage = "正在分配音色 (\(aiSegments.count) 段)..." }

        let edgeVoices = await EdgeTTSService.shared.fetchVoices()
        let fallbackVoices: [EdgeVoiceInfo] = [
            EdgeVoiceInfo(id: "zh-CN-XiaoxiaoNeural", name: "小晓", gender: "Female", locale: "zh-CN"),
            EdgeVoiceInfo(id: "zh-CN-YunxiNeural", name: "云希", gender: "Male", locale: "zh-CN"),
        ]
        let availableVoices = edgeVoices.isEmpty ? fallbackVoices : edgeVoices

        var speakerVoiceMap: [String: String] = [:]
        for seg in aiSegments {
            guard speakerVoiceMap[seg.speaker] == nil else { continue }
            let voice = TTSView.autoMatchVoice(for: seg.speaker, gender: seg.gender, availableVoices: availableVoices)
            speakerVoiceMap[seg.speaker] = voice
        }

        // 5. Merge consecutive segments for same speaker/emotion/tone
        let mergedSegments = mergeConsecutiveAISegments(aiSegments)
        DebugLogger.log(flow: "ai_worker", step: "playChapterWithAI_merged", details: [
            "before_merge": aiSegments.count,
            "after_merge": mergedSegments.count,
        ])

        guard !mergedSegments.isEmpty, !Task.isCancelled else {
            await MainActor.run { statusMessage = "合并后无有效片段。" }
            return
        }

        // 6. Concurrently synthesize with SynthesisBuffer
        let totalCount = mergedSegments.count
        await MainActor.run { statusMessage = "正在合成音频 (\(totalCount) 段)..." }

        let buffer = SynthesisBuffer { @Sendable [weak self] readyItems in
            guard let self else { return }
            let shouldPlayFirst = await buffer.markFirstPlayed()
            if shouldPlayFirst {
                await audioController.playQueue(readyItems)
            } else {
                await audioController.appendToQueue(readyItems)
            }
        }

        try? await withThrowingTaskGroup(of: (Int, TTSQueueItem).self) { group in
            for (idx, seg) in mergedSegments.enumerated() {
                guard !Task.isCancelled else { break }
                group.addTask { [weak self] in
                    guard let self else { throw CancellationError() }
                    let speaker = seg.speaker
                    let voice = speakerVoiceMap[speaker] ?? ""
                    let rate = TTSView.rateOffset(for: seg)
                    let pitch = TTSView.pitchOffset(for: seg, speakerName: speaker)
                    let volume = TTSView.resolvedVolume(tone: seg.tone, globalOffset: 0)
                    let style = seg.emotion.ssmlStyle

                    let audioData = try await EdgeTTSService.shared.synthesize(
                        text: seg.text,
                        voice: voice.isEmpty ? nil : voice,
                        rate: Double(rate),
                        pitch: Double(pitch),
                        style: style,
                        volume: volume
                    )

                    let scriptSeg = ScriptSegment(
                        id: UUID(),
                        characterName: speaker,
                        voice: voice,
                        rate: rate,
                        pitch: pitch,
                        style: style,
                        text: seg.text,
                        emotionTag: seg.emotion.rawValue,
                        paragraphIndex: idx
                    )

                    let anchor = PlaybackAnchor(
                        bookID: bookUUID.uuidString,
                        chapterIndex: chapterIndex,
                        paragraphIndex: idx,
                        sentenceIndex: 0,
                        speakerID: nil
                    )

                    let item = TTSQueueItem(
                        segment: scriptSeg,
                        audioURL: nil,
                        audioData: audioData,
                        chapterTitle: chapter.title,
                        bookTitle: bookTitle,
                        bookID: bookUUID.uuidString,
                        chapterIndex: chapterIndex,
                        segmentIndex: idx,
                        totalSegments: totalCount,
                        paragraphIndex: idx,
                        sentenceIndex: nil,
                        anchor: anchor
                    )

                    return (idx, item)
                }
            }

            for try await (idx, item) in group {
                guard !Task.isCancelled else { break }
                await buffer.insert(idx, item)
            }
        }

        guard !Task.isCancelled else { return }
        await buffer.flushRemaining()

        // 7. Wait for playback completion
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if !audioController.isPlaying { cont.resume(); return }
            let c = audioController.$isPlaying
                .dropFirst().filter { !$0 }.first()
                .sink { _ in
                    self.playbackContinuationCancellable = nil
                    cont.resume()
                }
            playbackContinuationCancellable = c
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                guard let c = self.playbackContinuationCancellable else { return }
                self.playbackContinuationCancellable = nil
                c.cancel()
                cont.resume()
            }
        }
        playbackContinuationCancellable = nil

        await MainActor.run {
            isSpeaking = false
            ttsIsPlaying = false
            if !Task.isCancelled { statusMessage = "已播放完毕。" }
        }
    }

    /// 合并说话人/情绪/语气相同的连续段落
    private func mergeConsecutiveAISegments(_ segments: [AISegment]) -> [AISegment] {
        guard !segments.isEmpty else { return segments }
        var merged: [AISegment] = []
        var current = segments[0]
        for seg in segments.dropFirst() {
            if seg.speaker == current.speaker && seg.emotion == current.emotion && seg.tone == current.tone {
                let sep = current.text.hasSuffix("。") || current.text.hasSuffix("？") || current.text.hasSuffix("！") ? "" : "。"
                current = AISegment(
                    speaker: current.speaker,
                    emotion: current.emotion,
                    tone: current.tone,
                    text: current.text + sep + seg.text,
                    gender: current.gender
                )
            } else {
                merged.append(current)
                current = seg
            }
        }
        merged.append(current)
        return merged
    }

    private func playLocalSpeech(_ text: String) async {
        stopPlayback()
        isSpeaking = true
        statusMessage = "正在使用系统语音朗读..."

        let textBlocks = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace).isEmpty }
        if textBlocks.isEmpty {
            isSpeaking = false
            statusMessage = "当前内容为空，无法朗读。"
            return
        }

        for block in textBlocks {
            let utterance = AVSpeechUtterance(string: block)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN") ?? AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
            utterance.preUtteranceDelay = 0.1
            speechSynthesizer.speak(utterance)
        }
        // note: AVSpeechSynthesizer uses delegate proxy to update isSpeaking when done
    }

    private enum TimeoutError: Error {
        case timedOut
    }

    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timedOut
            }
            guard let result = try await group.next() else {
                throw TimeoutError.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    nonisolated func detectNarratorPatterns(in text: String) -> [String: Int] {
        var patterns: [String: Int] = [:]
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("第") && trimmed.contains("章") { patterns["chapter", default: 0] += 1 }
            if trimmed.hasPrefix("“") || trimmed.hasPrefix("「") { patterns["dialogue", default: 0] += 1 }
            if trimmed.hasSuffix("。") && !trimmed.contains("说") && !trimmed.contains("道") { patterns["narrative", default: 0] += 1 }
        }
        return patterns
    }

    nonisolated func isLikelyNarrator(name: String, context: String, narratorIndicators: [String: Int]) -> Bool {
        if name.contains("旁白") || name.contains("叙述") { return true }
        if narratorIndicators["narrative", default: 0] > narratorIndicators["dialogue", default: 0] * 2 { return true }
        return false
    }

    nonisolated static func extractChapters(from text: String) -> [BookChapter] {
        let result = parseChapters(text: text)
        if !result.isEmpty { return result }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return splitIntoPseudoChapters(trimmed)
    }

    nonisolated static func splitIntoPseudoChapters(_ text: String) -> [BookChapter] {
        let pageSize = 5000
        var chapters: [BookChapter] = []
        var startIndex = text.startIndex
        var chapterIndex = 1

        while startIndex < text.endIndex {
            let endIndex = text.index(startIndex, offsetBy: pageSize, limitedBy: text.endIndex) ?? text.endIndex
            var splitIndex = endIndex
            if splitIndex < text.endIndex {
                if let punct = text[startIndex..<endIndex].lastIndex(where: { ".。！？!?".contains($0) }) {
                    splitIndex = text.index(after: punct)
                }
            }
            let chunk = String(text[startIndex..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chapters.append(BookChapter(id: UUID(), title: "第\(chapterIndex)章", text: chunk))
                chapterIndex += 1
            }
            startIndex = splitIndex
        }

        if chapters.isEmpty {
            return [BookChapter(id: UUID(), title: "全文", text: text)]
        }
        return chapters
    }


    nonisolated func inferCharacters(from text: String, voices: [VoiceItem], defaultSensitivity: Int) async -> [CharacterProfile] {
        // Use AI Worker instead of local scanner
        // This method is used for non-UI background processing
        // For now, fallback to simple heuristic since we can't access AIWorkerConfig here
        // The main scanning is done via TTSViewModel with proper AIWorkerConfig
        
        // Simple fallback: create a narrator profile
        let narrator = CharacterProfile(
            id: UUID(),
            name: "叙述者",
            aliases: [],
            gender: "Unknown",
            age: "未知",
            tone: "中性",
            voice: defaultVoice(for: "Unknown", tone: "neutral", role: "旁白", voices: voices),
            rate: 0,
            pitch: 0,
            style: "neutral",
            sensitivity: defaultSensitivity,
            isNarrator: true,
            role: .narrator
        )
        return [narrator]
    }

    nonisolated func createScriptSegments(from text: String, characters: [CharacterProfile], defaultSensitivity: Int, voices: [VoiceItem], defaultMaleVoiceID: String = "", defaultFemaleVoiceID: String = "", defaultFallbackRateOffset: Int = 0, defaultFallbackPitchOffset: Int = 0, defaultFallbackStyle: String = "neutral") -> [ScriptSegment] {
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace).isEmpty }
        var segments: [ScriptSegment] = []
        var lastSpeaker: String? = nil
        let maxLength = 350
        let blocks = Self.buildDialogueBlocks(paragraphs)

        let sharedAnalyzer = CharacterAnalyzer()  // reuse single instance

        for (_, block) in blocks.enumerated() {
            let mergedText = block.texts.joined(separator: "\n\n")
            let dialogueParts = Self.parseDialogueSegments(in: mergedText, characters: characters, lastSpeaker: lastSpeaker)

            // Update cross-block speaker tracking (skip narrator)
            if let lastPart = dialogueParts.last, lastPart.speaker != "叙述者" && lastPart.speaker != "旁白" {
                lastSpeaker = lastPart.speaker
            }

            for part in dialogueParts {
                let speakerProfile = characters.first(where: { $0.name == part.speaker || $0.aliases.contains(part.speaker) })
                let chunks = part.text.chunked(into: maxLength)
                for chunk in chunks {
                    let toneResult = sharedAnalyzer.analyzeSentenceTone(chunk)
                    var profile = speakerProfile ?? CharacterProfile(id: UUID(), name: part.speaker, gender: "未知", age: "未知", tone: toneResult.style, voice: "", rate: 0, pitch: 0, style: "neutral", sensitivity: defaultSensitivity)

                    if profile.voice.isEmpty && speakerProfile == nil {
                        let isMale = guessGender(from: part.speaker)
                        if isMale, !defaultMaleVoiceID.isEmpty {
                            profile.voice = defaultMaleVoiceID
                        } else if !isMale, !defaultFemaleVoiceID.isEmpty {
                            profile.voice = defaultFemaleVoiceID
                        }
                        profile.rate = defaultFallbackRateOffset
                        profile.pitch = defaultFallbackPitchOffset
                        profile.style = defaultFallbackStyle
                    }
                    if profile.voice.isEmpty {
                        profile.voice = defaultVoice(for: profile.gender, tone: toneResult.style, name: profile.name, voices: voices)
                    }

                    let sensitivityValue = (profile.sensitivity > 0) ? profile.sensitivity : defaultSensitivity
                    let sensitivityFactor = Double(max(0, min(sensitivityValue, 100))) / 50.0
                    let scaledPitchAdjustment = Int(Double(toneResult.pitchAdjust) * sensitivityFactor)

                    let finalStyle: String
                    if profile.style != "neutral" {
                        finalStyle = profile.style
                    } else {
                        finalStyle = sensitivityFactor >= 0.6 ? toneResult.style : "neutral"
                    }

                    let finalPitch = profile.pitch + scaledPitchAdjustment
                    let finalRate = profile.rate + (sensitivityValue > 50 ? toneResult.rateAdjust : 0)

                    segments.append(ScriptSegment(
                        id: UUID(),
                        characterName: profile.name,
                        voice: profile.voice,
                        rate: finalRate,
                        pitch: finalPitch,
                        style: finalStyle,
                        text: chunk,
                        emotionTag: part.emotionTag
                    ))
                }
            }
        }
        return segments
    }

    // MARK: - Dialogue parsing

    /// A segment parsed from a paragraph: either a character's dialogue or narration.
    private struct DialoguePart {
        let speaker: String
        let text: String
        let emotionTag: String?  // CosyVoice emotion tag, nil for narration
    }

    nonisolated private static let quotePairs: [(open: Character, close: Character)] = [
        ("\u{300C}", "\u{300D}"),
        ("\u{201C}", "\u{201D}"),
        ("\u{2018}", "\u{2019}"),
        ("\u{300E}", "\u{300F}"),
    ]

    /// Map internal tone names (from analyzeSentenceTone) to Edge TTS emotion tags.
    nonisolated private static func mapToneToEmotionTag(_ tone: String) -> String? {
        switch tone.lowercased() {
        case "angry":      return "angry"
        case "cheerful":   return "happy"
        case "sad":        return "sad"
        default:           return nil
        }
    }

    /// Parse a paragraph into (speaker, text) segments by detecting dialogue quotes.
    /// Non-quoted text → narrator. Quoted text → detected speaker (from speech verbs before/after the quote).
    nonisolated private static func parseDialogueSegments(in paragraph: String, characters: [CharacterProfile], lastSpeaker: String?, previousContextSuffix: String = "") -> [DialoguePart] {
        let narratorName = characters.first(where: { $0.isNarrator })?.name ?? "叙述者"
        let chars = Array(paragraph)
        var parts: [DialoguePart] = []
        var pos = 0
        var currentLastSpeaker = lastSpeaker
        let toneAnalyzer = CharacterAnalyzer()

        while pos < chars.count {
            // Find the next quote opener
            var bestOpenIdx: Int? = nil
            var bestOpenChar: Character? = nil
            var bestCloseChar: Character? = nil

            for (open, close) in quotePairs {
                if let idx = findChar(chars, open, from: pos) {
                    if bestOpenIdx == nil || idx < bestOpenIdx! {
                        bestOpenIdx = idx
                        bestOpenChar = open
                        bestCloseChar = close
                    }
                }
            }

            guard let openIdx = bestOpenIdx, let closeCh = bestCloseChar else {
                // No more quotes — remaining text is narration
                let remaining = String(chars[pos...])
                if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(DialoguePart(speaker: narratorName, text: remaining, emotionTag: nil))
                }
                break
            }

            // Text before the quote (narration, may contain speaker indicators)
            if openIdx > pos {
                let beforeText = String(chars[pos..<openIdx])
                if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(DialoguePart(speaker: narratorName, text: beforeText, emotionTag: nil))
                }
            }

            // Find the closing quote
            let closeIdx = findQuoteClose(chars, openChar: bestOpenChar ?? closeCh, closeChar: closeCh, from: openIdx + 1)
            let quoteText: String
            if let ci = closeIdx {
                quoteText = String(chars[(openIdx + 1)..<ci])
                pos = ci + 1
            } else {
                // No closing quote found — treat from opener to end as quote
                quoteText = String(chars[(openIdx + 1)...])
                pos = chars.count
            }

            // Detect speaker from context before or after the quote
            var speaker: String? = nil

            // Look backwards from opener for name+speech verb within 100 chars
            let lookBackStart = max(0, openIdx - 100)
            let beforeContext = String(chars[lookBackStart..<openIdx])
            // 当对白靠近段首时，合并前一段落末尾文本作为上下文
            let mergedContext = openIdx < 80 && !previousContextSuffix.isEmpty ? previousContextSuffix + beforeContext : beforeContext

            // Regex-based speaker detection; no external BERT dependency.
            var regexSpeaker: String? = nil
            if let detected = detectSpeakerInContext(mergedContext, characters: characters) {
                regexSpeaker = detected
            }
            // If not found before, look forwards from closer for speech verb+name
            if regexSpeaker == nil, let ci = closeIdx ?? bestOpenIdx.map({ $0 + quoteText.count + 1 }) {
                let lookAheadEnd = min(chars.count, ci + 80)
                if ci + 1 < chars.count && ci + 1 < lookAheadEnd {
                    let afterContext = String(chars[(ci + 1)..<lookAheadEnd])
                    if let detected = detectSpeakerAfterQuote(afterContext, characters: characters) {
                        regexSpeaker = detected
                    }
                }
            }

            if regexSpeaker != nil {
                speaker = regexSpeaker
            }

            // If still not found: vocative (name at quote start) is the ADDRESSEE,
            // not the speaker. Skip assignment so currentLastSpeaker/narrator handles it.
            // (旧代码错误地将受话者分配给 speaker，现已删除)

            let resolvedSpeaker = speaker ?? currentLastSpeaker ?? narratorName
            currentLastSpeaker = resolvedSpeaker

            if !quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let tone = toneAnalyzer.analyzeSentenceTone(quoteText)
                let emotionTag = Self.mapToneToEmotionTag(tone.style)
                parts.append(DialoguePart(speaker: resolvedSpeaker, text: quoteText, emotionTag: emotionTag))
            }
        }

        return parts
    }

    /// Find the first occurrence of a character starting from a position.
    nonisolated private static func findChar(_ chars: [Character], _ ch: Character, from: Int) -> Int? {
        for i in from..<chars.count {
            if chars[i] == ch { return i }
        }
        return nil
    }

    /// Find the matching closing quote, handling nesting of the same quote type.
    nonisolated private static func findQuoteClose(_ chars: [Character], openChar: Character, closeChar: Character, from: Int) -> Int? {
        // Simple approach: find the next closing char. In practice, Chinese web novels
        // rarely nest quotes of the same type, so linear search is sufficient.
        for i in from..<chars.count {
            if chars[i] == closeChar { return i }
        }
        return nil
    }

    /// Detect speaker from context BEFORE a quote (e.g. "陈煜笑道：「...").
    /// 按照文章顺序：优先从最近的上文中匹配角色名。
    nonisolated private static func detectSpeakerInContext(_ context: String, characters: [CharacterProfile]) -> String? {
        let speechVerbs = "说|道|笑道|说道|喊道|问道|怒道|哭道|叹道|骂道|喝道|叫道|低声道|轻声道|柔声道|冷声道|颤声道|沉声道|厉声道|正色道|正色说|接话道|插嘴道|接口道|应声道|抢先道|解释道|回答|追问|吩咐|叮嘱|嘱咐|呵斥|训斥|呵道"
        // 1. Name + speech verb (+ optional colon) at end — highest confidence
        if let groups = context.firstMatch(regex: "([\\p{Han}]{2,4})(?:\(speechVerbs))[：:\\s]*$"), groups.count > 1 {
            let name = groups[1]
            if characters.contains(where: { $0.name == name || $0.aliases.contains(name) }) {
                return name
            }
        }
        // 2. Name： at end
        if let groups = context.firstMatch(regex: "([\\p{Han}]{2,4})[：:]$"), groups.count > 1 {
            let name = groups[1]
            if characters.contains(where: { $0.name == name || $0.aliases.contains(name) }) {
                return name
            }
        }
        // 3. Character name at end of context
        let trimmed = context.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .init(charactersIn: "：:"))
        for ch in characters {
            if context.hasSuffix(ch.name) || trimmed.hasSuffix(ch.name) {
                return ch.name
            }
        }
        // 4. 按照文章顺序：取上下文中**最先**出现的已知角色名
        var firstPos = Int.max
        var firstName: String?
        for ch in characters {
            if let r = context.range(of: ch.name) {
                let pos = context.distance(from: context.startIndex, to: r.lowerBound)
                if pos < firstPos {
                    firstPos = pos
                    firstName = ch.name
                }
            }
        }
        return firstName
    }

    /// Detect speaker from context AFTER a quote (e.g. "「...」陈煜笑道").
    nonisolated private static func detectSpeakerAfterQuote(_ context: String, characters: [CharacterProfile]) -> String? {
        let speechVerbs = "说|道|笑道|说道|喊道|问道|怒道|哭道|叹道|骂道|喝道|叫道|低声道|轻声道|柔声道|冷声道|颤声道|沉声道|厉声道|正色道|正色说|接话道|插嘴道|接口道|应声道|抢先道|解释道|回答|追问|吩咐|叮嘱|嘱咐|呵斥|训斥|呵道"
        // 1. Speech verb + name at start
        if let groups = context.firstMatch(regex: "^(?:\(speechVerbs))([\\p{Han}]{2,4})"), groups.count > 1 {
            let name = groups[1]
            if characters.contains(where: { $0.name == name || $0.aliases.contains(name) }) {
                return name
            }
        }
        // 2. Name + speech verb at start
        if let groups = context.firstMatch(regex: "^([\\p{Han}]{2,4})(?:\(speechVerbs))"), groups.count > 1 {
            let name = groups[1]
            if characters.contains(where: { $0.name == name || $0.aliases.contains(name) }) {
                return name
            }
        }
        // 3. Known character name at start
        for ch in characters {
            if context.hasPrefix(ch.name) || context.hasPrefix("\(ch.name)") {
                return ch.name
            }
        }
        // 4. 全文搜索：取上下文中**最先**出现的已知角色名
        var firstPos = Int.max
        var firstName: String?
        for ch in characters {
            if let r = context.range(of: ch.name) {
                let pos = context.distance(from: context.startIndex, to: r.lowerBound)
                if pos < firstPos {
                    firstPos = pos
                    firstName = ch.name
                }
            }
        }
        return firstName
    }

    private func paragraphIndex(for paragraphText: String, in chapterText: String) -> Int? {
        let paragraphs = chapterText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace).isEmpty }
        let trimmed = paragraphText.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace)
        guard !trimmed.isEmpty else { return nil }
        // 精确匹配整段内容，避免子串歧义
        if let exact = paragraphs.firstIndex(where: { $0 == trimmed }) { return exact }
        // 容错: 去掉末尾标点再匹配
        let withoutPunct = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "。！？!?.，,；;"))
        if withoutPunct != trimmed,
           let idx = paragraphs.firstIndex(where: { $0 == withoutPunct || $0.hasPrefix(withoutPunct) }) {
            return idx
        }
        // 最后容错: 子串包含匹配（保留原始兼容性）
        return paragraphs.firstIndex(where: { $0.contains(trimmed) })
    }

    func playFromParagraph(_ paragraph: String) async {
        guard !bookText.isEmpty else {
            await MainActor.run { statusMessage = "请先导入小说文本。" }
            return
        }
        if characters.isEmpty || lastScannedBookText != bookText {
            await scanCharacters()
        }
        guard let bookID = UUID(uuidString: currentBookID),
              let chapterID = selectedChapterID else {
            await MainActor.run { statusMessage = "未找到当前章节。" }
            return
        }
        let chapterList = bookChaptersCache[bookID] ?? chapters
        guard let chapter = chapterList.first(where: { $0.id == chapterID }) else {
            await MainActor.run { statusMessage = "未找到当前章节。" }
            return
        }
        let trimmed = paragraph.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace)
        let fromParagraphIndex = trimmed.isEmpty ? nil : paragraphIndex(for: trimmed, in: chapter.text)
        do {
            try await playChapterStreaming(chapter: chapter, fromParagraphIndex: fromParagraphIndex)
        } catch {
            await MainActor.run { statusMessage = "朗读失败：\(error.localizedDescription)" }
        }
    }

    // Quick E2E test helper: import sample text, build script for first chapter and synthesize first segment
    func runQuickE2ETest(sampleText: String) async -> String {
        await importText(sampleText)
        await buildScript(for: false)
        guard let first = scriptSegments.first else { return "脚本为空，无法测试。" }
        do {
            let audioData = try await EdgeTTSService.shared.synthesize(text: first.text)
            let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-test-\(UUID().uuidString).\(ext)")
            try audioData.write(to: url, options: .atomic)
            await audioController.playFilesAndWait([url])
            return "合成并播放成功：\(url.lastPathComponent)"
        } catch {
            return "合成失败：\(error.localizedDescription)"
        }
    }

    nonisolated func detectSpeaker(in line: String, characters: [CharacterProfile]) -> String? {
        // Build lookup: all name variants (canonical + aliases) → canonical name
        var nameToCanonical: [String: String] = [:]
        for profile in characters {
            nameToCanonical[profile.name] = profile.name
            for alias in profile.aliases {
                nameToCanonical[alias] = profile.name
            }
        }
        let allNames = Array(nameToCanonical.keys)
        let analyzer = CharacterAnalyzer()
        if let speaker = analyzer.inferSpeaker(from: line, knownCharacters: allNames),
           let canonical = nameToCanonical[speaker] {
            return canonical
        }
        // Priority 1: Named "Name：" or "Name:" at start of line
        if let groups = line.firstMatch(regex: "^([\\p{Han}]{2,4})[：:]"), groups.count > 1 {
            return groups[1]
        }
        // Priority 2: Character name + speech verb (笑道/说道/问道/喊道/…)
        if let groups = line.firstMatch(regex: "([\\p{Han}]{2,4})(?=笑道|说道|问道|喊道|叫道|喝道|骂道|答道|回答|解释说|解释道|忽然道|低声道|轻声道|怒道|笑道|叹道|哭道|骂道|喝道|厉声道|正色道)"), groups.count > 1 {
            return groups[1]
        }
        // Priority 3: "Name：" before a Chinese quote
        if let groups = line.firstMatch(regex: "([\\p{Han}]{2,4})[：:][「『“‘]"), groups.count > 1 {
            return groups[1]
        }
        // Priority 4: Any known character name appearing at line start
        for profile in characters {
            if line.hasPrefix(profile.name) {
                return profile.name
            }
        }
        // Priority 5: Any known character name appearing anywhere in line (weak)
        for profile in characters {
            if line.contains(profile.name) {
                return profile.name
            }
        }
        return nil
    }

    func updateRecommendations(from sourceText: String? = nil) {
        let text = sourceText ?? bookText
        guard !characters.isEmpty else {
            recommendations = []
            return
        }

        let counts = countCharacterAppearances(in: text)
        let candidates = characters.sorted { (counts[$0.name] ?? 0) > (counts[$1.name] ?? 0) }
        let voiceOptions = voices.isEmpty ? VoiceItem.defaultItems() : voices

        recommendations = candidates.map { profile in
            let suggested = suggestedVoices(for: profile, from: voiceOptions)
            let count = counts[profile.name] ?? 0
            return CharacterRecommendation(id: profile.id, profile: profile, count: count, suggestedVoices: suggested)
        }
    }

    func countCharacterAppearances(in text: String) -> [String: Int] {
        // Count appearances for aliases too, map back to canonical name
        var allLookups: [String: String] = [:]
        for profile in characters {
            allLookups[profile.name] = profile.name
            for alias in profile.aliases where !alias.isEmpty {
                allLookups[alias] = profile.name
            }
        }
        let result = CharacterAnalyzer().countAppearances(text: text, characterNames: Array(allLookups.keys))
        var aggregated: [String: Int] = [:]
        for (name, count) in result {
            let canonical = allLookups[name] ?? name
            aggregated[canonical, default: 0] += count
        }
        return aggregated
    }

    func buildRelationshipGraph(in text: String) -> [RelationshipEdge] {
        let graphNames = characters.flatMap { [$0.name] + $0.aliases }
        return CharacterAnalyzer().buildRelationshipGraph(text: text, characterNames: graphNames)
    }

    func defaultVoiceItems() -> [VoiceItem] {
        VoiceItem.defaultItems()
    }

    nonisolated func detectGender(in context: String) -> String {
        let ctx = context
        if ctx.contains("小姐") || ctx.contains("姑娘") || ctx.contains("她") || ctx.contains("母亲") || ctx.contains("姐姐") || ctx.contains("妹妹") || ctx.contains("老婆") || ctx.contains("太太") || ctx.contains("闺女") || ctx.contains("妇人") || ctx.contains("婶婶") || ctx.contains("奶奶") || ctx.contains("姥姥") || ctx.contains("女士") || ctx.contains("女儿") {
            return "女性"
        }
        if ctx.contains("先生") || ctx.contains("公子") || ctx.contains("哥哥") || ctx.contains("弟弟") || ctx.contains("丈夫") || ctx.contains("小伙") || ctx.contains("大叔") || ctx.contains("大爷") || ctx.contains("伯伯") || ctx.contains("叔叔") || ctx.contains("少爷") || ctx.contains("儿子") || ctx.contains("他") {
            return "男性"
        }
        return "未知"
    }

    nonisolated func detectAge(in context: String) -> String {
        if context.contains("小孩") || context.contains("稚") || context.contains("孩子") || context.contains("孩童") || context.contains("幼") || context.contains("小儿") {
            return "少年"
        }
        if context.contains("少女") || context.contains("小姐") || context.contains("姑娘") || context.contains("女童") {
            return "少女"
        }
        if context.contains("少年") || context.contains("青年") || context.contains("年轻") || context.contains("小伙") || (context.contains("少") && !context.contains("多少") && !context.contains("不少")) {
            return "青年"
        }
        if context.contains("中年") || context.contains("师傅") || context.contains("大人") {
            return "中年"
        }
        if context.contains("年迈") || context.contains("老太") || context.contains("老人") || context.contains("老翁") || context.contains("老者") || context.contains("老年") {
            return "年长"
        }
        return "未知"
    }

    nonisolated func detectTone(in context: String) -> String {
        if context.contains("！") || context.contains("怒") || context.contains("大声") || context.contains("愤") {
            return "激昂"
        }
        if context.contains("？") || context.contains("疑") || context.contains("问") {
            return "疑问"
        }
        if context.contains("叹") || context.contains("轻声") || context.contains("低声") || context.contains("悲") {
            return "温柔"
        }
        if context.contains("笑") || context.contains("莞尔") || context.contains("开心") {
            return "轻松"
        }
        return "平稳"
    }

    nonisolated func styleFromTone(_ tone: String) -> String {
        switch tone {
        case "激昂": return "angry"
        case "疑问": return "neutral"
        case "温柔": return "sad"
        case "轻松": return "cheerful"
        default: return "neutral"
        }
    }

    nonisolated func defaultVoice(for gender: String, tone: String, role: String? = nil, name: String? = nil, voices: [VoiceItem]) -> String {
        if !voices.isEmpty {
            let targetGender: VoiceGender = (gender == "男") ? .male : .female
            let preferred = voices.first { $0.gender == targetGender }
            if let v = preferred { return v.id }
            return voices[0].id
        }
        switch gender {
        case "男": return "zh-CN-YunxiNeural"
        case "女": return "zh-CN-XiaoxiaoNeural"
        default:   return "zh-CN-XiaoxiaoNeural"
        }
    }

    nonisolated func voiceMatchScore(_ voice: VoiceItem, for profile: CharacterProfile) -> Int {
        var score = 0
        let targetGender: VoiceGender = (profile.gender == "男") ? .male : .female
        if voice.gender == targetGender { score += 3 }
        if voice.locale.hasPrefix("zh-CN") { score += 2 }
        if voice.styleList?.contains(profile.tone) == true { score += 1 }
        return score
    }

    nonisolated func suggestedVoices(for profile: CharacterProfile, from voiceOptions: [VoiceItem]) -> [VoiceItem] {
        voiceOptions
            .map { ($0, voiceMatchScore($0, for: profile)) }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0.0 }
    }

    func voiceSourceDescription(_ source: Any) -> String { "" }

    /// 从中文名字推测性别（启发式）
    nonisolated func guessGender(from name: String) -> Bool {
        let maleIndicators: [Character] = ["哥","爷","叔","伯","爸","弟","雄","强","刚","龙","虎","伟","勇","军","杰","涛","明","飞","浩","剑","峰","渊","恒","毅","宏"]
        let femaleIndicators: [Character] = ["妹","姐","妈","姑","姨","娘","女","花","丽","美","娜","婷","芳","娟","玲","静","淑","玉","娇","凤","燕","秀","莲","英"]
        for char in name {
            if maleIndicators.contains(char) { return true }
            if femaleIndicators.contains(char) { return false }
        }
        // 无法判断时返回 true（男性），因为网文角色比例男性偏高
        return true
    }

}

/// S15: 滑窗预取器 —— 提前发出 HTTP 请求，不等响应，结果按 index 缓存
actor AudioPrefetcher {
    private var buffer: [Int: Data] = [:]
    private var inflight: Set<Int> = []
    private var pending: [Int: CheckedContinuation<Data?, Never>] = [:]

    func prefetch(index: Int, text: String, voice: String?, rate: Double, pitch: Double, style: String) {
        guard !inflight.contains(index), buffer[index] == nil else { return }
        inflight.insert(index)
        Task { [weak self] in
            let audioData = try? await EdgeTTSService.shared.synthesize(
                text: text, voice: voice, rate: rate,
                pitch: pitch, style: style
            )
            await self?.store(index: index, audioData: audioData)
        }
    }

    func waitFor(index: Int, timeout: TimeInterval = 5) async -> Data? {
        if let cached = buffer[index] { return cached }
        guard inflight.contains(index) else { return nil }
        return await withCheckedContinuation { cont in
            pending[index] = cont
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.timeout(index: index)
            }
        }
    }

    private func timeout(index: Int) {
        guard pending[index] != nil else { return }
        inflight.remove(index)
        pending[index]?.resume(returning: nil)
        pending[index] = nil
    }

    private func store(index: Int, audioData: Data?) {
        inflight.remove(index)
        if let audioData = audioData {
            buffer[index] = audioData
        }
        // Always resume continuation (on success with data, on failure with nil)
        pending[index]?.resume(returning: audioData)
        pending[index] = nil
    }
}

private final class SpeechSynthesizerDelegateProxy: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    weak var owner: ReaderStore?

    init(owner: ReaderStore) {
        self.owner = owner
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.owner?.isSpeaking = false
        }
    }
}

