import Foundation
import Combine
import AVFoundation
import SwiftUI

@MainActor
final class ReaderStore: ObservableObject {
    @Published var bookText: String = ""
    @Published var chapters: [BookChapter] = []
    @Published var characters: [CharacterProfile] = []
    @Published var scriptSegments: [ScriptSegment] = []
    @Published var voices: [VoiceItem] = []
    @Published var recommendations: [CharacterRecommendation] = []
    @Published var selectedChapterID: UUID?
    @Published var statusMessage: String = "请导入小说或粘贴文本。"
    @Published var isBusy: Bool = false
    @Published var currentPlayingLine: String = ""
    @Published var apiKey: String = ""
    @Published var apiEndpoint: String = "http://127.0.0.1:8080"
    @Published var playProgress: Double = 0.0
    @Published var books: [Book] = []
    @Published var currentBookTitle: String = ""
    @Published var currentBookID: String = UUID().uuidString
    @Published var currentBookProgress: Double = 0.0
    @Published var readerFontSize: Double = 18
    @Published var readerLineSpacing: Double = 8
    @Published var readerTheme: ReaderTheme = .light
    @Published var bookmarks: [BookBookmark] = []
    @Published var bookProgressByChapter: [UUID: Double] = [:]
    @Published var defaultSensitivity: Int = 50

    private let audioController = AudioPlaybackController()
    private var client: TTSHttpClient { TTSHttpClient(baseURL: URL(string: apiEndpoint) ?? URL(string: "http://127.0.0.1:8080")!, apiKey: apiKey.isEmpty ? nil : apiKey) }

    init() {
        loadSettings()
        loadState()
    }

    func loadSettings() {
        apiEndpoint = UserDefaults.standard.string(forKey: "ReaderStore.apiEndpoint") ?? apiEndpoint
        apiKey = UserDefaults.standard.string(forKey: "ReaderStore.apiKey") ?? apiKey
    }

    func saveSettings() {
        UserDefaults.standard.set(apiEndpoint, forKey: "ReaderStore.apiEndpoint")
        UserDefaults.standard.set(apiKey, forKey: "ReaderStore.apiKey")
    }

    func loadState() {
        let url = stateFileURL()
        guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(ReaderState.self, from: data) else {
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
        readerTheme = state.readerTheme
        bookmarks = state.bookmarks
        bookProgressByChapter = state.bookProgressByChapter
        defaultSensitivity = state.defaultSensitivity
        updateRecommendations(from: bookText)
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
            defaultVoice: characters.first?.voice ?? "zh-CN-XiaoxiaoNeural",
            defaultRate: characters.first?.rate ?? 0,
            defaultPitch: characters.first?.pitch ?? 0,
            defaultStyle: characters.first?.style ?? "neutral",
            bookmarks: bookmarks,
            bookProgressByChapter: bookProgressByChapter,
            defaultSensitivity: defaultSensitivity
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFileURL(), options: .atomic)
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
        statusMessage = "已保存书签：\(chapter.title) \(Int(currentBookProgress * 100))%"
        saveState()
    }

    func removeBookmark(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveState()
    }

    func setChapterProgress(_ chapterID: UUID, percent: Double) {
        let capped = min(max(percent, 0), 1)
        bookProgressByChapter[chapterID] = capped
        // update overall progress as average or current chapter
        currentBookProgress = capped
        saveState()
    }

    func getChapterProgress(_ chapterID: UUID) -> Double {
        return bookProgressByChapter[chapterID] ?? 0
    }

    func clearLibrary() {
        books.removeAll()
        statusMessage = "已清空书架。"
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
        let data = try? Data(contentsOf: url)
        for enc in possibleEncodings {
            guard let data = data, let s = String(data: data, encoding: enc) else {
                continue
            }
            content = s
            break
        }
        guard let text = content else {
            statusMessage = "导入失败：无法识别文件编码。"
            return
        }
        let title = url.deletingPathExtension().lastPathComponent
        let book = Book(id: UUID(), title: title, text: text, importedAt: Date())
        books.append(book)
        bookText = text
        chapters = extractChapters(from: bookText)
        selectedChapterID = chapters.first?.id
        statusMessage = "已导入：\(title)，共 \(chapters.count) 章。"
        saveState()
    }

