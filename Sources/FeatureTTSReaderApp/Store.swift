import Foundation
import Combine
import AVFoundation
import SwiftUI
import MediaPlayer
import NaturalLanguage

@MainActor
struct ChapterNavigate: Equatable {
    let bookID: UUID
    let chapterIndex: Int
}

final class ReaderStore: NSObject, ObservableObject, @unchecked Sendable {
    @Published var navigationPath: NavigationPath = NavigationPath()
    @Published var bookText: String = ""
    @Published var chapters: [BookChapter] = []
    @Published var characters: [CharacterProfile] = []
    @Published var scriptSegments: [ScriptSegment] = []
    @Published var voices: [VoiceItem] = []
    @Published var selectedVoiceCatalog: VoiceCatalogSource = .chinese35
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

    // Lazy singleton for on-device BERT speaker detection
    nonisolated private static let bertLock = NSLock()
    nonisolated(unsafe) private static var _bertDetector: BertSpeakerDetector?
    nonisolated static var bertDetector: BertSpeakerDetector? {
        bertLock.lock()
        defer { bertLock.unlock() }
        if _bertDetector == nil {
            let d = BertSpeakerDetector()
            if d.isAvailable { _bertDetector = d }
        }
        return _bertDetector
    }

    /// 测试 CosyVoice 模型是否可用
    func testActiveServer() async {
        await MainActor.run {
            isTestingServer = true
            activeServerTestResult = "测试中..."
        }
        do {
            try await CosyVoiceService.shared.ensureModel()
            await MainActor.run { activeServerTestResult = "CosyVoice 就绪" }
        } catch {
            await MainActor.run { activeServerTestResult = "失败: \(error.localizedDescription)" }
        }
        await MainActor.run { isTestingServer = false }
    }

    // Chapter parse cache keyed by book ID
    var bookChaptersCache: [UUID: [BookChapter]] = [:]

    func chaptersForBook(_ bookID: UUID, text: String) -> [BookChapter] {
        if let cached = bookChaptersCache[bookID] { return cached }
        guard !text.isEmpty else { return [] }
        let parsed = Self.extractChapters(from: text)
        if !parsed.isEmpty {
            bookChaptersCache[bookID] = parsed
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

    let audioController = AudioPlaybackController()
    private let persistence = PersistenceController.shared
    private let speechSynthesizer = AVSpeechSynthesizer()
    private lazy var speechDelegate = SpeechSynthesizerDelegateProxy(owner: self)
    private var autoSaveTimer: Timer?

    override init() {
        Self.writeCrashMarker("init_start")
        super.init()
        Self.writeCrashMarker("init_super_done")
        speechSynthesizer.delegate = speechDelegate
        Self.writeCrashMarker("init_speech_delegate_done")
        voices = selectedVoiceCatalog.voices
        Self.writeCrashMarker("init_voices_done")
        setupAudioSession()
        Self.writeCrashMarker("init_audio_session_done")
        setupRemoteCommands()
        Self.writeCrashMarker("init_remote_commands_done")
        observeAudioController()
        Self.writeCrashMarker("init_observe_done")
        audioController.restorePlaybackState()
        Self.writeCrashMarker("init_restore_playback_done")
        startAutoSaveTimer()
        Self.writeCrashMarker("init_timer_done")

        // Restore reading position from UserDefaults (tiny, <1KB) so "继续阅读" works immediately
        if let data = UserDefaults.standard.data(forKey: "lastReadChapterIndexByBook"),
           let map = try? JSONDecoder().decode([UUID: Int].self, from: data) {
            lastReadChapterIndexByBook = map
        }
        Self.writeCrashMarker("init_userdefaults_done")

        // Full state loaded async to avoid blocking UI with ~40MB JSON decode
        Task {
            Self.writeCrashMarker("task_loadState_start")
            await loadStateAsync()
            Self.writeCrashMarker("task_loadState_done")
        }

        // Pre-warm CosyVoice model so playback doesn't trigger first-time download
        Self.writeCrashMarker("init_before_prewarm")
        CosyVoiceService.prewarm()
        Self.writeCrashMarker("init_after_prewarm")
    }

    /// Write a crash marker to a file in Documents directory + UserDefaults.
    /// The last written marker before the crash pinpoints the culprit.
    nonisolated static func writeCrashMarker(_ marker: String) {
        // UserDefaults (fast, survives most crashes)
        UserDefaults.standard.set(marker, forKey: "last_crash_marker")

        // File in Documents (accessible via file browser for self-signed installs)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let url = docs?.appendingPathComponent("crash_marker.txt") {
            let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let line = "\(ts) \(marker)\n"
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.synchronize()  // Force fsync
                    handle.closeFile()
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .allowAirPlay, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Logger.log(error: error)
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.audioController.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.audioController.pause()
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.audioController.stop()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.audioController.playNext()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.audioController.playPrevious()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.audioController.seek(to: event.positionTime)
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.audioController.seekForward(15)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.audioController.seekBackward(15)
            return .success
        }
    }

    private func observeAudioController() {
        // Observe audio controller state changes and sync with published properties
        audioController.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] isPlaying in
                self?.ttsIsPlaying = isPlaying
                self?.isSpeaking = isPlaying
            }
            .store(in: &cancellables)

