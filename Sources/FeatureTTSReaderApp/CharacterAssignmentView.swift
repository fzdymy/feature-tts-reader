import SwiftUI
import UniformTypeIdentifiers


struct CharacterAssignmentPanel: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book

    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase: String = ""
    @State private var elapsedText: String = ""
    @State private var etaText: String = ""
    @State private var activeSheet: SheetTarget?

    private enum SheetTarget: Identifiable {
        case editor(CharacterProfile)
        case templatePicker
        var id: String {
            switch self {
            case .editor: return "editor"
            case .templatePicker: return "template"
            }
        }
    }
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showTemplateExporter = false
    @State private var exportData = Data()
    @State private var showAllCharacters = false

    private let maxDisplayed = 100

    private var bookCharacters: [CharacterProfile] {
        store.characters.filter { $0.bookID == nil || $0.bookID == book.id }
    }

    private var displayedCharacters: [CharacterProfile] {
        showAllCharacters ? bookCharacters : Array(bookCharacters.prefix(maxDisplayed))
    }

    var body: some View {
        Section(header: Text("角色分配 (\(bookCharacters.count) 人)")) {
            actionButtons
            if isScanning { scanProgressView }
            if bookCharacters.isEmpty {
                Text("尚未分配角色，请扫描或应用模板。")
                    .font(.caption).foregroundColor(.secondary).padding(.vertical, 4)
            } else {
                characterGrid
                if bookCharacters.count > maxDisplayed {
                    Button(action: { showAllCharacters.toggle() }) {
                        Text(showAllCharacters ? "显示前 \(maxDisplayed) 个" : "显示全部 (\(bookCharacters.count) 个)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                bottomButtons
            }
        }
        .sheet(item: $activeSheet) { target in
            switch target {
            case .templatePicker:
                templatePickerSheet
            case .editor(let profile):
                CharacterEditorView(
                    character: profile,
                    voices: store.voices
                ) { updated in
                    if let i = store.characters.firstIndex(where: { $0.id == updated.id }) {
                        store.characters[i] = updated
                    }
                    store.saveState()
                }
                .environmentObject(store)
            }
        }
        .fileExporter(isPresented: $showExporter, document: JSONDocument(data: exportData),
                      contentType: .json, defaultFilename: "book-characters-\(book.title)") { result in
            switch result {
            case .success: store.statusMessage = "角色配置已导出"
            case .failure(let e): store.statusMessage = "导出失败: \(e.localizedDescription)"
            }
        }
        .fileExporter(isPresented: $showTemplateExporter, document: JSONDocument(data: exportData),
                      contentType: .json, defaultFilename: "template-\(book.title)") { result in
            switch result {
            case .success: store.statusMessage = "模板已导出"
            case .failure(let e): store.statusMessage = "导出模板失败: \(e.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                if store.importVoiceProfiles(from: data) {
                    store.statusMessage = "角色配置已导入"
                }
            case .failure(let e):
                store.statusMessage = "导入失败: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: { startScan() }) {
                HStack(spacing: 6) {
                    Image(systemName: "person.text.rectangle")
                    Text("扫描全书角色")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)
            HStack(spacing: 8) {
                Button(action: { activeSheet = .templatePicker }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.on.square")
                        Text("模板匹配")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                if !bookCharacters.isEmpty {
                    Button(role: .destructive) {
                        store.characters.removeAll { $0.bookID == nil || $0.bookID == book.id }
                        store.saveState()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("清空角色")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Scan Progress

    private var scanProgressView: some View {
        VStack(spacing: 6) {
            ProgressView(value: scanProgress, total: 1.0)
                .progressViewStyle(.linear)
            HStack {
                if !elapsedText.isEmpty {
                    Text(elapsedText).font(.caption2).foregroundColor(.secondary)
                }
                if !etaText.isEmpty {
                    Text("剩余 \(etaText)").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                if !scanPhase.isEmpty {
                    Text(scanPhase).font(.caption2).foregroundColor(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Character Grid

    private var characterGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(displayedCharacters) { profile in
                characterCard(profile)
            }
        }
    }

    private func characterCard(_ profile: CharacterProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Text(profile.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                if profile.isNarrator {
                    Text("旁白").font(.system(size: 9)).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15)).cornerRadius(3)
                }
                Spacer()
                if !profile.gender.isEmpty, profile.gender != "未知" {
                    Text(profile.gender).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            let attrs = [profile.age, profile.tone].filter { !$0.isEmpty && $0 != "未知" }
            if !attrs.isEmpty {
                Text(attrs.joined(separator: " · ")).font(.system(size: 10)).foregroundColor(.secondary)
            }
            if let alias = profile.aliases.first {
                Text("(\(alias))").font(.system(size: 9)).foregroundColor(.orange)
            }
            if !profile.voice.isEmpty {
                let voiceName = store.voices.first(where: { $0.id == profile.voice })?.name ?? profile.voice
                Text(voiceName).font(.system(size: 10)).lineLimit(1)
            } else {
                Text("未分配音色").font(.system(size: 9)).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                if !profile.style.isEmpty, profile.style != "neutral" {
                    Text(styleName(profile.style)).font(.system(size: 9))
                }
                if profile.rate != 0 {
                    Text("语速\(profile.rate > 0 ? "+" : "")\(profile.rate)").font(.system(size: 9))
                }
                if profile.pitch != 0 {
                    Text("语调\(profile.pitch > 0 ? "+" : "")\(profile.pitch)").font(.system(size: 9))
                }
            }
            .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(10)
        .onTapGesture {
            activeSheet = .editor(profile)
        }
        .contextMenu {
            Button {
                activeSheet = .editor(profile)
            } label: {
                Label("微调编辑", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                deleteCharacter(profile)
            } label: {
                Label("删除角色", systemImage: "trash")
            }
            Button {
                generateSample(profile)
            } label: {
                Label("生成试听", systemImage: "play.circle")
            }
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack(spacing: 12) {
            Button(action: exportCharacters) {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            Button(action: { showImporter = true }) {
                Label("导入", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            Button(action: exportAsTemplate) {
                Label("导出为模板", systemImage: "doc.badge.gearshape")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Scan Pipeline

    private func startScan() {
        isScanning = true
        scanProgress = 0
        scanPhase = ""
        elapsedText = ""
        etaText = ""
        let startTime = Date()
        let text = book.text
        let defaultSensitivity = store.defaultSensitivity
        let analyzer = CharacterAnalyzer()

        Task { @MainActor in
            // Phase 1: chunked regex on full text
            scanPhase = "正则匹配中..."
            scanProgress = 0.0
            var allNames = Set<String>()
            let nsText = text as NSString
            let totalLen = nsText.length
            let chunkSize = 30_000
            let totalChunks = max(1, (totalLen + chunkSize - 1) / chunkSize)
            for i in 0..<totalChunks {
                if Task.isCancelled { isScanning = false; return }
                let start = i * chunkSize
                let end = min(start + chunkSize, totalLen)
                let chunk = nsText.substring(with: NSRange(location: start, length: end - start))
                let names = await Task.detached(priority: .userInitiated) {
                    analyzer.extractDialogueNames(from: chunk)
                }.value
                for n in names { allNames.insert(n) }
                let elapsed = Date().timeIntervalSince(startTime)
                scanProgress = Double(i + 1) / Double(totalChunks) * 0.50
                elapsedText = formatDuration(elapsed)
                if i >= 3 {
                    let perChunk = elapsed / Double(i + 1)
                    etaText = formatDuration(perChunk * Double(totalChunks - i - 1))
                }
                await Task.yield()
            }

            let elapsed1 = Date().timeIntervalSince(startTime)
            elapsedText = formatDuration(elapsed1)

            // Phase 1b: filter out non-real names (surname check, reject pronouns/particles)
            allNames = allNames.filter { CharacterAnalyzer.looksLikeRealName($0) }

            // Phase 2: AC自动机频率统计 (Aho-Corasick 多模匹配)
            // 用字典树对前 500K 字做 O(n) 扫描，频次低于阈值的丢弃
            // 阈值按全文长度自适应：短文本从严，长文本从宽
            scanPhase = "频率统计中..."
            etaText = ""
            let freqLimit = min(500_000, text.count)
            let freqText = String(text.prefix(freqLimit))
            let candidateDict = Dictionary(uniqueKeysWithValues: allNames.map { ($0, 0) })
            let freqResult = await Task.detached(priority: .userInitiated) { [analyzer] in
                analyzer.countWithAC(text: freqText, candidates: candidateDict)
            }.value
            let minFreq = max(3, freqLimit / 100_000)
            allNames = Set(freqResult.filter { $0.value >= minFreq }.map(\.key))
            scanProgress = 0.50
            elapsedText = formatDuration(Date().timeIntervalSince(startTime))
            if allNames.isEmpty && !candidateDict.isEmpty {
                // If frequency filter wiped everything, fall back to top 20% by freq
                let ranked = freqResult.sorted { $0.value > $1.value }
                let keepCount = max(5, ranked.count / 5)
                allNames = Set(ranked.prefix(keepCount).map(\.key))
            }
            await Task.yield()

            // Phase 2b: dedup — remove candidates that are prefixed by a higher-frequency name
            let rankedNames = freqResult.sorted { $0.value > $1.value }
            var dedupNames = Set<String>()
            for (name, _) in rankedNames {
                if !allNames.contains(name) { continue }
                let isPrefix = dedupNames.contains { $0.count >= 2 && name.hasPrefix($0) && $0 != name }
                if !isPrefix {
                    dedupNames.insert(name)
                }
            }
            allNames = dedupNames

            // Phase 2c: NL tagger validation — eliminate common-word false positives
            // (任务/别人/包裹/卫生间/双手/后面/方向 etc.)
            scanPhase = "智能验证中..."
            let nlLimit = min(500_000, text.count)
            let nlText = String(text.prefix(nlLimit))
            let validatedNames = await Task.detached(priority: .userInitiated) { [analyzer] in
                analyzer.validateWithNL(text: nlText, candidates: allNames)
            }.value
            // Keep names that passed NL validation; if NL drops everything (e.g. all names are novel-specific),
            // fall back to the dedup set
            if !validatedNames.isEmpty {
                allNames = validatedNames
            }

            // Phase 2d: cap at top 100 by frequency
            let freqMap = Dictionary(uniqueKeysWithValues: rankedNames.filter { allNames.contains($0.key) })
            let sortedByFreq = allNames.sorted { (freqMap[$0] ?? 0) > (freqMap[$1] ?? 0) }
            allNames = Set(sortedByFreq.prefix(100))

            // Phase 3: attribute analysis (progress 0.50 → 1.0)
            scanPhase = "属性分析中..."
            etaText = ""
            var inferred = [CharacterProfile]()
            let contextLimit = min(500_000, text.count)
            let contextText = text.prefix(contextLimit)
            let uniqueNames = allNames.sorted()

            for (idx, name) in uniqueNames.enumerated() {
                if Task.isCancelled { isScanning = false; return }
                var gender = "未知"
                var age = "未知"
                var tone = "平稳"
                var style = "neutral"
                var rate = 0
                var pitch = 0
                guard let range = contextText.range(of: name) else {
                    scanProgress = 0.50 + Double(idx + 1) / Double(uniqueNames.count) * 0.50
                    await Task.yield()
                    continue
                }
                let ctxStart = contextText.index(range.lowerBound, offsetBy: -50, limitedBy: contextText.startIndex) ?? contextText.startIndex
                let ctxEnd = contextText.index(range.upperBound, offsetBy: 150, limitedBy: contextText.endIndex) ?? contextText.endIndex
                let ctx = String(contextText[ctxStart..<ctxEnd])
                let attrs = analyzer.analyzeAttributes(for: name, context: ctx)
                gender = attrs.gender; age = attrs.age; tone = attrs.baseTone
                style = attrs.baseStyle; rate = attrs.baseRate; pitch = attrs.basePitch
                if gender == "未知" { gender = store.guessGender(from: name) ? "男性" : "女性" }
                inferred.append(CharacterProfile(
                    id: UUID(), name: name, aliases: [],
                    gender: gender, age: age, tone: tone,
                    voice: "", rate: rate, pitch: pitch, style: style,
                    sensitivity: defaultSensitivity, frequency: 0,
                    bookID: book.id
                ))
                let elapsed = Date().timeIntervalSince(startTime)
                scanProgress = 0.50 + Double(idx + 1) / Double(uniqueNames.count) * 0.50
                elapsedText = formatDuration(elapsed)
                if idx >= 3 {
                    let perItem = elapsed / Double(idx + 1)
                    etaText = formatDuration(perItem * Double(uniqueNames.count - idx - 1))
                }
                await Task.yield()
            }

            if inferred.isEmpty {
                inferred = [CharacterProfile(id: UUID(), name: "叙述者", aliases: [], gender: "未知",
                    age: "未知", tone: "平稳", voice: "", rate: 0, pitch: 0, style: "neutral",
                    sensitivity: defaultSensitivity, frequency: 1, bookID: book.id)]
            } else if !inferred.contains(where: { $0.isNarrator }) {
                inferred.insert(CharacterProfile(
                    id: UUID(), name: "旁白", aliases: [], gender: "未知", age: "未知", tone: "平稳",
                    voice: "", rate: 0, pitch: 0, style: "neutral",
                    sensitivity: defaultSensitivity, isNarrator: true, role: .narrator,
                    frequency: 1, bookID: book.id
                ), at: 0)
            }

            // Phase 4: merge title-suffixed aliases (陈书记 → 陈太忠, 段市长 → 段卫华)
            let titleSuffixes: Set<String> = ["书记", "市长", "局长", "经理", "医生",
                                              "老师", "公主", "殿下", "仙子", "同学",
                                              "同志", "总裁", "主管", "主任", "姑娘"]
            var mergedProfiles = [CharacterProfile]()
            var toRemove = Set<UUID>()
            for profile in inferred where profile.name.count >= titleSuffixes.first?.count ?? 2 {
                guard let suffix = titleSuffixes.first(where: { profile.name.hasSuffix($0) }),
                      profile.name.count > suffix.count else { continue }
                let base = String(profile.name.dropLast(suffix.count))
                // Find a character whose full name starts with this base prefix
                let candidates = inferred.filter {
                    $0.id != profile.id && !$0.isNarrator && $0.name.hasPrefix(base)
                }
                if let best = candidates.max(by: { $0.frequency < $1.frequency }) {
                    if !best.aliases.contains(profile.name) {
                        var merged = best
                        merged.aliases = (merged.aliases + [profile.name]).sorted()
                        mergedProfiles.append(merged)
                        toRemove.insert(best.id)
                    }
                    toRemove.insert(profile.id)
                }
            }
            if !toRemove.isEmpty {
                inferred.removeAll { toRemove.contains($0.id) }
                inferred.append(contentsOf: mergedProfiles)
            }

            scanProgress = 1.0
            scanPhase = "完成"
            elapsedText = ""
            etaText = ""
            store.characters = inferred
            store.lastScannedBookText = text
            store.updateRecommendations(from: text)
            store.saveState()
            isScanning = false
            store.statusMessage = "扫描完成，识别 \(store.characters.count) 个角色，耗时 \(formatDuration(Date().timeIntervalSince(startTime)))"
        }
    }

    // MARK: - Generate Sample

    private func generateSample(_ profile: CharacterProfile) {
        guard let server = store.activeServer else {
            store.statusMessage = "请先配置 TTS 服务器"
            return
        }
        Task {
            store.statusMessage = "正在生成试听..."
            let sampleText = "你好，我是\(profile.name)。"
            let voiceID = profile.voice.isEmpty ? "zh-CN-XiaoxiaoNeural" : profile.voice
            guard let baseURL = URL(string: server.baseURL) else {
                store.statusMessage = "服务器地址无效"
                return
            }
            do {
                let url = try await TTSHttpClient(
                    baseURL: baseURL,
                    apiKey: server.apiKey
                ).synthesizeAudio(text: sampleText, voice: voiceID,
                                  rate: profile.rate, pitch: profile.pitch,
                                  style: profile.style.isEmpty ? "neutral" : profile.style)
                await store.audioController.playFilesAndWait([url])
                store.statusMessage = "试听已开始播放"
            } catch {
                store.statusMessage = "试听生成失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Export / Import

    private func exportCharacters() {
        guard let data = store.exportVoiceProfiles() else {
            store.statusMessage = "导出失败"
            return
        }
        exportData = data
        showExporter = true
    }

    private func exportAsTemplate() {
        guard let data = store.exportCharactersAsTemplate(name: "\(book.title) 角色配置") else {
            store.statusMessage = "导出模板失败"
            return
        }
        exportData = data
        showTemplateExporter = true
    }

    // MARK: - Template Picker

    private var templatePickerSheet: some View {
        NavigationStack {
            List {
                if store.roleTemplates.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Text("尚无可用模板").foregroundColor(.secondary)
                            Text("请先在「TTS」标签页创建或导入模板。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
                ForEach(store.roleTemplates) { template in
                    Section {
                        Button(action: {
                            activeSheet = nil
                            applyTemplate(template)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name).font(.headline)
                                Text("\(template.roles.count) 个角色").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("选择模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { activeSheet = nil }
                }
            }
        }
    }

    private func applyTemplate(_ template: RoleTemplate) {
        do {
            store.applyTemplate(template)
            store.saveState()
        } catch {
            store.statusMessage = "模板匹配失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func deleteCharacter(_ profile: CharacterProfile) {
        store.characters.removeAll { $0.id == profile.id }
        store.saveState()
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval))秒"
        } else if interval < 3600 {
            return "\(Int(interval / 60))分\(Int(interval.truncatingRemainder(dividingBy: 60)))秒"
        } else {
            return "\(Int(interval / 3600))时\(Int(interval.truncatingRemainder(dividingBy: 3600) / 60))分"
        }
    }

    private func styleName(_ style: String) -> String {
        switch style {
        case "neutral": return "中性"
        case "cheerful": return "欢快"
        case "sad": return "悲伤"
        case "angry": return "愤怒"
        case "gentle": return "温柔"
        case "serious": return "严肃"
        case "lyrical": return "抒情"
        case "disgruntled": return "不满"
        case "affectionate": return "亲切"
        case "calm": return "平静"
        case "fearful": return "恐惧"
        case "depressed": return "低沉"
        case "embarrassed": return "尴尬"
        case "excited": return "激动"
        case "shy": return "害羞"
        default: return style
        }
    }
}
