import Foundation
import Combine
import AVFoundation
import SwiftUI
import MediaPlayer

@MainActor
final class ReaderStore: NSObject, ObservableObject {
    @Published var bookText: String = ""
    @Published var chapters: [BookChapter] = []
    @Published var characters: [CharacterProfile] = []
    @Published var scriptSegments: [ScriptSegment] = []
    @Published var voices: [VoiceItem] = []
    @Published var selectedVoiceCatalog: VoiceCatalogSource = .remote
    @Published var recommendations: [CharacterRecommendation] = []
    @Published var selectedChapterID: UUID?
    @Published var statusMessage: String = "请导入小说或粘贴文本。"
    @Published var isBusy: Bool = false
    @Published var importProgress: Double = 0.0
    @Published var currentPlayingLine: String = ""
    @Published var apiKey: String = ""
    @Published var apiEndpoint: String = "http://127.0.0.1:8080"
    @Published var playProgress: Double = 0.0
    @Published var books: [Book] = []
    @Published var currentBookTitle: String = ""
    @Published var currentBookID: String = UUID().uuidString
    @Published var currentBookProgress: Double = 0.0
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

// TTS Synthesis Cache
    private var ttsCache: [String: URL] = [:]

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
    @Published var bookmarks: [BookBookmark] = []
    @Published var bookProgressByChapter: [UUID: Double] = [:]
    @Published var lastReadChapterIndexByBook: [UUID: Int] = [:]
    @Published var defaultSensitivity: Int = 50
    @Published var defaultRate: Int = 0
    @Published var defaultPitch: Int = 0
    @Published var defaultStyle: String = "neutral"
    @Published var defaultSortOption: SortOption = .recent

    private let audioController = AudioPlaybackController()
    private let persistence = PersistenceController.shared
    private let speechSynthesizer = AVSpeechSynthesizer()
    private lazy var speechDelegate = SpeechSynthesizerDelegateProxy(owner: self)
    private var client: TTSHttpClient { TTSHttpClient(baseURL: URL(string: apiEndpoint) ?? URL(string: "http://127.0.0.1:8080")!, apiKey: apiKey.isEmpty ? nil : apiKey) }

