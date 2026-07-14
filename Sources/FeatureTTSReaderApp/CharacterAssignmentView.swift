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
    @State private var editingCharacter: CharacterProfile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportData = Data()
    @State private var showAllCharacters = false

    private let maxDisplayed = 100

    private var bookCharacters: [CharacterProfile] {
        store.characters.filter { $0.bookID == nil || $0.bookID == book.id }
            .sorted { a, b in
                if a.isNarrator != b.isNarrator { return a.isNarrator }
                return a.appearanceCount > b.appearanceCount
            }
    }

    private var displayedCharacters: [CharacterProfile] {
        let sorted = bookCharacters
        return showAllCharacters ? sorted : Array(sorted.prefix(maxDisplayed))
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
        .sheet(item: $editingCharacter) { profile in
            CharacterEditorView(
                character: profile
            ) { updated in
                if let i = store.characters.firstIndex(where: { $0.id == updated.id }) {
                    store.characters[i] = updated
                }
                store.saveState()
            }
            .environmentObject(store)
        }
        .fileExporter(isPresented: $showExporter, document: JSONDocument(data: exportData),
                      contentType: .json, defaultFilename: "book-characters-\(book.title)") { result in
            switch result {
            case .success: store.statusMessage = "角色配置已导出"
            case .failure(let e): store.statusMessage = "导出失败: \(e.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                if let imported = try? JSONDecoder().decode([CharacterProfile].self, from: data) {
                    store.characters.append(contentsOf: imported)
                    store.saveState()
                    store.statusMessage = "已导入 \(imported.count) 个角色"
                } else {
                    store.statusMessage = "导入失败: 格式错误"
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
                Button("取消") {
                    isScanning = false
                }
                .font(.caption2)
                .foregroundColor(.red)
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
                if profile.gender != .unknown {
                    Text(profile.gender.rawValue).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            let attrs = [profile.age, profile.tone].filter { !$0.isEmpty && $0 != "未知" }
            if !attrs.isEmpty {
                Text(attrs.joined(separator: " · ")).font(.system(size: 10)).foregroundColor(.secondary)
            }
            if let alias = profile.aliases.first {
                Text("(\(alias))").font(.system(size: 9)).foregroundColor(.orange)
            }
            if !profile.voiceID.isEmpty {
                let voiceName = store.voices.first(where: { $0.id == profile.voiceID })?.name ?? profile.voiceID
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
            editingCharacter = profile
        }
        .contextMenu {
            Button {
                editingCharacter = profile
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
            scanPhase = "正在扫描角色..."
            scanProgress = 0.0

            // Phase 1: extractCandidates (paragraph guard → regex → looksLikeRealName → NLTagger + surname)
            // Runs inline tagger per dialogue paragraph — no separate kill-step for NL validation.
            var allNames = await Task.detached(priority: .userInitiated) {
                analyzer.extractCandidates(from: text)
            }.value
            scanProgress = 0.35

            // Phase 2: AC automaton frequency (build once, scan full text, filter ≤1)
            scanPhase = "正在统计分析..."
            let capturedNames = allNames
            let freqResult = await Task.detached(priority: .userInitiated) {
                analyzer.countCharacterFrequencies(text: text, candidates: capturedNames)
            }.value
            let minFreq: Int
            if allNames.isEmpty { minFreq = 0 }
            else if allNames.count <= 10 { minFreq = 1 }
            else { minFreq = max(2, text.count / 200_000) }
            let filtered = Set(freqResult.filter { $0.value >= minFreq }.map(\.key))
            scanProgress = 0.50

            // Dedup — remove candidates prefixed by a higher-frequency name
            let rankedNames = freqResult.sorted { $0.value > $1.value }
            var dedupNames = Set<String>()
            for (name, _) in rankedNames {
                if !filtered.contains(name) { continue }
                let isPrefix = dedupNames.contains { $0.count >= 2 && name.hasPrefix($0) && $0 != name }
                if !isPrefix { dedupNames.insert(name) }
            }

            // Phase 2c: cap at top 100 by frequency
            let freqMap = Dictionary(uniqueKeysWithValues: rankedNames.filter { allNames.contains($0.key) })
            let sortedByFreq = allNames.sorted { (freqMap[$0] ?? 0) > (freqMap[$1] ?? 0) }
            allNames = Set(sortedByFreq.prefix(100))

            // Phase 3: multi-paragraph voting for attributes (replaces old first-occurrence truncation)
            scanPhase = "正在提取属性..."
            etaText = ""
            var inferred = [CharacterProfile]()
            let uniqueNames = dedupNames.sorted()

            for (idx, name) in uniqueNames.enumerated() {
                if Task.isCancelled { isScanning = false; return }
                let attrs = await Task.detached(priority: .userInitiated) { [analyzer] in
                    analyzer.estimateAttributes(for: name, in: text)
                }.value
                let gender: CharacterGender = attrs.gender == "Male" ? .male : (attrs.gender == "Female" ? .female : .unknown)
                let age = attrs.age
                let acFreq = freqResult[name] ?? 0
                inferred.append(CharacterProfile(
                    id: UUID(), name: name, aliases: [],
                    gender: gender, age: age, tone: attrs.baseTone,
                    voiceID: "", rate: attrs.baseRate, pitch: attrs.basePitch, style: attrs.baseStyle,
                    sensitivity: defaultSensitivity, appearanceCount: acFreq,
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
                inferred = [CharacterProfile(id: UUID(), name: "叙述者", aliases: [], gender: .unknown,
                    age: "未知", tone: "平稳", voiceID: "", rate: 0, pitch: 0, style: "neutral",
                    sensitivity: defaultSensitivity, appearanceCount: 1, bookID: book.id)]
            } else if !inferred.contains(where: { $0.isNarrator }) {
                inferred.insert(CharacterProfile(
                    id: UUID(), name: "旁白", aliases: [], gender: .unknown, age: "未知", tone: "平稳",
                    voiceID: "", rate: 0, pitch: 0, style: "neutral",
                    sensitivity: defaultSensitivity, isNarrator: true, role: .narrator,
                    appearanceCount: 1, bookID: book.id
                ), at: 0)
            }

            // Phase 4: merge title-suffixed aliases (陈书记 → 陈太忠, 段市长 → 段卫华)
            let titleSuffixes: Set<String> = ["书记", "市长", "局长", "经理", "医生",
                                              "老师", "公主", "殿下", "仙子", "同学",
                                              "同志", "总裁", "主管", "主任", "姑娘"]
            var mergedMap: [UUID: CharacterProfile] = [:]
            var toRemove = Set<UUID>()
            for profile in inferred where profile.name.count >= (titleSuffixes.first?.count ?? 2) {
                guard let suffix = titleSuffixes.first(where: { profile.name.hasSuffix($0) }),
                      profile.name.count > suffix.count else { continue }
                let base = String(profile.name.dropLast(suffix.count))
                let candidates = inferred.filter {
                    $0.id != profile.id && !$0.isNarrator && $0.name.hasPrefix(base)
                }
                if let best = candidates.max(by: { $0.appearanceCount < $1.appearanceCount }) {
                    toRemove.insert(profile.id)
                    var merged = mergedMap[best.id] ?? best
                    if !merged.aliases.contains(profile.name) {
                        merged.aliases = (merged.aliases + [profile.name]).sorted()
                    }
                    mergedMap[best.id] = merged
                }
            }
            if !toRemove.isEmpty {
                inferred.removeAll { toRemove.contains($0.id) || mergedMap.keys.contains($0.id) }
                inferred.append(contentsOf: mergedMap.values)
            }

            // Phase 3b: resolve aliases (陈无忌 → 无忌, 张公子 → 张无忌)
            if inferred.count >= 2 {
                let names = inferred.map(\.name)
                let resolved = CharacterAnalyzer.resolveAliases(names)
                for (canonical, aliases) in resolved where !aliases.isEmpty {
                    if let idx = inferred.firstIndex(where: { $0.name == canonical }) {
                        let existing = Set(inferred[idx].aliases)
                        inferred[idx].aliases = (inferred[idx].aliases + aliases.filter { !existing.contains($0) }).sorted()
                    }
                }
            }

            scanProgress = 1.0
            scanPhase = "扫描完成"
            elapsedText = ""
            etaText = ""
            store.characters.removeAll { $0.bookID == nil || $0.bookID == book.id }
            store.characters.append(contentsOf: inferred)
            store.lastScannedBookText = text
            store.updateRecommendations(from: text)
            store.saveState()
            isScanning = false
            store.statusMessage = "扫描完成，识别 \(store.characters.count) 个角色，耗时 \(formatDuration(Date().timeIntervalSince(startTime)))"
        }
    }

    // MARK: - Generate Sample

    private func generateSample(_ profile: CharacterProfile) {
        Task {
            store.statusMessage = "正在生成试听..."
            let sampleText = "你好，我是\(profile.name)。"
            do {
                let audioData = try await EdgeTTSService.shared.synthesize(text: sampleText, voice: profile.voiceID.isEmpty ? nil : profile.voiceID)
                let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample-\(UUID().uuidString).\(ext)")
                try audioData.write(to: url, options: .atomic)
                await store.audioController.playFilesAndWait([url])
                store.statusMessage = "试听已开始播放"
            } catch {
                store.statusMessage = "试听生成失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Export / Import

    private func exportCharacters() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(bookCharacters) else {
            store.statusMessage = "导出失败"
            return
        }
        exportData = data
        showExporter = true
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

// MARK: - JSON Document for file export

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
