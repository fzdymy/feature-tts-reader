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

    @Published var activeServerTestResult: String = ""
    @Published var isTestingServer: Bool = false

    private var playbackTask: Task<Void, Never>?
    @Published private(set) var isStateLoaded = false

    // Lazy singleton for on-device BERT speaker detection
    nonisolated private static let bertLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _bertDetector: BertSpeakerDetector?
    nonisolated static var bertDetector: BertSpeakerDetector? {
        bertLock.withLock {
            if _bertDetector == nil {
                let d = BertSpeakerDetector()
                if d.isAvailable { _bertDetector = d }
            }
            return _bertDetector
        }
    }

    /// 测试 CosyVoice 模型是否可用
    func testActiveServer() async {
        guard !isTestingServer else { return }
        isTestingServer = true
        activeServerTestResult = "测试中..."
        do {
            try await CosyVoiceService.shared.ensureModel()
            activeServerTestResult = "CosyVoice 就绪"
        } catch {
            activeServerTestResult = "失败: \(error.localizedDescription)"
        }
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
                    self?.ttsCurrentIndex = anchor.map { $0.paragraphIndex } ?? 0
                    self?.ttsSegmentTitle = anchor.map { "段 \($0.paragraphIndex):句 \($0.sentenceIndex)" } ?? ""
                }
            }
            .store(in: &cancellables)

        audioController.$queueCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                Task { @MainActor [weak self] in
                    self?.ttsIsPlaying = count > 0
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
            self?.saveState()
        }
    }

    private func startAutoSaveTimer() {
        restartAutoSaveTimer()
    }

    func loadStateAsync() async {
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
                isStateLoaded = true
                startAutoSaveTimer()
                return
            }
            books = state.books
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
        guard isStateLoaded else { return }
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
        Task.detached {
            try? data.write(to: targetURL, options: Data.WritingOptions.atomic)
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
        let persistedBooks = persistence.fetchBooks()
        if !persistedBooks.isEmpty {
            books = persistedBooks
            loadAllTextsFromFiles()
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
    }

    private func ensureVoiceOptionsLoaded() {
        if voices.isEmpty {
            Task { await refreshVoices() }
        }
    }

    func testTTSSynthesize() async -> String {
        try? await CosyVoiceService.shared.ensureModel()
        guard await CosyVoiceService.shared.isAvailable else { return "CosyVoice 模型不可用" }
        let testText = "这是个多角色语音阅读器！"
        do {
            let audioData = try await CosyVoiceService.shared.synthesizeSingle(text: testText)
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let audioURL = cachesDir.appendingPathComponent("cosy-test-\(UUID().uuidString).wav")
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
            .unicode
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

    private func readDataWithProgress(_ url: URL, progress: @escaping (Double) -> Void) async throws -> Data {
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
                                progress(min(max(p, 0), 1))
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
        let currentVoices = voices
        let currentSensitivity = defaultSensitivity
        let targetText = chapterText ?? bookText

        let config = CharacterScanner.Config(
            maxResults: 12,
            useNLValidation: true,
            includeGraph: targetText.count > 10000
        )
        let bookID = UUID(uuidString: currentBookID)
        let scanResult = await CharacterScanner.scan(
            text: targetText, config: config, voices: currentVoices,
            defaultSensitivity: currentSensitivity, bookID: bookID
        )

        await MainActor.run {
            var final = scanResult.characters
            // Assign voices
            final = final.map { profile in
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
                if !scanResult.edges.isEmpty {
                    statusMessage += " 关系图: \(scanResult.edges.prefix(5).map { "\($0.source)-\($0.target)(\($0.weight))" }.joined(separator: ", "))"
                }
            }
            // Only replace characters for the current book; keep others intact
            characters.removeAll { $0.bookID == bookID || $0.bookID == nil }
            characters.append(contentsOf: final)
            lastScannedBookText = targetText
            updateRecommendations(from: targetText)
            saveState()
        }
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
        try? await CosyVoiceService.shared.ensureModel()
        guard await CosyVoiceService.shared.isAvailable else {
            statusMessage = "CosyVoice 模型不可用，请检查网络连接。"
            return
        }
        isBusy = true
        let text = "你好，我是 \(profile.name)，这是我的声音示例。"
        do {
            let embedding: [Float]? = profile.voiceSampleEmbedding.flatMap {
                try? JSONDecoder().decode([Float].self, from: $0)
            }
            let audioData = try await CosyVoiceService.shared.synthesizeSingle(text: text, embedding: embedding)
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let audioURL = cachesDir.appendingPathComponent("preview-\(UUID().uuidString).wav")
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
        statusMessage = "CosyVoice 无需 Azure 音色推荐。"
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

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        audioController.stop()
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        ttsIsPlaying = false
        statusMessage = "已停止播放。"
        ttsProgressMessage = ""
    }

    func startPlaybackTask(chapter: BookChapter, fromParagraph: String? = nil) {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try Task.checkCancellation()
                try await self.playChapterStreaming(chapter: chapter, fromParagraph: fromParagraph)
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { statusMessage = "朗读失败：\(error.localizedDescription)" }
                }
            }
        }
    }

    nonisolated private static let dialogueOpenQuotes: Set<Character> = ["\u{201C}", "\u{300C}", "\u{300E}", "\u{2018}"]

    private nonisolated static func hasDialogueQuote(_ s: String) -> Bool {
        dialogueOpenQuotes.contains(where: s.contains)
    }

    /// G8: 全标点断句，支持 CJK 引号结尾
    nonisolated static func splitBlockIntoSentences(_ text: String) -> [String] {
        let pattern = "[^。！？\n\r]+([。！？\n\r]\"|'|」|』|〗|”)?|[\n\r]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var sentences: [String] = []
        regex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let matchRange = match?.range, let swiftRange = Range(matchRange, in: text) {
                let sentence = text[swiftRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
            }
        }
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

    /// 逐段落流水线：高亮段落 → 识别对白 → CosyVoice 合成 → 播放
    func playChapterStreaming(chapter: BookChapter, fromParagraph: String? = nil) async throws {
        await MainActor.run {
            isBusy = true
            statusMessage = "正在朗读 \(chapter.title)..."
        }

        let paragraphs = chapter.text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !paragraphs.isEmpty else {
            await MainActor.run { statusMessage = "当前章节为空，无法朗读。" }
            return
        }

        let startParaIndex: Int
        if let paraText = fromParagraph, !paraText.isEmpty {
            startParaIndex = paragraphs.firstIndex(where: { $0.contains(paraText) || paraText.contains($0) }) ?? 0
        } else {
            startParaIndex = 0
        }

        let bookTitle = currentBookTitle.isEmpty ? "未知书籍" : currentBookTitle
        let bookUUID = UUID(uuidString: currentBookID) ?? UUID()
        let speakerEmbeddings = _speakerEmbeddings
        let speakerSamples = _speakerSamples
        // Sendable wrapper to satisfy Swift 6 concurrency checking in TaskGroup closure
        struct EmbeddingPayload: @unchecked Sendable {
            let dict: [String: [Float]]
            let samples: [String: URL]
        }
        let embedPayload = EmbeddingPayload(dict: speakerEmbeddings, samples: speakerSamples)
        let chapterIndex = chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
        let blocks = Self.buildDialogueBlocks(paragraphs)

        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let cosyDir = cachesDir.appendingPathComponent("cosy_audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: cosyDir, withIntermediateDirectories: true)

        let registry = VoiceEmbeddingRegistry.shared
        var _speakerEmbeddings: [String: [Float]] = [:]
        var _speakerSamples: [String: URL] = [:]
        for char in characters {
            if let embData = char.voiceSampleEmbedding,
               let floats = try? JSONDecoder().decode([Float].self, from: embData),
               floats.count >= 192 {
                speakerEmbeddings[char.name] = floats
                await registry.register(canonicalName: char.name, embedding: floats, sampleRate: 16000, source: .preset)
            } else if let url = char.voiceSampleURL {
                speakerSamples[char.name] = url
            }
            if !char.aliases.isEmpty {
                await registry.registerAliases(char.aliases, for: char.name)
            }
        }

        let director = DramaDirector()
        var lastSpeakerID: UUID?
        var lastEmotionTag: String?
        var previousDialogueContext: DramaDirector.SentenceContext?
        var allUpcomingSentenceContexts: [DramaDirector.SentenceContext] = []
        var lastSpeaker: String? = nil

        // Build upcoming sentence contexts for DramaDirector lookahead
        for block in blocks {
            guard block.globalStart + block.texts.count > startParaIndex else { continue }
            let pIdx = block.globalStart
            let mergedText = block.texts.joined(separator: "\n\n")
            let sentences = Self.splitBlockIntoSentences(mergedText)
            for s in sentences {
                let parts = Self.parseDialogueSegments(in: s, characters: characters, lastSpeaker: nil)
                let speaker = parts.first?.speaker ?? "叙述者"
                let canonical = characters.first(where: { $0.name == speaker || $0.aliases.contains(speaker) })?.name ?? speaker
                let profile = characters.first(where: { $0.name == canonical })
                allUpcomingSentenceContexts.append(
                    DramaDirector.SentenceContext(
                        text: s, speakerID: profile?.id,
                        emotionTag: parts.first?.emotionTag ?? "neutral",
                        isNarrator: profile?.isNarrator ?? (speaker == "叙述者" || speaker == "旁白"),
                        speed: 1.0, pitch: 1.0, paragraphIndex: pIdx
                    )
                )
            }
        }

        // Track completed items for cleanup
        let allItemsLock = OSAllocatedUnfairLock(initialState: [TTSQueueItem]())
        var upcomingContextIndex = 0

        // AsyncStream: producer side
        let stream = AsyncStream<TTSQueueItem> { continuation in
            Task {
                let semaphore = AsyncSemaphore(maxConcurrent: 3)
                await withTaskGroup(of: TTSQueueItem?.self) { group in
                    for (blockIdx, block) in blocks.enumerated() {
                        guard block.globalStart + block.texts.count > startParaIndex else { continue }
                        let pIdx = block.globalStart
                        let mergedText = block.texts.joined(separator: "\n\n")
                        let sentences = Self.splitBlockIntoSentences(mergedText)

                        for (sIdx, sentence) in sentences.enumerated() {
                            let parts = Self.parseDialogueSegments(in: sentence, characters: characters, lastSpeaker: lastSpeaker)
                            let speaker = parts.first?.speaker ?? "叙述者"
                            let canonical = characters.first(where: { $0.name == speaker || $0.aliases.contains(speaker) })?.name ?? speaker
                            let profile = characters.first(where: { $0.name == canonical })
                            let isNarrator = profile?.isNarrator ?? (speaker == "叙述者" || speaker == "旁白")
                            let speakerID = profile?.id

                            if !isNarrator { lastSpeaker = speaker }

                            let unit = SentenceUnit(
                                text: sentence, speakerID: speakerID,
                                emotionTag: parts.first?.emotionTag ?? "neutral",
                                anchor: PlaybackAnchor(
                                    bookID: bookUUID.uuidString, chapterIndex: chapterIndex,
                                    paragraphIndex: pIdx, sentenceIndex: sIdx, speakerID: speakerID
                                ),
                                estimatedDuration: 2.0, estimatedSpeed: 1.0, estimatedPitch: 1.0
                            )

                            let upcomingWindow = Array(allUpcomingSentenceContexts.dropFirst(upcomingContextIndex).prefix(5))
                            let contextWindow = DramaDirector.ContextWindow(
                                previousDialogue: previousDialogueContext,
                                upcomingSentences: upcomingWindow,
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
                            upcomingContextIndex += 1

                            let cosySegments: [(String, String, String?)] = [(canonical, sentence, refined.emotionTag)]

                            group.addTask {
                                let emb = embedPayload.dict
                                let samples = embedPayload.samples
                                await semaphore.wait()
                                defer { semaphore.signal() }

                                guard !Task.isCancelled else { return nil }

                                let audioData: Data
                                do {
                                    audioData = try await CosyVoiceService.shared.synthesizeDialogueWithEmbeddings(
                                        segments: cosySegments,
                                        speakerEmbeddings: emb,
                                        speakerSamples: samples,
                                        registry: registry
                                    )
                                } catch {
                                    await MainActor.run { self.statusMessage = "CosyVoice 合成失败，切换至系统语音" }
                                    await self.playLocalSpeech(sentence)
                                    return nil
                                }

                                let audioURL = cosyDir.appendingPathComponent("blk-\(blockIdx)-s-\(sIdx)-\(UUID().uuidString).wav")
                                try? audioData.write(to: audioURL, options: .atomic)

                                let anchor = PlaybackAnchor(
                                    bookID: bookUUID.uuidString, chapterIndex: chapterIndex,
                                    paragraphIndex: pIdx, sentenceIndex: sIdx, speakerID: speakerID
                                )

                                let seg = ScriptSegment(
                                    id: UUID(), characterName: canonical,
                                    voice: "", rate: 0, pitch: 0, style: "neutral",
                                    text: sentence, paragraphIndex: pIdx
                                )

                                let item = TTSQueueItem(
                                    segment: seg, audioURL: audioURL,
                                    chapterTitle: chapter.title, bookTitle: bookTitle,
                                    bookID: bookUUID.uuidString, chapterIndex: chapterIndex,
                                    segmentIndex: 0, totalSegments: 0,
                                    paragraphIndex: pIdx, sentenceIndex: sIdx, anchor: anchor
                                )
                                allItemsLock.withLock { $0.append(item) }
                                return item
                            }
                        }
                    }
                    for await item in group {
                        if let item { continuation.yield(item) }
                    }
                    continuation.finish()
                }
            }
        }

        // Consumer: play items as they arrive, first starts immediately
        var consumed = 0
        var isFirst = true
        for await item in stream {
            if isFirst {
                await MainActor.run {
                    ttsChapterTitle = chapter.title
                    ttsSegmentTitle = item.segment.characterName
                    ttsIsPlaying = true; isSpeaking = true
                    currentParagraphIndex = item.paragraphIndex
                    statusMessage = "朗读中..."; ttsProgressMessage = ""
                }
                audioController.playQueue([item])
                isFirst = false
            } else {
                audioController.appendToQueue([item])
            }
            consumed += 1
        }

        guard consumed > 0 else {
            await MainActor.run { statusMessage = "没有可朗读的内容。" }
            return
        }

        // Wait for playback completion
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if !audioController.isPlaying { cont.resume(); return }
            let c = audioController.$isPlaying
                .dropFirst().filter { !$0 }.first()
                .sink { _ in cont.resume() }
            playbackContinuationCancellable = c
        }
        playbackContinuationCancellable = nil

        let files = allItemsLock.withLock { $0 }
        DispatchQueue.global(qos: .utility).async {
            for item in files { try? FileManager.default.removeItem(at: item.audioURL) }
        }

        await MainActor.run {
            isSpeaking = false; isBusy = false; ttsIsPlaying = false
            if !Task.isCancelled { statusMessage = "已播放完毕。" }
            ttsProgressMessage = ""
        }
    }

    func playChapterWithTTS(chapter: BookChapter, fromParagraph: String? = nil) async {
        await MainActor.run { statusMessage = "正在准备朗读章节..." }
        do {
            try await playChapterStreaming(chapter: chapter, fromParagraph: fromParagraph)
        } catch {
            await MainActor.run { statusMessage = "朗读失败: \(error.localizedDescription)" }
        }
    }

    private func playLocalSpeech(_ text: String) async {
        stopPlayback()
        isSpeaking = true
        statusMessage = "正在使用系统语音朗读..."

        let textBlocks = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
        let config = CharacterScanner.Config(
            maxResults: 12,
            useNLValidation: true,
            includeGraph: false
        )
        let result = await CharacterScanner.scan(
            text: text, config: config, voices: voices,
            defaultSensitivity: defaultSensitivity
        )
        // Assign voices to non-narrator characters
        return result.characters.map { profile in
            var p = profile
            if p.voice.isEmpty {
                p.voice = defaultVoice(for: p.gender, tone: p.tone, name: p.name, voices: voices)
            }
            return p
        }
    }

    nonisolated func createScriptSegments(from text: String, characters: [CharacterProfile], defaultSensitivity: Int, voices: [VoiceItem], defaultMaleVoiceID: String = "", defaultFemaleVoiceID: String = "", defaultFallbackRateOffset: Int = 0, defaultFallbackPitchOffset: Int = 0, defaultFallbackStyle: String = "neutral") -> [ScriptSegment] {
        // Reset BERT profiles for this chapter
        Self.bertDetector?.resetProfiles()

        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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

    /// Map internal tone names (from analyzeSentenceTone) to CosyVoice emotion tags.
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

            // BERT primary: run once and use for disambiguation
            var bertResult: (name: String?, score: Float) = (nil, 0)
            if let bert = Self.bertDetector, !mergedContext.isEmpty {
                bertResult = bert.detectSpeaker(context: mergedContext, quote: quoteText, candidates: characters.map(\.name))
            }

            // Regex speaker detection
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

            // Decide: BERT primary with regex tiebreaker
            if bertResult.score > 0.7 {
                speaker = bertResult.name
            } else if bertResult.score > 0.5, regexSpeaker != nil {
                speaker = regexSpeaker
            } else if bertResult.score > 0.5 {
                speaker = bertResult.name
            } else if regexSpeaker != nil {
                speaker = regexSpeaker
            } else if bertResult.score > 0.4 {
                speaker = bertResult.name
            }

            // If still not found, look for vocative inside the quote
            if speaker == nil {
                for ch in characters {
                    let name = ch.name
                    if quoteText.hasPrefix("\(name)，") || quoteText.hasPrefix("\(name),") || quoteText.hasPrefix(name) {
                        speaker = name
                        break
                    }
                }
            }

            let resolvedSpeaker = speaker ?? currentLastSpeaker ?? narratorName
            currentLastSpeaker = resolvedSpeaker

            // Update BERT profile for high-confidence detections
            if speaker != nil, let bert = Self.bertDetector, !mergedContext.isEmpty, resolvedSpeaker != narratorName {
                let profileText = mergedContext + " [SEP] " + quoteText
                bert.updateProfile(for: resolvedSpeaker, from: profileText)
            }

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
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await playChapterStreaming(chapter: chapter, fromParagraph: trimmed.isEmpty ? nil : trimmed)
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
            let embedding: [Float]? = nil
            let audioData = try await CosyVoiceService.shared.synthesizeSingle(text: first.text, embedding: embedding)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-test-\(UUID().uuidString).wav")
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
        ""
    }

    nonisolated func voiceMatchScore(_ voice: VoiceItem, for profile: CharacterProfile) -> Int { 0 }

    nonisolated func suggestedVoices(for profile: CharacterProfile, from voiceOptions: [VoiceItem]) -> [VoiceItem] {
        []
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
    
private final class SpeechSynthesizerDelegateProxy: NSObject, AVSpeechSynthesizerDelegate {
    weak var owner: ReaderStore?

    init(owner: ReaderStore) {
        self.owner = owner
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            owner?.isSpeaking = false
        }
    }
}