    override init() {
        super.init()
        speechSynthesizer.delegate = speechDelegate
        loadSettings()
        setupAudioSession()
        setupRemoteCommands()
        observeAudioController()
        audioController.restorePlaybackState()

        // Load state off the main actor to avoid blocking UI on startup
        Task.detached { [weak self] in
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let url = docs.appendingPathComponent("tts_reader_state.json")
            if let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(ReaderState.self, from: data) {
                await MainActor.run {
                    guard let strong = self else { return }
                    strong.bookText = state.bookText
                    strong.chapters = state.chapters
                    strong.characters = state.characters
                    strong.scriptSegments = state.scriptSegments
                    strong.selectedVoiceCatalog = state.selectedVoiceCatalog
                    strong.recommendations = state.recommendations ?? []
                    strong.selectedChapterID = state.selectedChapterID
                    strong.statusMessage = state.statusMessage
                    strong.isBusy = state.isBusy
                    strong.currentPlayingLine = state.currentPlayingLine
                    strong.apiKey = state.apiKey
                    strong.apiEndpoint = state.apiEndpoint
                    strong.playProgress = state.playProgress
                    strong.books = state.books
                    strong.currentBookTitle = state.currentBookTitle
                    strong.currentBookID = state.currentBookID
                    strong.currentBookProgress = state.currentBookProgress
                    strong.isSpeaking = state.isSpeaking
                    strong.readerFontSize = state.readerFontSize
                    strong.readerLineSpacing = state.readerLineSpacing
                    strong.readerParagraphSpacing = state.readerParagraphSpacing
                    strong.readerTheme = state.readerTheme
                    strong.readerFontName = state.readerFontName
                    strong.customBackgroundImage = state.customBackgroundImage
                    strong.showChapterTitle = state.showChapterTitle
                    strong.showProgressBar = state.showProgressBar
                    strong.showPageNumber = state.showPageNumber
                    strong.showTime = state.showTime
                    strong.showBattery = state.showBattery
                    strong.showBookCover = state.showBookCover
                    strong.showReadingProgress = state.showReadingProgress
                    strong.bookmarks = state.bookmarks
                    strong.bookProgressByChapter = state.bookProgressByChapter
                    strong.lastReadChapterIndexByBook = state.lastReadChapterIndexByBook
                    strong.defaultSensitivity = state.defaultSensitivity
                    strong.lastScannedBookText = state.lastScannedBookText
                    strong.playTimeoutSeconds = state.playTimeoutSeconds

                    // Restore TTS queue state
                    strong.ttsQueue = state.ttsQueue ?? []
                    strong.ttsCurrentIndex = state.ttsCurrentIndex ?? 0
                    strong.ttsIsPlaying = state.ttsIsPlaying ?? false
                    strong.ttsChapterTitle = state.ttsChapterTitle ?? ""
                    strong.ttsSegmentTitle = state.ttsSegmentTitle ?? ""
                }
            } else {
                await MainActor.run {
                    self?.loadPersistentLibrary()
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

        audioController.$currentTime
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                self?.ttsCurrentTime = time
            }
            .store(in: &cancellables)

        audioController.$currentDuration
            .receive(on: RunLoop.main)
            .sink { [weak self] duration in
                self?.ttsDuration = duration
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
}

    private var cancellables = Set<AnyCancellable>()

    func loadSettings() {
        apiEndpoint = UserDefaults.standard.string(forKey: "ReaderStore.apiEndpoint") ?? apiEndpoint
        apiKey = UserDefaults.standard.string(forKey: "ReaderStore.apiKey") ?? apiKey
    }

    func saveSettings() {
        UserDefaults.standard.set(apiEndpoint, forKey: "ReaderStore.apiEndpoint")
        UserDefaults.standard.set(apiKey, forKey: "ReaderStore.apiKey")
        // also persist to state file so settings survive app restarts
        saveState()
    }

    func loadState() {
        let url = stateFileURL()
        guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(ReaderState.self, from: data) else {
            loadPersistentLibrary()
            return
        }
        bookText = state.bookText
        chapters = state.chapters
        characters = state.characters
        scriptSegments = state.scriptSegments
        selectedChapterID = state.selectedChapterID
        apiEndpoint = state.apiEndpoint
        apiKey = state.apiKey
        books = state.books
        currentBookTitle = state.currentBookTitle
        currentBookID = state.currentBookID
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
        lastScannedBookText = state.lastScannedBookText
        playTimeoutSeconds = state.playTimeoutSeconds

        if selectedVoiceCatalog != .remote {
            voices = loadLocalVoiceCatalog(selectedVoiceCatalog)
        }

        if !bookText.isEmpty && lastScannedBookText.isEmpty {
            lastScannedBookText = bookText
        }
        updateRecommendations(from: bookText)
        loadPersistentLibrary()
    }

    func restoreState(_ state: ReaderState) {
        bookText = state.bookText
        chapters = state.chapters
        characters = state.characters
        scriptSegments = state.scriptSegments
        selectedChapterID = state.selectedChapterID
        apiEndpoint = state.apiEndpoint
        apiKey = state.apiKey
        books = state.books
        currentBookTitle = state.currentBookTitle
        currentBookID = state.currentBookID
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
        lastScannedBookText = state.lastScannedBookText
        playTimeoutSeconds = state.playTimeoutSeconds
        ttsQueue = state.ttsQueue ?? []
        ttsCurrentIndex = state.ttsCurrentIndex ?? 0
        ttsIsPlaying = state.ttsIsPlaying ?? false
        ttsChapterTitle = state.ttsChapterTitle ?? ""
        ttsSegmentTitle = state.ttsSegmentTitle ?? ""
        recommendations = state.recommendations ?? []
        statusMessage = "数据已恢复。"
        saveState()
    }

    func saveState() {
        let state = ReaderState(
            bookText: bookText,
            chapters: chapters,
            characters: characters,
            scriptSegments: scriptSegments,
            selectedChapterID: selectedChapterID,
            apiEndpoint: apiEndpoint,
            apiKey: apiKey,
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
            lastScannedBookText: lastScannedBookText,
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
            isSpeaking: isSpeaking
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
        if selectedVoiceCatalog != .remote && voices.isEmpty {
            voices = loadLocalVoiceCatalog(selectedVoiceCatalog)
        }
    }

    func testTTSConnection() async -> String {
        guard let url = URL(string: apiEndpoint) else { return "无效的 TTS 服务地址。" }
        do {
            let client = TTSHttpClient(baseURL: url, apiKey: apiKey.isEmpty ? nil : apiKey)
            let voices = try await client.fetchVoiceList()
            return "连通成功，发现 \(voices.count) 个音色。"
        } catch let urlError as URLError {
            return "网络错误：\(urlError.localizedDescription)"
        } catch let ns as NSError {
            return "服务错误：\(ns.localizedDescription) (code: \(ns.code))"
        } catch {
            return "未知错误：\(error.localizedDescription)"
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
        lastReadChapterIndexByBook[bookID] = chapterIndex
        persistence.saveLastReadChapterIndexMap(lastReadChapterIndexByBook)
        saveState()
    }

    func lastReadChapterIndex(for bookID: UUID) -> Int? {
        return lastReadChapterIndexByBook[bookID]
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
        guard let text = content else {
            statusMessage = "导入失败：无法识别文件编码。"
            await MainActor.run { isBusy = false }
            return
        }
        let title = url.deletingPathExtension().lastPathComponent
        let book = Book(id: UUID(), title: title, text: text, importedAt: Date())
        books.append(book)
        persistence.saveBooks(books)
        bookText = text
        currentBookTitle = title
        currentBookID = book.id.uuidString
        chapters = extractChapters(from: bookText)
        selectedChapterID = chapters.first?.id
        characters = []
        scriptSegments = []
        recommendations = []
        lastScannedBookText = ""
        statusMessage = "已导入：\(title)，共 \(chapters.count) 章。"
        saveState()
        await MainActor.run {
            importProgress = 0.0
            isBusy = false
        }
    }

    private func stateFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("tts_reader_state.json")
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
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            await MainActor.run { statusMessage = "导入文本为空。" }
            return
        }

        // perform chapter extraction off-main-thread
        let extracted = await Task.detached { [weak self, trimmedText] in
            return self?.extractChapters(from: trimmedText) ?? []
        }.value

        await MainActor.run {
            bookText = trimmedText
            currentBookTitle = "未命名文本"
            currentBookID = UUID().uuidString
            chapters = extracted
            selectedChapterID = chapters.first?.id
            characters = []
            scriptSegments = []
            recommendations = []
            lastScannedBookText = ""
            statusMessage = "已导入文本，发现 \(chapters.count) 个章节。"

            let book = Book(id: UUID(), title: currentBookTitle, text: bookText, importedAt: Date())
            books.append(book)
            saveState()
        }
    }

    func parseChapters() {
        // synchronous wrapper kept for compatibility; prefer async version
        Task { await parseChaptersAsync() }
    }

    func parseChaptersAsync() async {
        let text = bookText
        await MainActor.run { isBusy = true; importProgress = 0.0; statusMessage = "正在扫描章节..." }
        let extracted = await Task.detached { [weak self, text] in
            // reuse existing extraction logic
            return self?.extractChapters(from: text) ?? []
        }.value
        await MainActor.run {
            chapters = extracted
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

    func scanCharacters() async {
        ensureVoiceOptionsLoaded()
        let currentVoices = voices
        let currentSensitivity = defaultSensitivity
        // perform character inference off the main thread
        let inferred = await Task.detached { [bookText, currentVoices, currentSensitivity, weak self] in
            return self?.inferCharacters(from: bookText, voices: currentVoices, defaultSensitivity: currentSensitivity) ?? []
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
            lastScannedBookText = bookText
            updateRecommendations()
            saveState()
        }
    }

    func createScriptSegmentsAsync(from text: String) async -> [ScriptSegment] {
        let currentCharacters = characters
        let currentVoices = voices
        let currentSensitivity = defaultSensitivity
        return await Task.detached { [weak self, text, currentCharacters, currentVoices, currentSensitivity] in
            return self?.createScriptSegments(from: text, characters: currentCharacters, defaultSensitivity: currentSensitivity, voices: currentVoices) ?? []
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
        } else if let chapter = chapters.first(where: { $0.id == selectedChapterID }) {
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
            updateRecommendations(from: wholeBook ? bookText : (chapters.first(where: { $0.id == selectedChapterID })?.text ?? bookText))
            saveState()
        }
    }

    func refreshVoices() async {
        isBusy = true
        if selectedVoiceCatalog != .remote {
            voices = loadLocalVoiceCatalog(selectedVoiceCatalog)
            statusMessage = "已加载本地音色目录：\(selectedVoiceCatalog.displayName)，共 \(voices.count) 个音色。"
            updateRecommendations()
            saveState()
            isBusy = false
            return
        }

        guard !apiEndpoint.isEmpty else {
            statusMessage = "请先填写 TTS 服务地址。"
            isBusy = false
            return
        }

        do {
            voices = try await client.fetchVoiceList()
            if voices.isEmpty {
                voices = VoiceItem.defaultItems()
                statusMessage = "语音列表为空，使用默认内置音色。"
            } else {
                statusMessage = "已加载远程服务音色，共 \(voices.count) 个。"
            }
        } catch {
            voices = VoiceItem.defaultItems()
            statusMessage = "获取语音失败：\(error.localizedDescription)，已使用默认内置音色。"
        }
        updateRecommendations()
        saveState()
        isBusy = false
    }

    func previewVoice(for profile: CharacterProfile) async {
        guard !apiEndpoint.isEmpty else {
            statusMessage = "请先填写 TTS 服务地址。"
            return
        }
        isBusy = true
        let text = "你好，我是 \(profile.name)，这是我的声音示例。"
        do {
            let audioURL = try await client.synthesizeAudio(text: text, voice: profile.voice, rate: profile.rate, pitch: profile.pitch, style: profile.style)
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

    func playSelectedChapter() async {
        guard !bookText.isEmpty else {
            statusMessage = "请先导入小说文本。"
            return
        }
        await buildScript(for: false)
        do {
            try await playScriptSegments(scriptSegments)
        } catch {
            statusMessage = "远程 TTS 服务不可用，使用系统语音播放当前章节。"
            await playLocalSpeech(bookText)
        }
    }

    func playWholeBook() async {
        guard !bookText.isEmpty else {
            statusMessage = "请先导入小说文本。"
            return
        }
        await buildScript(for: true)
        do {
            try await playScriptSegments(scriptSegments)
        } catch {
            statusMessage = "远程 TTS 服务不可用，使用系统语音播放整本小说。"
            await playLocalSpeech(bookText)
        }
    }

    func stopPlayback() {
        audioController.stop()
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        statusMessage = "已停止播放。"
    }

    func playChapterWithTTS(chapter: BookChapter) async {
        statusMessage = "正在准备朗读章节..."

        let segments = await createScriptSegmentsAsync(from: chapter.text)
        guard !segments.isEmpty else {
            statusMessage = "当前章节脚本为空，无法朗读。"
            return
        }

        do {
            try await playScriptSegments(segments)
        } catch {
            statusMessage = "远程 TTS 服务不可用，使用系统语音播放当前章节。"
            await playLocalSpeech(chapter.text)
            isBusy = false
        }
    }

    private func playScriptSegments(_ segments: [ScriptSegment]) async throws {
        guard !segments.isEmpty else {
            statusMessage = "当前没有可播放的朗读段落。"
            return
        }

        let bookTitle = currentBookTitle.isEmpty ? "未知书籍" : currentBookTitle
        let chapterTitle = chapters.first(where: { $0.id == selectedChapterID })?.title ?? "当前章节"
        let bookID = UUID(uuidString: currentBookID) ?? UUID()
        let chapterIndex = chapters.firstIndex(where: { $0.id == selectedChapterID }) ?? 0

        var queueItems: [TTSQueueItem] = []

        isBusy = true
        playProgress = 0

        for (index, segment) in segments.enumerated() {
            currentPlayingLine = segment.characterName
            statusMessage = "正在合成：\(segment.characterName) (\(index + 1)/\(segments.count))"
            let content = "\(segment.characterName)：\(segment.text.replacingOccurrences(of: "\n", with: " "))"

            // Generate cache key
            let cacheKey = "\(segment.voice):\(segment.rate):\(segment.pitch):\(segment.style):\(content.hashValue)"

            let audioURL: URL
            if let cachedURL = ttsCache[cacheKey] {
                audioURL = cachedURL
            } else {
                let synthesizedURL = try await client.synthesizeAudio(text: content, voice: segment.voice, rate: segment.rate, pitch: segment.pitch, style: segment.style)
                ttsCache[cacheKey] = synthesizedURL
                audioURL = synthesizedURL
            }

            let queueItem = TTSQueueItem(
                segment: segment,
                audioURL: audioURL,
                chapterTitle: chapterTitle,
                bookTitle: bookTitle,
                bookID: bookID.uuidString,
                chapterIndex: chapterIndex,
                segmentIndex: index,
                totalSegments: segments.count
            )
            queueItems.append(queueItem)

            playProgress = Double(index + 1) / Double(segments.count)
        }

        ttsQueue = queueItems
        ttsCurrentIndex = 0
        ttsChapterTitle = chapterTitle
        ttsSegmentTitle = queueItems.first?.segment.characterName ?? ""
        ttsIsPlaying = true

        // Play via audio controller
        audioController.playQueue(queueItems)

        // Update play progress based on audio controller
        await MainActor.run {
            isSpeaking = true
        }

        // Wait for playback to complete or be interrupted
        while audioController.isPlaying && !queueItems.isEmpty {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await MainActor.run {
                ttsCurrentTime = audioController.currentProgress * (audioController.currentDuration)
                ttsDuration = audioController.currentDuration
                ttsCurrentIndex = audioController.currentIndex
                ttsSegmentTitle = audioController.currentTitle
                playProgress = Double(audioController.currentIndex + 1) / Double(queueItems.count)
            }
        }

        await MainActor.run {
            isSpeaking = false
            isBusy = false
            ttsIsPlaying = false
        }

        statusMessage = "已播放完毕。"
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

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timedOut
            }
            let result = try await group.next()!
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

    nonisolated func extractChapters(from text: String) -> [BookChapter] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let headingPattern = "(?m)^(第[零一二三四五六七八九十百千0-9]{1,8}[章节].*)"
        let headings = trimmed.regexGroups(pattern: headingPattern)
        if headings.count >= 2 {
            var chapters: [BookChapter] = []
            let lines = trimmed.components(separatedBy: .newlines)
            var currentTitle: String?
            var currentText = ""
            for line in lines {
                if let firstHead = line.firstMatch(regex: headingPattern)?.first {
                    if let title = currentTitle, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        chapters.append(BookChapter(id: UUID(), title: title, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                    currentTitle = firstHead
                    currentText = line + "\n"
                } else {
                    currentText.append(line + "\n")
                }
            }
            if let title = currentTitle, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chapters.append(BookChapter(id: UUID(), title: title, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            return chapters
        }

        let parts = trimmed.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if parts.count >= 3 {
            return parts.enumerated().map { index, piece in
                BookChapter(id: UUID(), title: "章节 \(index + 1)", text: piece.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return splitIntoPseudoChapters(trimmed)
    }

    nonisolated func splitIntoPseudoChapters(_ text: String) -> [BookChapter] {
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

        let namePatterns = [
            "([\\p{Han}]{2,4})(?=先生|小姐|姑娘|公子|师父|师傅|少爷|哥|姐|太太|夫人)",
            "([\\p{Han}]{2,4})(?=笑道|说道|问道|喊道|低声说|轻声说|轻声道|说道|道)",
            "([\\p{Han}]{2,4})(?=说|问|叫|喝|笑)",
            "([\\p{Han}]{2,4})(?:先生|小姐|姑娘|公子|师父|师傅|太太|夫人)"
        ]

        for pattern in namePatterns {
            for match in raw.regexGroups(pattern: pattern) {
                if let name = match.first?.trimmingCharacters(in: .whitespacesAndNewlines), name.count >= 2, name.count <= 4 {
                    names.append(name)
                }
            }
        }

        let wordPattern = "([\\p{Han}]{2,4})[，。？！；、 ]"
        for match in raw.regexGroups(pattern: wordPattern) {
            if let candidate = match.first?.trimmingCharacters(in: .whitespacesAndNewlines), candidate.count >= 2, candidate.count <= 4 {
                if !candidate.hasPrefix("第") && !candidate.hasSuffix("章") {
                    names.append(candidate)
                }
            }
        }

        // Analyze narrator patterns - text that is not dialogue
        let narratorIndicators = detectNarratorPatterns(in: raw)

        var result: [CharacterProfile] = []
        for name in names.prefix(8) {
            let context = raw.contextAround(name, radius: 120)
            let gender = detectGender(in: context)
            let age = detectAge(in: context)
            let tone = detectTone(in: context)
            let style = styleFromTone(tone)

            // Detect if this is likely a narrator
            let isNarrator = isLikelyNarrator(name: name, context: context, narratorIndicators: narratorIndicators)
            let role: CharacterRole = isNarrator ? .narrator : .character

            // For narrator, use a neutral voice; for characters, assign based on gender/tone
            let assignedVoice: String
            if isNarrator {
                assignedVoice = defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: voices)
            } else {
                assignedVoice = defaultVoice(for: gender, tone: tone, voices: voices)
            }

            result.append(CharacterProfile(
                id: UUID(),
                name: name,
                gender: gender,
                age: age,
                tone: tone,
                voice: assignedVoice,
                rate: style == "cheerful" ? 10 : style == "sad" ? -10 : 0,
                pitch: style == "cheerful" ? 10 : style == "sad" ? -5 : 0,
                style: style,
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

    nonisolated func createScriptSegments(from text: String, characters: [CharacterProfile], defaultSensitivity: Int, voices: [VoiceItem]) -> [ScriptSegment] {
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var segments: [ScriptSegment] = []
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = trimmed.chunked(into: 900)
            for line in lines {
                let speaker = detectSpeaker(in: line, characters: characters) ?? characters.first?.name ?? "叙述者"
                let matchedProfile = characters.first(where: { line.contains($0.name) })
                let speakerProfile = matchedProfile ?? characters.first(where: { $0.name == speaker })
                let tone = detectTone(in: line)
                var profile = speakerProfile ?? characters.first ?? CharacterProfile(id: UUID(), name: speaker, gender: "未知", age: "未知", tone: tone, voice: "", rate: 0, pitch: 0, style: "neutral", sensitivity: defaultSensitivity)
                if profile.voice.isEmpty {
                    profile.voice = defaultVoice(for: profile.gender, tone: tone, name: profile.name, voices: voices)
                }

                // detect tone for this line and derive style/pitch adjustments
                let dynamicStyle = styleFromTone(tone)
                let tonePitchBase: Int
                switch dynamicStyle {
                case "cheerful": tonePitchBase = 8
                case "angry": tonePitchBase = 10
                case "sad": tonePitchBase = -6
                default: tonePitchBase = 0
                }

                // determine sensitivity: use character-specific if set (>0), otherwise fall back to global default
                let sensitivityValue = (profile.sensitivity > 0) ? profile.sensitivity : defaultSensitivity
                // sensitivity scales how strongly this character follows detected tone
                let sensitivityFactor = Double(max(0, min(sensitivityValue, 100))) / 50.0 // 50 -> 1.0
                let scaledPitchAdjustment = Int(Double(tonePitchBase) * sensitivityFactor)

                // If profile has a non-neutral custom style, honor it; otherwise prefer detected style when sensitivity high
                let finalStyle: String
                if profile.style != "neutral" {
                    finalStyle = profile.style
                } else {
                    finalStyle = sensitivityFactor >= 0.6 ? dynamicStyle : "neutral"
                }

                let finalPitch = profile.pitch + scaledPitchAdjustment
                let finalRate = profile.rate

                segments.append(ScriptSegment(
                    id: UUID(),
                    characterName: profile.name,
                    voice: profile.voice,
                    rate: finalRate,
                    pitch: finalPitch,
                    style: finalStyle,
                    text: line
                ))
            }
        }
        return segments
    }

    func playFromParagraph(_ paragraph: String) async {
        guard !bookText.isEmpty else {
            statusMessage = "请先导入小说文本。"
            return
        }
        // ensure script built for current chapter
        await buildScript(for: false)
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let idx = scriptSegments.firstIndex(where: { $0.text.contains(trimmed) || $0.text == trimmed }) ?? 0
        let slice = Array(scriptSegments[idx...])
        do {
            try await playScriptSegments(slice)
        } catch {
            statusMessage = "朗读失败：\(error.localizedDescription)"
        }
    }

    // Quick E2E test helper: import sample text, build script for first chapter and synthesize first segment
    func runQuickE2ETest(sampleText: String) async -> String {
await importText(sampleText)
        await buildScript(for: false)
        guard let first = scriptSegments.first else { return "脚本为空，无法测试。" }
        do {
            let url = try await client.synthesizeAudio(text: "\(first.characterName)：\(first.text)", voice: first.voice, rate: first.rate, pitch: first.pitch, style: first.style)
            // play briefly to validate
            await audioController.playFilesAndWait([url])
            return "合成并播放成功：\(url.lastPathComponent)"
        } catch {
            return "合成失败：\(error.localizedDescription)"
        }
    }

    nonisolated func detectSpeaker(in line: String, characters: [CharacterProfile]) -> String? {
        for profile in characters {
            if line.contains(profile.name) {
                return profile.name
            }
        }
        // detect patterns like: 小明说道："..." or 小芳："..."
        if let matched = line.firstMatch(regex: "^([\\p{Han}]{1,4})[：: ]")?.first {
            return matched
        }
        if let inQuote = line.firstMatch(regex: "([\\p{Han}]{1,4})(?=笑道|说道|问道|喊道|低声说|轻声说|轻声道|说道|道)")?.first {
            return inQuote
        }
        // detect quoted dialogue with preceding speaker on previous line like: 小明：\n"..."
        if let prevSpeaker = line.firstMatch(regex: "(?m)([\\p{Han}]{1,4})[：:][\r\n]+\")")?.first {
            return prevSpeaker
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
        var result: [String: Int] = [:]
        let raw = text.replacingOccurrences(of: "\r", with: "\n")
        for profile in characters {
            let occurrences = raw.components(separatedBy: profile.name).count - 1
            result[profile.name] = max(occurrences, 0)
        }
        return result
    }

    func defaultVoiceItems() -> [VoiceItem] {
        VoiceItem.defaultItems()
    }

    nonisolated func detectGender(in context: String) -> String {
        let lower = context
        if lower.contains("小姐") || lower.contains("姑娘") || lower.contains("她") || lower.contains("母亲") || lower.contains("姐姐") || lower.contains("妹妹") || lower.contains("老婆") || lower.contains("太太") {
            return "女性"
        }
        if lower.contains("先生") || lower.contains("公子") || lower.contains("他") || lower.contains("哥哥") || lower.contains("弟弟") || lower.contains("丈夫") || lower.contains("先生") {
            return "男性"
        }
        return "未知"
    }

    nonisolated func detectAge(in context: String) -> String {
        if context.contains("少年") || context.contains("小孩") || context.contains("稚") || context.contains("孩子") {
            return "少年"
        }
        if context.contains("少女") || context.contains("小姐") || context.contains("姑娘") {
            return "少女"
        }
        if context.contains("青年") || context.contains("年轻") || context.contains("少") {
            return "青年"
        }
        if context.contains("中年") || context.contains("师傅") || context.contains("大人") {
            return "中年"
        }
        if context.contains("老") || context.contains("年迈") || context.contains("老太") || context.contains("老人") {
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

        if profile.gender == "女性" {
            if lowerID.contains("xiao") || lowerName.contains("小") || lowerName.contains("xia") { score += 20 }
            if !lowerID.contains("yun") && !lowerName.contains("云") { score += 5 }
        } else if profile.gender == "男性" {
            if lowerID.contains("yun") || lowerName.contains("云") { score += 20 }
            if !lowerID.contains("xiao") && !lowerName.contains("小") { score += 5 }
        }

        if profile.tone == "温柔" || profile.tone == "轻松" {
            if lowerID.contains("xiao") || lowerName.contains("晓") || lowerName.contains("柔") { score += 10 }
        }
        if profile.tone == "激昂" {
            if let styles = voice.styleList, styles.contains(where: { $0.contains("angry") || $0.contains("excited") || $0.contains("strong") || $0.contains("loud") }) { score += 12 }
        }
        if profile.tone == "疑问" {
            if let styles = voice.styleList, styles.contains(where: { $0.contains("chat") || $0.contains("assistant") || $0.contains("question") }) { score += 8 }
        }
        if profile.tone == "平稳" {
            score += 5
        }

        if locale.contains("zh") { score += 5 }
        if let styles = voice.styleList, styles.contains("chat") { score += 3 }

        if let name = profile.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            if lowerID.contains(name.lowercased()) || lowerName.contains(name.lowercased()) { score += 15 }
        }

        return score
    }

    func loadLocalVoiceCatalog(_ source: VoiceCatalogSource) -> [VoiceItem] {
        guard let resourceName = source.resourceName else { return [] }
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            return defaultVoiceItems()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let raw = try decoder.decode([LocalVoiceCatalogItem].self, from: data)
            return raw.compactMap { item in
                let voiceID = item.short_name ?? item.name ?? item.local_name ?? item.display_name
                guard let id = voiceID else { return nil }
                let title = item.display_name ?? item.local_name ?? item.name ?? id
                return VoiceItem(id: id, name: title, locale: item.locale ?? "zh-CN", styleList: item.style_list ?? item.styleList)
            }
        } catch {
            return defaultVoiceItems()
        }
    }

    nonisolated func suggestedVoices(for profile: CharacterProfile, from voiceOptions: [VoiceItem]) -> [VoiceItem] {
        var list = voiceOptions
        list.sort { voiceMatchScore($0, for: profile) > voiceMatchScore($1, for: profile) }
        return Array(list.prefix(6))
    }

    func voiceSourceDescription(_ source: VoiceCatalogSource) -> String {
        switch source {
        case .remote: return "远程服务音色"
        case .chinese35: return "本地 35 种音色"
        case .fullChinese: return "本地完整音色"
        }
    }

    struct LocalVoiceCatalogItem: Decodable {
        let name: String?
        let display_name: String?
        let local_name: String?
        let short_name: String?
        let locale: String?
        let style_list: [String]?
        let styleList: [String]?
    }
}
    
private class SpeechSynthesizerDelegateProxy: NSObject, AVSpeechSynthesizerDelegate {
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

