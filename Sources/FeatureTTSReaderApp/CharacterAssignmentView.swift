import SwiftUI
import UniformTypeIdentifiers

struct CharacterAssignmentPanel: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book

    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanEstimate: String = ""
    @State private var showScanConfirm = false
    @State private var showTemplatePicker = false
    @State private var editingCharacter: CharacterProfile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportData = Data()

    private var bookCharacters: [CharacterProfile] {
        store.characters
    }

    var body: some View {
        Section(header: Text("角色分配")) {
            scanButton
            templateButton
            characterList
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
                    if !scanEstimate.isEmpty {
                        Text(scanEstimate).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isScanning {
                    if scanProgress > 0 {
                        Text("\(Int(scanProgress * 100))%")
                            .font(.caption).foregroundColor(.accentColor)
                    } else {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
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
                    ProgressView(value: scanProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal)
                    Text("\(Int(scanProgress * 100))%")
                        .font(.caption).foregroundColor(.secondary)
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
        Task {
            let chunkSize = max(book.text.count / 10, 1)
            var allNames: [String: Int] = [:]
            let analyzer = CharacterAnalyzer()
            await withTaskGroup(of: (chunkIndex: Int, names: [String: Int]).self) { group in
                for i in 0..<10 {
                    let start = i * chunkSize
                    let end = min(start + chunkSize, book.text.count)
                    guard start < end else { break }
                    let chunk = String(book.text[book.text.index(book.text.startIndex, offsetBy: start)..<book.text.index(book.text.startIndex, offsetBy: end)])
                    group.addTask {
                        let names = analyzer.extractCharacterNames(from: chunk)
                        var map: [String: Int] = [:]
                        for n in names { map[n, default: 0] += 1 }
                        return (i, map)
                    }
                }
                for await result in group {
                    for (name, count) in result.names {
                        allNames[name, default: 0] += count
                    }
                    await MainActor.run {
                        scanProgress = Double(result.chunkIndex + 1) / 10.0
                    }
                }
            }
            var inferred = allNames.sorted { $0.value > $1.value }.map { name, count in
                CharacterProfile(
                    id: UUID(),
                    name: name.key,
                    gender: "",
                    age: "",
                    tone: "",
                    voice: store.defaultVoice(for: "", tone: "", name: name.key, voices: store.voices),
                    rate: 0,
                    pitch: 0,
                    style: "neutral",
                    sensitivity: store.defaultSensitivity
                )
            }
            if inferred.isEmpty {
                inferred = [CharacterProfile(id: UUID(), name: "叙述者", gender: "未知", age: "未知", tone: "中性",
                    voice: store.defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: store.voices),
                    rate: 0, pitch: 0, style: "neutral", sensitivity: store.defaultSensitivity)]
            } else if !inferred.contains(where: { $0.isNarrator }) {
                inferred.insert(CharacterProfile(
                    id: UUID(), name: "旁白", gender: "未知", age: "未知", tone: "平稳",
                    voice: store.defaultVoice(for: "未知", tone: "平稳", role: "旁白", voices: store.voices),
                    rate: 0, pitch: 0, style: "neutral", sensitivity: store.defaultSensitivity,
                    isNarrator: true, role: .narrator
                ), at: 0)
            }
            await MainActor.run {
                store.characters = inferred
                store.lastScannedBookText = book.text
                store.updateRecommendations(from: book.text)
                store.saveState()
                isScanning = false
                showScanConfirm = false
                store.statusMessage = "扫描完成，识别 \(store.characters.count) 个角色"
            }
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
                ForEach(bookCharacters) { profile in
                    characterRow(profile)
                }
            }
        }
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
                        ForEach(profile.aliases.prefix(2), id: \.self) { alias in
                            Text(alias).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12)).cornerRadius(4)
                        }
                    }
                    if !profile.info.isEmpty {
                        Text(profile.info).font(.caption2).foregroundColor(.secondary)
                    }
                }
                voiceDetailText(profile)
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { editingCharacter = profile }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundColor(.accentColor)
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