        audioController.$currentProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.playProgress = progress
            }
            .store(in: &cancellables)

        audioController.$currentIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] index in
                self?.ttsCurrentIndex = index
            }
            .store(in: &cancellables)

        audioController.$currentTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                self?.ttsSegmentTitle = title
            }
            .store(in: &cancellables)

        audioController.$queue
            .receive(on: RunLoop.main)
            .sink { [weak self] queue in
                self?.ttsQueue = queue
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

    private func loadStateAsync() async {
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
                return
            }
            books = state.books
            chapters = state.chapters
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
            selectedVoiceCatalog = state.selectedVoiceCatalog
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
                lastReadChapterIndexByBook = udMap
            } else if !state.lastReadChapterIndexByBook.isEmpty {
                lastReadChapterIndexByBook = state.lastReadChapterIndexByBook
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

        }
    }

    func loadState() {
        Task { await loadStateAsync() }
    }

    func restoreState(_ state: ReaderState) {
        saveAllTextsToFiles()
        chapters = state.chapters
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
        selectedVoiceCatalog = state.selectedVoiceCatalog
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
            selectedVoiceCatalog: selectedVoiceCatalog,
            defaultVoice: characters.first?.voice ?? "zh-CN-XiaoxiaoNeural",
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

        let inferred = await Task.detached { [targetText, currentVoices, currentSensitivity, weak self] in
            return self?.inferCharacters(from: targetText, voices: currentVoices, defaultSensitivity: currentSensitivity) ?? []
        }.value

        await MainActor.run {
            var final = inferred
            if final.isEmpty {
                final = [CharacterProfile(id: UUID(), name: "叙述者", gender: "未知", age: "未知", tone: "中性", voice: defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: voices), rate: 0, pitch: 0, style: "neutral", sensitivity: defaultSensitivity)]
                statusMessage = "未识别到明确人物，已创建默认叙述者。"
            } else {
                final = final.map { profile in
                    var updated = profile
                    if updated.voice.isEmpty {
                        updated.voice = defaultVoice(for: profile.gender, tone: profile.tone, name: profile.name, voices: voices)
                    }
                    return updated
                }
                statusMessage = "已识别 \(final.count) 个角色。"
            }
            characters = final
            lastScannedBookText = targetText
            updateRecommendations(from: targetText)

            if targetText.count > 10000 {
                // Include aliases in graph name set (counts map to canonical)
                let graphNames = characters.flatMap { [$0.name] + $0.aliases }
                let edges = CharacterAnalyzer().buildRelationshipGraph(text: targetText, characterNames: graphNames)
                if !edges.isEmpty {
                    statusMessage = (statusMessage ?? "") + " 关系图: \(edges.prefix(5).map { "\($0.source)-\($0.target)(\($0.weight))" }.joined(separator: ", "))"
                }
            }

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
                  let cached = bookChaptersCache[bookID],
                  let chapter = cached.first(where: { $0.id == selectedChapterID }) {
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

    func switchCatalog(to source: VoiceCatalogSource) {
        selectedVoiceCatalog = source
        voices = source.voices
        statusMessage = "已加载音色目录：\(source.displayName)，共 \(voices.count) 个音色。"
        saveState()
    }

    func refreshVoices() async {
        switchCatalog(to: selectedVoiceCatalog)
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

    func applyVoice(_ voiceID: String, toCharacterID id: UUID) {
        guard let index = characters.firstIndex(where: { $0.id == id }) else { return }
        characters[index].voice = voiceID
        statusMessage = "角色 \(characters[index].name) 已应用音色 \(voiceID)。"
        updateRecommendations()
        saveState()
    }

    func applyRecommendationsToUnmapped() {
        for rec in recommendations {
            if let idx = characters.firstIndex(where: { $0.id == rec.profile.id }) {
                let current = characters[idx].voice
                // if voice is default or empty, apply suggestion
                if current.isEmpty || current == defaultVoice(for: characters[idx].gender, tone: characters[idx].tone, voices: voices) {
                    if let v = rec.suggestedVoices.first?.id {
                        characters[idx].voice = v
                    }
                }
            }
        }
        statusMessage = "已为未映射角色应用推荐音色。"
        saveState()
    }

    func autoApplyRecommendedToAll() {
        for rec in recommendations {
            if let idx = characters.firstIndex(where: { $0.id == rec.profile.id }) {
                if let v = rec.suggestedVoices.first?.id {
                    characters[idx].voice = v
                }
            }
        }
        statusMessage = "已为所有角色批量应用推荐音色。"
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
              let bookID = UUID(uuidString: currentBookID),
              let chapters = bookChaptersCache[bookID],
              let chapter = chapters.first(where: { $0.id == chapterID }) else {
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
        let chapters = UUID(uuidString: currentBookID).flatMap { bookChaptersCache[$0] } ?? []
        guard !chapters.isEmpty else {
            await MainActor.run { statusMessage = "未找到章节。" }
            return
        }
        for chapter in chapters {
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

    /// Group paragraphs into dialogue blocks: merge consecutive paragraphs containing quotes,
    /// splitting only after 2 consecutive non-quote paragraphs.
    private static func buildDialogueBlocks(_ paragraphs: [String]) -> [(texts: [String], globalStart: Int)] {
        var blocks: [(texts: [String], globalStart: Int)] = []
        var i = 0
        while i < paragraphs.count {
            // Skip leading non-quote paragraphs
            if !paragraphs[i].contains("\u{201C}") && !paragraphs[i].contains("\u{300C}") {
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
                let hasQuote = paragraphs[i].contains("\u{201C}") || paragraphs[i].contains("\u{300C}")
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

    /// 逐段落流水线：高亮段落 → 识别对白 → 匹配音色 → 发送TTS → 播放 → 下一段落
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
        let bookID = UUID(uuidString: currentBookID) ?? UUID()
        let chapterIndex = chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
        var lastSpeaker: String? = nil
        let blocks = Self.buildDialogueBlocks(paragraphs)

        // Build speaker samples map (safe unwrap, no data race)
        var speakerSamples: [String: URL] = [:]
        for char in characters {
            guard let url = char.voiceSampleURL else { continue }
            speakerSamples[char.name] = url
        }

        for (blockIdx, block) in blocks.enumerated() {
            try Task.checkCancellation()
            guard block.globalStart >= startParaIndex else {
                if block.globalStart + block.texts.count > startParaIndex { }
                continue
            }

            await MainActor.run { currentParagraphIndex = block.globalStart }

            let mergedText = block.texts.joined(separator: "\n\n")
            let dialogueParts = Self.parseDialogueSegments(in: mergedText, characters: characters, lastSpeaker: lastSpeaker)
            guard !dialogueParts.isEmpty else { continue }

            if let lastPart = dialogueParts.last, lastPart.speaker != "叙述者" && lastPart.speaker != "旁白" {
                lastSpeaker = lastPart.speaker
            }

            // CosyVoice 合成整个 block
            let cosySegments: [(speaker: String, text: String, emotion: String?)] = dialogueParts.map {
                ($0.speaker, $0.text, $0.emotionTag)
            }

            let audioData: Data
            do {
                audioData = try await CosyVoiceService.shared.synthesizeDialogue(
                    segments: cosySegments,
                    speakerSamples: speakerSamples
                )
            } catch {
                await MainActor.run { statusMessage = "CosyVoice 合成失败，切换至系统语音" }
                await playLocalSpeech(mergedText)
                continue
            }

            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let cosyDir = cachesDir.appendingPathComponent("cosy_audio", isDirectory: true)
            try? FileManager.default.createDirectory(at: cosyDir, withIntermediateDirectories: true)
            let audioURL = cosyDir.appendingPathComponent("block-\(blockIdx)-\(UUID().uuidString).wav")
            try audioData.write(to: audioURL, options: .atomic)

            let seg = ScriptSegment(
                id: UUID(),
                characterName: dialogueParts.first?.speaker ?? "叙述者",
                voice: "", rate: 0, pitch: 0, style: "neutral",
                text: dialogueParts.map(\.text).joined(separator: " ")
            )
            let item = TTSQueueItem(
                segment: seg, audioURL: audioURL,
                chapterTitle: chapter.title, bookTitle: bookTitle,
                bookID: bookID.uuidString, chapterIndex: chapterIndex,
                segmentIndex: blockIdx, totalSegments: blocks.count
            )

            await MainActor.run {
                ttsChapterTitle = chapter.title
                ttsSegmentTitle = dialogueParts.first?.speaker ?? ""
                ttsIsPlaying = true; isSpeaking = true
                statusMessage = "朗读区块 \(blockIdx + 1)/\(blocks.count)"
            }
            audioController.playQueue([item])

            if audioController.isPlaying {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    let c = audioController.$isPlaying
                        .filter { !$0 }
                        .first()
                        .sink { _ in cont.resume() }
                    playbackContinuationCancellable = c
                }
                playbackContinuationCancellable = nil
            }

            DispatchQueue.global(qos: .utility).async {
                try? FileManager.default.removeItem(at: audioURL)
            }
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


    nonisolated func inferCharacters(from text: String, voices: [VoiceItem], defaultSensitivity: Int) -> [CharacterProfile] {
        let raw = text.replacingOccurrences(of: "\r", with: "\n")
        var names = OrderedSet<String>()

        let analyzer = CharacterAnalyzer()
        let candidates = analyzer.extractDialogueNames(from: raw)
        var candidateScores: [String: Int] = [:]
        for n in candidates { candidateScores[n, default: 0] += 1 }
        let scores = analyzer.countWithAC(text: raw, candidates: candidateScores)
        let sorted = scores.keys.sorted { scores[$0, default: 0] > scores[$1, default: 0] }
        for n in sorted {
            let freq = scores[n, default: 0]
            // High-frequency names (>10) get a relaxed surname check
            let accepted = CharacterAnalyzer.looksLikeRealName(n) ||
                CharacterAnalyzer.titleSuffixes.contains(where: { n.hasSuffix($0) }) ||
                (freq >= 10 && n.count >= 2 && n.count <= 4 && !analyzer.isStopWord(n))
            guard accepted else { continue }
            names.append(n)
        }

        // Validate candidates with Apple NL tagger (filters common-word false positives)
        let nlValidated = analyzer.validateWithNL(text: raw, candidates: Set(names))
        if !nlValidated.isEmpty {
            names = OrderedSet(names.filter { nlValidated.contains($0) })
        }

        // Resolve aliases: 无忌 → 张无忌, 张公子 → 张无忌, etc.
        let resolved = CharacterAnalyzer.resolveAliases(Array(names))
        let allAliases = Set(resolved.flatMap { $0.aliases })
        let canonicalNames = resolved.map { $0.canonical }.filter { !allAliases.contains($0) }

        // Analyze narrator patterns - text that is not dialogue
        let narratorIndicators = detectNarratorPatterns(in: raw)

        var result: [CharacterProfile] = []
        for resolvedName in resolved.prefix(12) {
            let name = resolvedName.canonical
            let aliases = resolvedName.aliases
            let context = raw.contextAround(name, radius: 120)
            let attrs = analyzer.analyzeAttributes(for: name, context: context)

            // Detect if this is likely a narrator
            let isNarrator = isLikelyNarrator(name: name, context: context, narratorIndicators: narratorIndicators)
            let role: CharacterRole = isNarrator ? .narrator : .character

            let assignedVoice: String
            if isNarrator {
                assignedVoice = defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: voices)
            } else {
                assignedVoice = defaultVoice(for: attrs.gender, tone: attrs.baseTone, voices: voices)
            }

            result.append(CharacterProfile(
                id: UUID(),
                name: name,
                aliases: aliases,
                gender: attrs.gender,
                age: attrs.age,
                tone: attrs.baseTone,
                voice: assignedVoice,
                rate: attrs.baseRate,
                pitch: attrs.basePitch,
                style: attrs.baseStyle,
                sensitivity: defaultSensitivity,
                isNarrator: isNarrator,
                role: role
            ))
        }

        // If no characters found, add a default narrator
        if result.isEmpty {
            result.append(CharacterProfile(
                id: UUID(),
                name: "旁白",
                gender: "未知",
                age: "未知",
                tone: "平稳",
                voice: defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: voices),
                rate: 0,
                pitch: 0,
                style: "neutral",
                sensitivity: defaultSensitivity,
                isNarrator: true,
                role: .narrator
            ))
        }

        // Ensure at least one narrator exists
        if !result.contains(where: { $0.isNarrator }) {
            result.insert(CharacterProfile(
                id: UUID(),
                name: "旁白",
                gender: "未知",
                age: "未知",
                tone: "平稳",
                voice: defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: voices),
                rate: 0,
                pitch: 0,
                style: "neutral",
                sensitivity: defaultSensitivity,
                isNarrator: true,
                role: .narrator
            ), at: 0)
        }

        return result
    }

    nonisolated func createScriptSegments(from text: String, characters: [CharacterProfile], defaultSensitivity: Int, voices: [VoiceItem], defaultMaleVoiceID: String = "", defaultFemaleVoiceID: String = "", defaultFallbackRateOffset: Int = 0, defaultFallbackPitchOffset: Int = 0, defaultFallbackStyle: String = "neutral") -> [ScriptSegment] {
        // Reset BERT profiles for this chapter
        Self.bertDetector?.resetProfiles()

        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var segments: [ScriptSegment] = []
        var lastSpeaker: String? = nil
        let maxLength = 350
        let blocks = Self.buildDialogueBlocks(paragraphs)

        for (_, block) in blocks.enumerated() {
            let mergedText = block.texts.joined(separator: "\n\n")
            let dialogueParts = Self.parseDialogueSegments(in: mergedText, characters: characters, lastSpeaker: lastSpeaker)

            // Update cross-block speaker tracking (skip narrator)
            if let lastPart = dialogueParts.last, lastPart.speaker != "叙述者" && lastPart.speaker != "旁白" {
                lastSpeaker = lastPart.speaker
            }

            for part in dialogueParts {
                let chunks = part.text.chunked(into: maxLength)
                for chunk in chunks {
                    let analyzer = CharacterAnalyzer()
                    let speakerProfile = characters.first(where: { $0.name == part.speaker || $0.aliases.contains(part.speaker) })
                    let toneResult = analyzer.analyzeSentenceTone(chunk)
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

    private static let quotePairs: [(open: Character, close: Character)] = [
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
                // Check if quote starts with a character name + comma/vocative
                for ch in characters {
                    let name = ch.name
                    if quoteText.hasPrefix("\(name)，") || quoteText.hasPrefix("\(name),") || quoteText.hasPrefix(name) {
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
    private static func findChar(_ chars: [Character], _ ch: Character, from: Int) -> Int? {
        for i in from..<chars.count {
            if chars[i] == ch { return i }
        }
        return nil
    }

    /// Find the matching closing quote, handling nesting of the same quote type.
    private static func findQuoteClose(_ chars: [Character], openChar: Character, closeChar: Character, from: Int) -> Int? {
        // Simple approach: find the next closing char. In practice, Chinese web novels
        // rarely nest quotes of the same type, so linear search is sufficient.
        for i in from..<chars.count {
            if chars[i] == closeChar { return i }
        }
        return nil
    }

    /// Detect speaker from context BEFORE a quote (e.g. "陈煜笑道：「...").
    /// 按照文章顺序：优先从最近的上文中匹配角色名。
    private static func detectSpeakerInContext(_ context: String, characters: [CharacterProfile]) -> String? {
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
    private static func detectSpeakerAfterQuote(_ context: String, characters: [CharacterProfile]) -> String? {
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
        let chapters = UUID(uuidString: currentBookID).flatMap { bookChaptersCache[$0] } ?? []
        guard let chapter = chapters.first(where: { $0.id == selectedChapterID }) else {
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
        let options = voices.isEmpty ? VoiceItem.defaultItems() : voices
        
        // For narrator, prefer neutral, clear voices
        if role == "旁白" || role == "narrator" {
            let narratorVoices = options.filter { $0.id.contains("Xiaoxiao") || $0.id.contains("Yunjian") || $0.id.contains("Yunxi") }
            let profile = CharacterProfile(id: UUID(), name: name ?? "旁白", gender: "未知", age: "未知", tone: "平稳", voice: "", rate: 0, pitch: 0, style: "neutral", sensitivity: 50, isNarrator: true, role: .narrator)
            let best = (narratorVoices.isEmpty ? options : narratorVoices).max(by: { voiceMatchScore($0, for: profile) < voiceMatchScore($1, for: profile) })
            return best?.id ?? "zh-CN-XiaoxiaoNeural"
        }
        
        let profile = CharacterProfile(id: UUID(), name: name ?? "叙述者", gender: gender, age: "未知", tone: tone, voice: "", rate: 0, pitch: 0, style: "neutral", sensitivity: 50, isNarrator: false, role: .character)
        let best = options.max(by: { voiceMatchScore($0, for: profile) < voiceMatchScore($1, for: profile) })
        return best?.id ?? "zh-CN-XiaoxiaoNeural"
    }

    nonisolated func voiceMatchScore(_ voice: VoiceItem, for profile: CharacterProfile) -> Int {
        var score = 0
        let lowerID = voice.id.lowercased()
        let lowerName = voice.name.lowercased()
        let locale = voice.locale.lowercased()
        let voiceTraits = VoiceCatalog.traits[voice.id] ?? []
        let voiceTier = VoiceCatalog.tier(for: voice.id)

        // 音质等级加分：主角/旁白优先使用高等级音色
        if profile.role == .narrator || profile.isNarrator {
            score += voiceTier.rawValue * 8
        }
        if voiceTraits.contains("男主角") || voiceTraits.contains("女主角") {
            score += voiceTier.rawValue * 5 + 5
        }

        // 角色身份标签匹配
        if voiceTraits.contains("旁白") && (profile.role == .narrator || profile.isNarrator) {
            score += 30
        }
        if voiceTraits.contains("反派") && profile.tone == "激昂" {
            score += 15
        }

        // 性别匹配
        if profile.gender == "女性" {
            if lowerID.contains("xiao") || lowerName.contains("小") || lowerName.contains("xia") || voiceTraits.contains("女主角") || voiceTraits.contains("女配角") { score += 25 }
            if !lowerID.contains("yun") && !lowerName.contains("云") { score += 5 }
        } else if profile.gender == "男性" {
            if lowerID.contains("yun") || lowerName.contains("云") || voiceTraits.contains("男主角") || voiceTraits.contains("男配角") { score += 25 }
            if !lowerID.contains("xiao") && !lowerName.contains("小") { score += 5 }
        }

        // 语气匹配
        if profile.tone == "温柔" || profile.tone == "轻松" {
            if lowerID.contains("xiao") || lowerName.contains("晓") || lowerName.contains("柔") || voiceTraits.contains("温柔") || voiceTraits.contains("治愈") || voiceTraits.contains("温婉") { score += 15 }
        }
        if profile.tone == "激昂" {
            if let styles = voice.styleList, styles.contains(where: { $0.contains("angry") || $0.contains("excited") || $0.contains("strong") || $0.contains("loud") }) { score += 12 }
            if voiceTraits.contains("激昂") || voiceTraits.contains("战斗型") { score += 10 }
        }
        if profile.tone == "疑问" {
            if let styles = voice.styleList, styles.contains(where: { $0.contains("chat") || $0.contains("assistant") || $0.contains("question") }) { score += 8 }
        }
        if profile.tone == "平稳" {
            score += 5
        }

        // 年龄/风格匹配
        if voiceTraits.contains("萝莉") || voiceTraits.contains("少女") { score += (profile.age == "少年" || profile.age == "少女" ? 10 : 2) }
        if voiceTraits.contains("少年感") || voiceTraits.contains("阳光") { score += (profile.age == "少年" || profile.age == "青年" ? 10 : 3) }
        if voiceTraits.contains("成熟大叔") || voiceTraits.contains("沉稳") { score += (profile.age == "中年" || profile.age == "年长" ? 10 : 2) }

        // 方言/地域匹配
        if voiceTraits.contains("东北话") || voiceTraits.contains("四川话") || voiceTraits.contains("河南话") || voiceTraits.contains("山东话") || voiceTraits.contains("陕西话") || voiceTraits.contains("广西话") || voiceTraits.contains("粤语") || voiceTraits.contains("吴语") || voiceTraits.contains("台普") {
            score += 8
        }

        if locale.contains("zh") { score += 5 }
        if let styles = voice.styleList, styles.contains("chat") { score += 3 }

        if let name = profile.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            if lowerID.contains(name.lowercased()) || lowerName.contains(name.lowercased()) { score += 15 }
        }

        // Traits 标签综合加分
        for trait in voiceTraits {
            if trait == "元気" || trait == "活泼" || trait == "元气" { score += (profile.tone == "轻松" ? 8 : 2) }
            if trait == "知性" || trait == "职业" { score += (profile.tone == "平稳" ? 8 : 2) }
            if trait == "高冷" { score += (profile.tone == "平稳" || profile.tone == "疑问" ? 8 : 2) }
            if trait == "磁性" || trait == "浑厚" { score += (profile.age == "中年" || profile.age == "年长" ? 8 : 3) }
        }

        return score
    }

    nonisolated func suggestedVoices(for profile: CharacterProfile, from voiceOptions: [VoiceItem]) -> [VoiceItem] {
        var list = voiceOptions
        list.sort { voiceMatchScore($0, for: profile) > voiceMatchScore($1, for: profile) }
        return Array(list.prefix(6))
    }

    func voiceSourceDescription(_ source: VoiceCatalogSource) -> String {
        source.displayName
    }

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