    private func stateFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("tts_reader_state.json")
    }

    func importText(_ text: String) {
        bookText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        chapters = extractChapters(from: bookText)
        selectedChapterID = chapters.first?.id
        statusMessage = "已导入文本，发现 \(chapters.count) 个章节。"
        updateRecommendations()
        saveState()
    }

    func parseChapters() {
        chapters = extractChapters(from: bookText)
        selectedChapterID = chapters.first?.id
        statusMessage = "已扫描 \(chapters.count) 个章节。"
        saveState()
    }

    func scanCharacters() {
        characters = inferCharacters(from: bookText)
        if characters.isEmpty {
            characters = [CharacterProfile(id: UUID(), name: "叙述者", gender: "未知", age: "未知", tone: "中性", voice: "zh-CN-XiaoxiaoNeural", rate: 0, pitch: 0, style: "neutral", sensitivity: 50)]
            statusMessage = "未识别到明确人物，已创建默认叙述者。"
        } else {
            statusMessage = "已识别 \(characters.count) 个角色。"
        }
        updateRecommendations()
        saveState()
    }

    func buildScript(for wholeBook: Bool) {
        let targetText: String
        if wholeBook {
            targetText = bookText
        } else if let chapter = chapters.first(where: { $0.id == selectedChapterID }) {
            targetText = chapter.text
        } else {
            targetText = bookText
        }

        if characters.isEmpty {
            scanCharacters()
        }

        scriptSegments = createScriptSegments(from: targetText)
        if scriptSegments.isEmpty {
            statusMessage = "生成脚本失败，请先导入文本并扫描角色。"
        } else {
            statusMessage = "已生成 \(scriptSegments.count) 个朗读段落。"
        }
        updateRecommendations(from: wholeBook ? bookText : (chapters.first(where: { $0.id == selectedChapterID })?.text ?? bookText))
        saveState()
    }

    func refreshVoices() async {
        guard !apiEndpoint.isEmpty else {
            statusMessage = "请先填写 TTS 服务地址。"
            return
        }
        isBusy = true
        do {
            voices = try await client.fetchVoiceList()
            if voices.isEmpty {
                statusMessage = "语音列表为空，使用默认内置音色。"
            } else {
                statusMessage = "已加载 \(voices.count) 个语音风格。"
            }
        } catch {
            voices = []
            statusMessage = "获取语音失败：\(error.localizedDescription)"
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
            audioController.playFiles([audioURL])
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

    func playSelectedChapter() async {
        guard !bookText.isEmpty else {
            statusMessage = "请先导入小说文本。"
            return
        }
        buildScript(for: false)
        await playScriptSegments(scriptSegments)
    }

    func playWholeBook() async {
        guard !bookText.isEmpty else {
            statusMessage = "请先导入小说文本。"
            return
        }
        buildScript(for: true)
        await playScriptSegments(scriptSegments)
    }

    func stopPlayback() {
        audioController.stop()
        statusMessage = "已停止播放。"
    }

    func playChapterWithTTS(chapter: BookChapter) async {
        isBusy = true
        statusMessage = "正在准备朗读章节..."
        
        let voice = characters.first?.voice ?? "zh-CN-XiaoxiaoNeural"
        
        do {
            let audioURL = try await client.synthesizeAudio(
                text: chapter.text,
                voice: voice,
                rate: characters.first?.rate ?? 0,
                pitch: characters.first?.pitch ?? 0,
                style: characters.first?.style ?? "neutral"
            )
            audioController.playFiles([audioURL])
            statusMessage = "正在朗读：\(chapter.title)"
            isBusy = false
        } catch {
            statusMessage = "朗读失败：\(error.localizedDescription)"
            isBusy = false
        }
    }

    private func playScriptSegments(_ segments: [ScriptSegment]) async {
        guard !segments.isEmpty else {
            statusMessage = "当前没有可播放的朗读段落。"
            return
        }
        isBusy = true
        playProgress = 0
        var audioURLs: [URL] = []
        for (index, segment) in segments.enumerated() {
            currentPlayingLine = segment.characterName
            statusMessage = "正在合成：\(segment.characterName)"
            do {
                let content = "\(segment.characterName)：\(segment.text.replacingOccurrences(of: "\n", with: " "))"
                let audioURL = try await client.synthesizeAudio(text: content, voice: segment.voice, rate: segment.rate, pitch: segment.pitch, style: segment.style)
                audioURLs.append(audioURL)
            } catch {
                statusMessage = "合成失败：\(error.localizedDescription)"
                isBusy = false
                return
            }
            playProgress = Double(index + 1) / Double(segments.count)
        }

        audioController.playFiles(audioURLs)
        statusMessage = "已开始播放，当前音色：\(segments.first?.voice ?? "未知")。"
        isBusy = false
    }

    private func extractChapters(from text: String) -> [BookChapter] {
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

        var parts = trimmed.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if parts.count < 3 {
            parts = trimmed.chunked(into: 12000)
        }
        return parts.enumerated().map { index, piece in
            BookChapter(id: UUID(), title: "章节 \(index + 1)", text: piece.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func inferCharacters(from text: String) -> [CharacterProfile] {
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

        var result: [CharacterProfile] = []
        for name in names.prefix(8) {
            let context = raw.contextAround(name, radius: 120)
            let gender = detectGender(in: context)
            let age = detectAge(in: context)
            let tone = detectTone(in: context)
            let style = styleFromTone(tone)
            result.append(CharacterProfile(
                id: UUID(),
                name: name,
                gender: gender,
                age: age,
                tone: tone,
                voice: defaultVoice(for: gender, tone: tone),
                rate: style == "cheerful" ? 10 : style == "sad" ? -10 : 0,
                pitch: style == "cheerful" ? 10 : style == "sad" ? -5 : 0,
                style: style,
                sensitivity: 50
            ))
        }

        return result
    }

    private func createScriptSegments(from text: String) -> [ScriptSegment] {
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var segments: [ScriptSegment] = []
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = trimmed.chunked(into: 900)
            for line in lines {
                let speaker = detectSpeaker(in: line) ?? characters.first?.name ?? "叙述者"
                var profile = characters.first(where: { line.contains($0.name) }) ?? characters.first(where: { $0.name == speaker }) ?? characters.first ?? CharacterProfile(id: UUID(), name: speaker, gender: "未知", age: "未知", tone: "中性", voice: "zh-CN-XiaoxiaoNeural", rate: 0, pitch: 0, style: "neutral", sensitivity: 50)

                // detect tone for this line and derive style/pitch adjustments
                let tone = detectTone(in: line)
                let dynamicStyle = styleFromTone(tone)
                let tonePitchBase: Int
                switch dynamicStyle {
                case "cheerful": tonePitchBase = 8
                case "angry": tonePitchBase = 10
                case "sad": tonePitchBase = -6
                default: tonePitchBase = 0
                }

                // sensitivity scales how strongly this character follows detected tone
                let sensitivityFactor = Double(max(0, min(profile.sensitivity, 100))) / 50.0 // 50 -> 1.0
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
        buildScript(for: false)
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let idx = scriptSegments.firstIndex(where: { $0.text.contains(trimmed) || $0.text == trimmed }) ?? 0
        let slice = Array(scriptSegments[idx...])
        await playScriptSegments(slice)
    }

    private func detectSpeaker(in line: String) -> String? {
        for profile in characters {
            if line.contains(profile.name) {
                return profile.name
            }
        }
        if let matched = line.firstMatch(regex: "([\\p{Han}]{2,4})(?=笑道|说道|问道|喊道|低声说|轻声说|轻声道|说道|道)")?.first {
            return matched
        }
        return nil
    }

    private func updateRecommendations(from sourceText: String? = nil) {
        let text = sourceText ?? bookText
        guard !characters.isEmpty else {
            recommendations = []
            return
        }

        let counts = countCharacterAppearances(in: text)
        let candidates = characters.sorted { (counts[$0.name] ?? 0) > (counts[$1.name] ?? 0) }
        let voiceOptions = voices.isEmpty ? defaultVoiceItems() : voices

        recommendations = candidates.map { profile in
            let suggested = suggestedVoices(for: profile, from: voiceOptions)
            let count = counts[profile.name] ?? 0
            return CharacterRecommendation(id: profile.id, profile: profile, count: count, suggestedVoices: suggested)
        }
    }

    private func countCharacterAppearances(in text: String) -> [String: Int] {
        var result: [String: Int] = [:]
        let raw = text.replacingOccurrences(of: "\r", with: "\n")
        for profile in characters {
            let occurrences = raw.components(separatedBy: profile.name).count - 1
            result[profile.name] = max(occurrences, 0)
        }
        return result
    }

    private func suggestedVoices(for profile: CharacterProfile, from voiceOptions: [VoiceItem]) -> [VoiceItem] {
        var list = voiceOptions
        if profile.gender == "女性" {
            list = list.sorted { lhs, rhs in
                let lscore = (lhs.id.contains("Xiao") || lhs.id.contains("xia")) ? 1 : 0
                let rscore = (rhs.id.contains("Xiao") || rhs.id.contains("xia")) ? 1 : 0
                return lscore > rscore
            }
        } else if profile.gender == "男性" {
            list = list.sorted { lhs, rhs in
                let lscore = (lhs.id.contains("Yun") || lhs.id.contains("yun")) ? 1 : 0
                let rscore = (rhs.id.contains("Yun") || rhs.id.contains("yun")) ? 1 : 0
                return lscore > rscore
            }
        }
        return Array(list.prefix(4))
    }

    private func defaultVoiceItems() -> [VoiceItem] {
        [
            VoiceItem(id: "zh-CN-XiaoxiaoNeural", name: "标准女声", locale: "zh-CN"),
            VoiceItem(id: "zh-CN-YunxiNeural", name: "年轻男声", locale: "zh-CN"),
            VoiceItem(id: "zh-CN-XiaohanNeural", name: "活力女声", locale: "zh-CN"),
            VoiceItem(id: "zh-CN-YunjianNeural", name: "成熟男声", locale: "zh-CN"),
            VoiceItem(id: "zh-CN-XiaomoNeural", name: "温柔女声", locale: "zh-CN")
        ]
    }

    private func detectGender(in context: String) -> String {
        let lower = context
        if lower.contains("小姐") || lower.contains("姑娘") || lower.contains("她") || lower.contains("母亲") || lower.contains("姐姐") || lower.contains("妹妹") || lower.contains("老婆") || lower.contains("太太") {
            return "女性"
        }
        if lower.contains("先生") || lower.contains("公子") || lower.contains("他") || lower.contains("哥哥") || lower.contains("弟弟") || lower.contains("丈夫") || lower.contains("先生") {
            return "男性"
        }
        return "未知"
    }

    private func detectAge(in context: String) -> String {
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

    private func detectTone(in context: String) -> String {
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

    private func styleFromTone(_ tone: String) -> String {
        switch tone {
        case "激昂": return "angry"
        case "疑问": return "neutral"
        case "温柔": return "sad"
        case "轻松": return "cheerful"
        default: return "neutral"
        }
    }

    private func defaultVoice(for gender: String, tone: String) -> String {
        if gender == "女性" {
            if tone == "温柔" || tone == "轻松" {
                return "zh-CN-XiaomoNeural"
            }
            return "zh-CN-XiaoxiaoNeural"
        }
        if gender == "男性" {
            return "zh-CN-YunxiNeural"
        }
        return "zh-CN-XiaoxiaoNeural"
    }
}
