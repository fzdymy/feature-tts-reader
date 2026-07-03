import SwiftUI
import UniformTypeIdentifiers

struct CharacterAssignmentPanel: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book

    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanEstimate: String = ""
    @State private var elapsedText: String = ""
    @State private var etaText: String = ""
    @State private var showScanConfirm = false
    @State private var showTemplatePicker = false
    @State private var editingCharacter: CharacterProfile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportData = Data()
    @State private var scanTimeHistory: [TimeInterval] = []
    @State private var showAllCharacters = false

    private let maxDisplayed = 100

    private var bookCharacters: [CharacterProfile] {
        store.characters
    }

    private var displayedCharacters: [CharacterProfile] {
        showAllCharacters ? bookCharacters : Array(bookCharacters.prefix(maxDisplayed))
    }

    var body: some View {
        Section(header: Text("角色分配 (\(bookCharacters.count) 人)")) {
            scanButton
            templateButton
            characterList
            if bookCharacters.count > maxDisplayed {
                Button(action: { showAllCharacters.toggle() }) {
                    Text(showAllCharacters ? "显示前 \(maxDisplayed) 个" : "显示全部 (\(bookCharacters.count) 个)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if !bookCharacters.isEmpty {
                exportImportButtons
            }
        }
        .sheet(isPresented: $showScanConfirm) {
            scanConfirmSheet
        }
        .sheet(isPresented: $showTemplatePicker) {
            templatePickerSheet
        }
        .sheet(item: $editingCharacter) { profile in
            CharacterEditorView(character: profile, voices: store.voices) { updated in
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
                if store.importVoiceProfiles(from: data) {
                    store.statusMessage = "角色配置已导入"
                }
            case .failure(let e):
                store.statusMessage = "导入失败: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Scan Button

    private var scanButton: some View {
        Button(action: { prepareScan() }) {
            HStack {
                Image(systemName: "person.text.rectangle")
                VStack(alignment: .leading, spacing: 2) {
                    Text("扫描全书角色")
                    if isScanning {
                        HStack(spacing: 4) {
                            if !elapsedText.isEmpty {
                                Text(elapsedText).font(.caption2).foregroundColor(.secondary)
                            }
                            if !etaText.isEmpty {
                                Text("剩余 \(etaText)").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    } else if !scanEstimate.isEmpty {
                        Text(scanEstimate).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isScanning {
                    HStack(spacing: 6) {
                        Text("\(Int(scanProgress * 100))%")
                            .font(.caption).foregroundColor(.accentColor)
                        if scanProgress > 0 {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.7)
                        }
                    }
                } else {
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .disabled(isScanning)
    }

    private func prepareScan() {
        let len = book.text.count
        let wan = Double(len) / 10000
        if len > 50000 {
            scanEstimate = "约 \(len / 50000) 分钟（\(String(format: "%.1f", wan)) 万字）"
        } else if len > 10000 {
            scanEstimate = "约 \(max(1, len / 10000)) 分钟（\(String(format: "%.1f", wan)) 万字）"
        } else {
            scanEstimate = "文本较短，可快速完成（\(String(format: "%.1f", wan)) 万字）"
        }
        showScanConfirm = true
    }

    private var scanConfirmSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                Text("扫描全书角色")
                    .font(.title2).bold()
                Text("将分析文本，识别书中出现的所有角色。")
                    .foregroundColor(.secondary)
                if !scanEstimate.isEmpty {
                    Label(scanEstimate, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if isScanning {
                    VStack(spacing: 8) {
                        ProgressView(value: scanProgress)
                            .progressViewStyle(.linear)
                            .padding(.horizontal)
                        HStack {
                            if !elapsedText.isEmpty {
                                Text("已用 \(elapsedText)").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(Int(scanProgress * 100))%").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            if !etaText.isEmpty {
                                Text("剩余 \(etaText)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                HStack(spacing: 16) {
                    Button(role: .cancel) {
                        showScanConfirm = false
                    } label: {
                        Text("取消").frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isScanning)

                    Button(action: startScan) {
                        Text(isScanning ? "扫描中..." : "开始扫描").frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning)
                }
            }
            .padding(40)
            .navigationTitle("确认扫描")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func startScan() {
        isScanning = true
        scanProgress = 0
        scanTimeHistory = []
        let startTime = Date()
        let text = book.text
        let voices = store.voices
        let defaultSensitivity = store.defaultSensitivity

        Task { @MainActor in
            let totalLen = text.count
            let chunkSize = 50_000
            let totalChunks = max(1, (totalLen + chunkSize - 1) / chunkSize)
            var allNames: [String: Int] = [:]
            var processedChunks = 0

            for i in 0..<totalChunks {
                if Task.isCancelled { break }
                let startIdx = text.index(text.startIndex, offsetBy: i * chunkSize, limitedBy: text.endIndex) ?? text.startIndex
                let endIdx = text.index(startIdx, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
                guard startIdx < endIdx else { break }
                let chunk = text[startIdx..<endIdx]
                let chunkStart = Date()
                let names = await Task.detached(priority: .userInitiated) {
                    CharacterAnalyzer().extractNames(from: String(chunk))
                }.value
                let chunkElapsed = Date().timeIntervalSince(chunkStart)
                scanTimeHistory.append(chunkElapsed)

                for n in names {
                    allNames[n, default: 0] += 1
                }
                processedChunks += 1
                scanProgress = Double(processedChunks) / Double(totalChunks)

                // Update elapsed time
                let totalElapsed = Date().timeIntervalSince(startTime)
                elapsedText = formatDuration(totalElapsed)

                // Estimate remaining based on average chunk time
                if processedChunks >= 3 {
                    let avgChunkTime = scanTimeHistory.reduce(0, +) / Double(scanTimeHistory.count)
                    let remainingChunks = totalChunks - processedChunks
                    let estimatedRemaining = avgChunkTime * Double(remainingChunks)
                    etaText = formatDuration(estimatedRemaining)
                } else if totalChunks > 0 {
                    let remaining = totalChunks - processedChunks
                    let totalEstimate = Double(totalChunks) * chunkElapsed
                    let elapsed = Date().timeIntervalSince(startTime)
                    etaText = formatDuration(max(0, totalEstimate - elapsed))
                }

                await Task.yield()
            }

            // Deduplicate aliases
            let uniqueNames = allNames.keys.sorted { allNames[$0, default: 0] > allNames[$1, default: 0] }
            let resolved = CharacterAnalyzer.resolveAliases(uniqueNames)
            let usedNames = Set(resolved.map { $0.canonical })

            // Also include unique names that weren't merged (2-char non-surname names etc.)
            var mergedMap: [String: (frequency: Int, aliases: [String])] = [:]
            for (canonical, aliases) in resolved {
                let freq = allNames[canonical, default: 0]
                let aliasFreq = aliases.reduce(0) { $0 + allNames[$1, default: 0] }
                mergedMap[canonical] = (freq + aliasFreq, aliases)
            }
            for (name, freq) in allNames where !usedNames.contains(name) && !name.isEmpty {
                if mergedMap[name] == nil {
                    mergedMap[name] = (freq, [])
                }
            }

            let sortedProfiles = mergedMap.sorted { $0.value.frequency > $1.value.frequency }

            var inferred: [CharacterProfile] = sortedProfiles.map { name, data in
                let gender = store.guessGender(from: name) ? "男性" : "女性"
                let baseVoice = gender == "男性"
                    ? defaultMaleVoice(voices: voices)
                    : defaultFemaleVoice(voices: voices)
                return CharacterProfile(
                    id: UUID(), name: name, aliases: data.aliases,
                    gender: gender, age: "未知", tone: "平稳",
                    voice: baseVoice,
                    rate: 0, pitch: 0, style: "neutral", sensitivity: defaultSensitivity
                )
            }

            if inferred.isEmpty {
                inferred = [CharacterProfile(id: UUID(), name: "叙述者", aliases: [], gender: "未知",
                    age: "未知", tone: "平稳",
                    voice: store.defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: voices),
                    rate: 0, pitch: 0, style: "neutral", sensitivity: defaultSensitivity)]
            } else if !inferred.contains(where: { $0.isNarrator }) {
                inferred.insert(CharacterProfile(
                    id: UUID(), name: "旁白", aliases: [], gender: "未知", age: "未知", tone: "平稳",
                    voice: store.defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: voices),
                    rate: 0, pitch: 0, style: "neutral", sensitivity: defaultSensitivity,
                    isNarrator: true, role: .narrator
                ), at: 0)
            }
            store.characters = inferred
            store.lastScannedBookText = text
            store.updateRecommendations(from: text)
            store.saveState()
            isScanning = false
            showScanConfirm = false
            elapsedText = ""
            etaText = ""
            store.statusMessage = "扫描完成，识别 \(store.characters.count) 个角色，合并 \(resolved.reduce(0) { $0 + $1.aliases.count }) 个别名"
        }
    }

    private func defaultMaleVoice(voices: [VoiceItem]) -> String {
        let options = voices.isEmpty ? VoiceItem.defaultItems() : voices
        if let v = options.first(where: { $0.gender == .male }) {
            return v.id
        }
        return "zh-CN-YunyeNeural"
    }

    private func defaultFemaleVoice(voices: [VoiceItem]) -> String {
        let options = voices.isEmpty ? VoiceItem.defaultItems() : voices
        if let v = options.first(where: { $0.gender == .female }) {
            return v.id
        }
        return "zh-CN-XiaoxiaoNeural"
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

    // MARK: - Template Button

    private var templateButton: some View {
        Button(action: { showTemplatePicker = true }) {
            HStack {
                Image(systemName: "square.on.square")
                Text("使用系统自带模板")
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
        }
    }

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
                            applyTemplate(template)
                            showTemplatePicker = false
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
                    Button("取消") { showTemplatePicker = false }
                }
            }
        }
    }

    private func applyTemplate(_ template: RoleTemplate) {
        store.applyTemplate(template)
        store.saveState()
    }

    // MARK: - Character List

    private var characterList: some View {
        Group {
            if bookCharacters.isEmpty {
                Text("尚未分配角色，请扫描或应用模板。")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(displayedCharacters) { profile in
                    characterRow(profile)
                }
                .onDelete(perform: deleteCharacters)
            }
        }
    }

    private func deleteCharacters(at offsets: IndexSet) {
        let toDelete = offsets.map { displayedCharacters[$0].id }
        store.characters.removeAll { toDelete.contains($0.id) }
        store.saveState()
    }

    private func deleteCharacter(_ profile: CharacterProfile) {
        store.characters.removeAll { $0.id == profile.id }
        store.saveState()
    }

    private func characterRow(_ profile: CharacterProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name).font(.subheadline).fontWeight(.medium)
                    if profile.isNarrator {
                        Text("旁白").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15)).cornerRadius(4)
                    }
                    if profile.role != .character {
                        Text(profile.role.displayName)
                            .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.12)).cornerRadius(4)
                    }
                    if !profile.aliases.isEmpty {
                        ForEach(profile.aliases.prefix(3), id: \.self) { alias in
                            Text(alias).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12)).cornerRadius(4)
                        }
                        if profile.aliases.count > 3 {
                            Text("+\(profile.aliases.count - 3)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                HStack(spacing: 4) {
                    if !profile.gender.isEmpty {
                        Text(profile.gender).font(.caption2).foregroundColor(.secondary)
                    }
                    if !profile.age.isEmpty {
                        Text(profile.age).font(.caption2).foregroundColor(.secondary)
                    }
                    if !profile.tone.isEmpty {
                        Text(profile.tone).font(.caption2).foregroundColor(.secondary)
                    }
                    if !profile.gender.isEmpty || !profile.age.isEmpty || !profile.tone.isEmpty {
                        Text("·").font(.caption2).foregroundColor(.secondary)
                    }
                    voiceDetailText(profile)
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: { editingCharacter = profile }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            Button(action: { deleteCharacter(profile) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func voiceDetailText(_ profile: CharacterProfile) -> Text {
        var parts: [String] = []
        if let voice = store.voices.first(where: { $0.id == profile.voice }) {
            parts.append(voice.name)
        } else if !profile.voice.isEmpty {
            parts.append(profile.voice)
        }
        if !profile.style.isEmpty && profile.style != "neutral" {
            parts.append(styleName(profile.style))
        }
        if profile.rate != 0 {
            parts.append("语速\(profile.rate > 0 ? "+" : "")\(profile.rate)")
        }
        if profile.pitch != 0 {
            parts.append("语调\(profile.pitch > 0 ? "+" : "")\(profile.pitch)")
        }
        return Text(parts.isEmpty ? "未分配音色" : parts.joined(separator: " · "))
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

    // MARK: - Export/Import

    private var exportImportButtons: some View {
        Group {
            Button(action: exportCharacters) {
                Label("导出角色配置", systemImage: "square.and.arrow.up")
            }
            Button(action: { showImporter = true }) {
                Label("导入角色配置", systemImage: "square.and.arrow.down")
            }
        }
        .font(.caption)
    }

    private func exportCharacters() {
        guard let data = store.exportVoiceProfiles() else {
            store.statusMessage = "导出失败"
            return
        }
        exportData = data
        showExporter = true
    }
}
