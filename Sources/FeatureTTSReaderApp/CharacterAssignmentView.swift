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
    @State private var showTemplatePicker = false
    @State private var editingCharacter: CharacterProfile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportData = Data()
    @State private var showAllCharacters = false
    @State private var showAliasEditor = false
    @State private var editingAliasProfile: CharacterProfile?
    @State private var newAliasText = ""

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
            if !bookCharacters.isEmpty {
                Button(role: .destructive) {
                    store.characters = []
                    store.saveState()
                } label: {
                    HStack {
                        Image(systemName: "trash").font(.caption)
                        Text("清空角色分配列表").font(.caption)
                    }
                }
                .foregroundColor(.red)
            }
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
        .sheet(isPresented: $showAliasEditor) {
            if let profile = editingAliasProfile {
                aliasEditSheet(profile)
            }
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
        Button(action: { startScan() }) {
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
                        if !scanPhase.isEmpty {
                            Text(scanPhase).font(.caption2).foregroundColor(.secondary)
                        }
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

    private func startScan() {
        isScanning = true
        scanProgress = 0
        elapsedText = ""
        etaText = ""
        let startTime = Date()
        let text = book.text
        let voices = store.voices
        let defaultSensitivity = store.defaultSensitivity

        let chunkSize = 50_000
        let totalLen = text.count
        let totalChunks = max(1, (totalLen + chunkSize - 1) / chunkSize)
        var candidateScores = [String: Int]()

        Task { @MainActor in
            // Phase 1: dialogue regex on chunks (with progress)
            for i in 0..<totalChunks {
                if Task.isCancelled { isScanning = false; return }
                let startIdx = text.index(text.startIndex, offsetBy: i * chunkSize, limitedBy: text.endIndex) ?? text.startIndex
                let endIdx = text.index(startIdx, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
                guard startIdx < endIdx else { break }
                let chunk = String(text[startIdx..<endIdx])
                let names = await Task.detached(priority: .userInitiated) {
                    CharacterAnalyzer().extractDialogueNames(from: chunk)
                }.value
                for n in names {
                    candidateScores[n, default: 0] += 1
                }
                scanProgress = Double(i + 1) / Double(totalChunks)
                let totalElapsed = Date().timeIntervalSince(startTime)
                elapsedText = formatDuration(totalElapsed)
                if i >= 3 && totalChunks > i + 1 {
                    let avgPerChunk = totalElapsed / Double(i + 1)
                    let eta = avgPerChunk * Double(totalChunks - i - 1)
                    etaText = formatDuration(eta)
                }
                await Task.yield()
            }

            // Phase 2: AC automaton on full text
            scanPhase = "频率统计中..."
            scanProgress = 0.91
            let acScores = await Task.detached(priority: .userInitiated) {
                CharacterAnalyzer().countWithAC(text: text, candidates: candidateScores)
            }.value

            // Phase 3: NL NER on dialogue paragraphs
            scanPhase = "智能识别补全中..."
            scanProgress = 0.95
            let nlScores = await Task.detached(priority: .background) {
                CharacterAnalyzer().extractNLMissing(text: text, known: acScores)
            }.value

            var scores = acScores
            for (name, count) in nlScores {
                scores[name, default: 0] += count * 15
            }

            let totalElapsed = Date().timeIntervalSince(startTime)
            elapsedText = formatDuration(totalElapsed)
            scanProgress = 1.0

            // Sort & filter
            let uniqueNames = scores.keys.sorted { scores[$0, default: 0] > scores[$1, default: 0] }
            let resolved = CharacterAnalyzer.resolveAliases(uniqueNames)
            let usedNames = Set(resolved.map { $0.canonical })
            let minFreq = max(3, totalLen / 50000)
            var mergedMap: [String: (frequency: Int, aliases: [String])] = [:]
            func isValidCharacterName(_ name: String, freq: Int) -> Bool {
                if freq < minFreq { return false }
                if name.count == 1 { return false }
                if name.count == 2 && !CharacterAnalyzer.firstCharIsSurname(name) { return false }
                return true
            }
            for (canonical, aliases) in resolved {
                let freq = scores[canonical, default: 0]
                let aliasFreq = aliases.reduce(0) { $0 + scores[$1, default: 0] }
                let total = freq + aliasFreq
                if isValidCharacterName(canonical, freq: total) {
                    mergedMap[canonical] = (total, aliases)
                }
            }
            for (name, freq) in scores where !usedNames.contains(name) && !name.isEmpty {
                if mergedMap[name] == nil && isValidCharacterName(name, freq: freq) {
                    mergedMap[name] = (freq, [])
                }
            }

            let sortedProfiles = mergedMap.sorted { $0.value.frequency > $1.value.frequency }

            // Attribute inference
            let contextLimit = min(500_000, totalLen)
            let contextText = text.prefix(contextLimit)
            let analyzer = CharacterAnalyzer()
            var inferred: [CharacterProfile] = []

            for (name, data) in sortedProfiles {
                var gender = "未知"
                var age = "未知"
                var tone = "平稳"
                var style = "neutral"
                var rate = 0
                var pitch = 0

                if let range = contextText.range(of: name) {
                    let ctxStart = contextText.index(range.lowerBound, offsetBy: -50, limitedBy: contextText.startIndex) ?? contextText.startIndex
                    let ctxEnd = contextText.index(range.upperBound, offsetBy: 150, limitedBy: contextText.endIndex) ?? contextText.endIndex
                    let ctx = String(contextText[ctxStart..<ctxEnd])
                    let attrs = analyzer.analyzeAttributes(for: name, context: ctx)
                    gender = attrs.gender
                    age = attrs.age
                    tone = attrs.baseTone
                    style = attrs.baseStyle
                    rate = attrs.baseRate
                    pitch = attrs.basePitch
                }

                if gender == "未知" {
                    gender = store.guessGender(from: name) ? "男性" : "女性"
                }

                let baseVoice = store.defaultVoice(for: gender, tone: tone, name: name, voices: voices)

                inferred.append(CharacterProfile(
                    id: UUID(), name: name, aliases: data.aliases,
                    gender: gender, age: age, tone: tone,
                    voice: baseVoice,
                    rate: rate, pitch: pitch, style: style, sensitivity: defaultSensitivity
                ))
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
            elapsedText = ""
            etaText = ""
            store.statusMessage = "扫描完成，识别 \(store.characters.count) 个角色，耗时 \(formatDuration(Date().timeIntervalSince(startTime)))"
        }
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
            HStack(spacing: 4) {
                Button(action: {
                    editingCharacter = store.characters.first(where: { $0.id == profile.id })
                }) {
                    VStack(spacing: 1) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16))
                        Text("微调").font(.system(size: 9))
                    }
                    .foregroundColor(.accentColor)
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: { deleteCharacter(profile) }) {
                    VStack(spacing: 1) {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                        Text("删除").font(.system(size: 9))
                    }
                    .foregroundColor(.red)
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(action: { editingCharacter = store.characters.first(where: { $0.id == profile.id }) }) {
                Label("微调角色", systemImage: "slider.horizontal.3")
            }
            Button(action: {
                editingAliasProfile = profile
                showAliasEditor = true
            }) {
                Label("编辑别名/标签", systemImage: "tag")
            }
            Divider()
            Button(role: .destructive, action: { deleteCharacter(profile) }) {
                Label("删除角色", systemImage: "trash")
            }
        }
    }

    private func aliasEditSheet(_ profile: CharacterProfile) -> some View {
        NavigationStack {
            Form {
                Section(header: Text("当前别名/标签")) {
                    if profile.aliases.isEmpty {
                        Text("无别名标签").foregroundColor(.secondary)
                    }
                    ForEach(profile.aliases, id: \.self) { alias in
                        HStack {
                            Text(alias).font(.subheadline)
                            Spacer()
                            Button(action: {
                                if let i = store.characters.firstIndex(where: { $0.id == profile.id }) {
                                    store.characters[i].aliases.removeAll { $0 == alias }
                                    store.saveState()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section(header: Text("添加新别名")) {
                    HStack {
                        TextField("输入别名", text: $newAliasText)
                            .font(.subheadline)
                        Button("添加") {
                            let trimmed = newAliasText.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            if let i = store.characters.firstIndex(where: { $0.id == profile.id }) {
                                if !store.characters[i].aliases.contains(trimmed) {
                                    store.characters[i].aliases.append(trimmed)
                                    store.saveState()
                                }
                            }
                            newAliasText = ""
                        }
                        .disabled(newAliasText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section(header: Text("提示")) {
                    Text("别名用于匹配同一角色的不同称呼，如「无忌」「张公子」都会匹配到「张无忌」。长按角色行也可进入此菜单。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("编辑别名: \(profile.name)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showAliasEditor = false; newAliasText = "" }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 8) {
            Button(action: exportCharacters) {
                HStack {
                    Image(systemName: "square.and.arrow.up").font(.caption)
                    Text("导出角色配置").font(.caption)
                }
            }
            Button(action: { showImporter = true }) {
                HStack {
                    Image(systemName: "square.and.arrow.down").font(.caption)
                    Text("导入角色配置").font(.caption)
                }
            }
        }
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
