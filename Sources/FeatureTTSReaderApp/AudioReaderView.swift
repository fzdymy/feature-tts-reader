import SwiftUI
import UIKit
import Combine

// MARK: - AudioReaderView (朗读听书 + 多角色配音自动化）

struct AudioReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let bookID: UUID
    @State var startChapterIndex: Int

    @State private var currentChapterIndex: Int
    @State private var displayedChapterTitle: String
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 1.0
    @State private var currentTime = Date()
    @State private var batteryLevel: Int = 100
    @State private var showCharacterPanel = false
    @State private var editingCharacter: CharacterProfile?
    @State private var showVoiceCatalogPicker = false
    @State private var showAddCharacter = false
    @State private var showAllRecommendations = false
    @State private var selectedTextForCharacter = ""
    @State private var showCharacterFromText = false

    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init(book: Book, bookID: UUID, chapterIndex: Int) {
        self.book = book
        self.bookID = bookID
        self.startChapterIndex = chapterIndex
        self._currentChapterIndex = State(initialValue: chapterIndex)
        self._displayedChapterTitle = State(initialValue: "")
    }

    private var chapters: [BookChapter]? {
        store.chaptersForBookCached(bookID)
    }

    private var currentChapter: BookChapter? {
        guard let chs = chapters, currentChapterIndex < chs.count else { return nil }
        return chs[currentChapterIndex]
    }

    private var chapterDisplayText: String {
        guard let ch = currentChapter else { return "" }
        return "\u{3000}\u{3000}" + ch.text
            .replacingOccurrences(of: "\n", with: "\n\u{3000}\u{3000}")
    }

    private var textColor: Color {
        switch store.readerTheme {
        case .dark: return .white
        case .light: return Color(red: 0.1, green: 0.1, blue: 0.1)
        case .sepia: return Color(red: 0.2, green: 0.18, blue: 0.15)
        }
    }

    private var bgColor: Color {
        if store.customBackgroundImage != nil { return Color.clear }
        switch store.readerTheme {
        case .dark: return .black
        case .light: return .white
        case .sepia: return Color(red: 0.98, green: 0.93, blue: 0.82)
        }
    }

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            VStack(spacing: 0) {
                audioHeader
                if showCharacterPanel {
                    characterPanel
                        .frame(maxHeight: max(UIScreen.main.bounds.height * 0.35, 300))
                }
                SelectableTextReader(
                    text: chapterDisplayText,
                    fontName: store.readerFontName,
                    fontSize: store.readerFontSize + 2,
                    textColor: UIColor(textColor),
                    lineSpacing: store.readerLineSpacing + 4,
                    onSelect: { selectedText in
                        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.count >= 2 && trimmed.count <= 4 else { return }
                        selectedTextForCharacter = trimmed
                        showCharacterFromText = true
                    }
                )
                automationToolbar
                audioControlBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .statusBarHidden(false)
        .onReceive(timer) { _ in
            currentTime = Date()
            updateBatteryLevel()
        }
        .onAppear {
            updateBatteryLevel()
            if displayedChapterTitle.isEmpty,
               let chs = chapters, currentChapterIndex < chs.count {
                displayedChapterTitle = chs[currentChapterIndex].title
            }
            store.selectedChapterID = currentChapter?.id
        }
        .sheet(item: $editingCharacter) { character in
            CharacterEditorView(
                character: character,
                voices: store.voices.isEmpty ? VoiceItem.defaultItems() : store.voices
            ) { updated in
                if let idx = store.characters.firstIndex(where: { $0.id == updated.id }) {
                    store.characters[idx] = updated
                    store.updateRecommendations()
                    store.saveState()
                }
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $showAddCharacter) {
            AddCharacterView { name, gender, age, tone in
                store.addCharacter(name: name, gender: gender, age: age, tone: tone)
                showAddCharacter = false
            }
        }
        .sheet(isPresented: $showAllRecommendations) {
            AllRecommendationsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showCharacterFromText) {
            QuickCharacterAddView(
                candidateName: selectedTextForCharacter,
                bookText: store.bookText,
                existingCharacters: store.characters,
                onAdd: { name, gender, age, tone in
                    store.addCharacter(name: name, gender: gender, age: age, tone: tone)
                },
                onEdit: { character in
                    editingCharacter = character
                }
            )
            .environmentObject(store)
        }
    }

    // MARK: - Header

    private var audioHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(textColor.opacity(0.7))
            }
            Text(displayedChapterTitle)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(textColor)
                .padding(.leading, 8)
            Spacer()
            Text("选中文本中的人名可直接添加为角色")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Button(action: { showCharacterPanel.toggle() }) {
                Image(systemName: showCharacterPanel ? "person.2.fill" : "person.2")
                    .font(.title3)
                    .foregroundColor(showCharacterPanel ? .blue : textColor.opacity(0.7))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(bgColor.opacity(0.9))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Character Panel (多角色配音自动化核心)

    private var characterPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    voiceCatalogRow
                    automationRow
                    if !store.recommendations.isEmpty {
                        recommendationSection
                    }
                    if !store.characters.isEmpty {
                        characterListSection
                    } else {
                        emptyStateHint
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Divider()
        }
        .background(bgColor.opacity(0.95))
    }

    // MARK: 音色库选择

    private var voiceCatalogRow: some View {
        HStack(spacing: 10) {
            Text("音色库")
                .font(.subheadline)
                .foregroundColor(textColor)
            Button(action: { store.switchCatalog(to: .chinese35) }) {
                Text("经典(40)")
                    .font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(store.selectedVoiceCatalog == .chinese35 ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(store.selectedVoiceCatalog == .chinese35 ? .white : textColor)
                    .cornerRadius(6)
            }
            .buttonStyle(.borderless)
            Button(action: { store.switchCatalog(to: .fullChinese) }) {
                Text("全音色(76)")
                    .font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(store.selectedVoiceCatalog == .fullChinese ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(store.selectedVoiceCatalog == .fullChinese ? .white : textColor)
                    .cornerRadius(6)
            }
            .buttonStyle(.borderless)
            Spacer()
            Text("\(store.voices.count)个")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: 自动化流程按钮

    private var automationRow: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await store.scanCharacters() } }) {
                Label("扫描角色", systemImage: "person.badge.plus")
                    .font(.caption).padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(8)
            }
            .buttonStyle(.borderless)
            Button(action: { Task { await store.buildScript(for: true) } }) {
                Label("生成脚本", systemImage: "doc.richtext")
                    .font(.caption).padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)
            }
            .buttonStyle(.borderless)
            Button(action: {
                store.autoApplyRecommendedToAll()
                Task { await store.buildScript(for: true) }
            }) {
                Label("一键配音", systemImage: "wand.and.stars")
                    .font(.caption).padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: 推荐音色

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("推荐音色")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(textColor)
                Spacer()
                Button("应用到未映射") { store.applyRecommendationsToUnmapped() }
                    .font(.caption).buttonStyle(.borderless)
                Button("全部应用") { store.autoApplyRecommendedToAll() }
                    .font(.caption).buttonStyle(.borderless)
            }
            ForEach(store.recommendations.prefix(3)) { rec in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(rec.profile.name)
                            .font(.caption).fontWeight(.medium)
                            .foregroundColor(textColor)
                        Text("x\(rec.count)")
                            .font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        if let v = rec.suggestedVoices.first {
                            Text(v.name)
                                .font(.caption2).foregroundColor(.blue)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(rec.suggestedVoices.prefix(4)) { voice in
                                Button(action: { store.applyVoice(voice.id, toCharacterID: rec.id) }) {
                                    Text(voice.name)
                                        .font(.caption2)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(6)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .padding(8)
                .background(textColor.opacity(0.05))
                .cornerRadius(8)
            }
            if store.recommendations.count > 3 {
                Button("查看全部 \(store.recommendations.count) 个推荐") {
                    showAllRecommendations = true
                }
                .font(.caption).foregroundColor(.secondary)
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: 角色列表

    private var characterListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("角色列表")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(textColor)
                Spacer()
                Button(action: { store.sortCharactersByAppearance() }) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                Button(action: { showAddCharacter = true }) {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
            }
            ForEach(store.characters) { character in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(character.name)
                                .font(.caption).fontWeight(.medium)
                                .foregroundColor(textColor)
                            if character.isNarrator {
                                Text("旁白")
                                    .font(.caption2).foregroundColor(.orange)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                        Text("\(character.voice)")
                            .font(.caption2).foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: { Task { await store.previewVoice(for: character) } }) {
                        Image(systemName: "play.circle")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.borderless)
                    Button(action: { editingCharacter = character }) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    Button(action: { store.deleteCharacter(at: character.id) }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(textColor.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }

    private var emptyStateHint: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "person.3")
                    .font(.title2).foregroundColor(.secondary)
                Text("选中文本中的人名即可快速添加为角色")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.vertical, 16)
            Spacer()
        }
    }

    // MARK: 自动化工具栏（常驻）

    private var automationToolbar: some View {
        HStack(spacing: 12) {
            Button(action: { showCharacterPanel.toggle() }) {
                Label(
                    store.characters.isEmpty ? "角色管理" : "角色(\(store.characters.count))",
                    systemImage: "person.2"
                )
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundColor(showCharacterPanel ? .blue : textColor)

            Spacer()

            Button(action: { Task { await store.scanCharacters() } }) {
                Label("扫描", systemImage: "person.badge.plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundColor(textColor)

            Button(action: { Task { await store.buildScript(for: true) } }) {
                Label("脚本", systemImage: "doc.richtext")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundColor(textColor)

            if !store.scriptSegments.isEmpty {
                Text("\(store.scriptSegments.count)段")
                    .font(.caption2).foregroundColor(.secondary)
            }

            if store.isBusy {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(bgColor.opacity(0.9))
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Control Bar

    private var audioControlBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text("00:00").font(.caption2).foregroundColor(textColor.opacity(0.5)).monospacedDigit()
                Slider(value: $playbackProgress, in: 0...1)
                    .accentColor(.blue)
                Text("--:--").font(.caption2).foregroundColor(textColor.opacity(0.5)).monospacedDigit()
            }
            .padding(.horizontal, 20)

            HStack(spacing: 24) {
                Button(action: previousChapter) {
                    Image(systemName: "backward.end.fill").font(.title2)
                }
                .disabled(currentChapterIndex <= 0)

                Button(action: {
                    isPlaying.toggle()
                    if isPlaying {
                        Task { await startPlayback() }
                    } else {
                        store.stopPlayback()
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                }

                Button(action: nextChapter) {
                    Image(systemName: "forward.end.fill").font(.title2)
                }
                .disabled(currentChapterIndex >= (chapters?.count ?? 1) - 1)
            }
            .foregroundColor(textColor)

            HStack(spacing: 16) {
                speedButton("0.75x", speed: 0.75)
                speedButton("1.0x", speed: 1.0)
                speedButton("1.25x", speed: 1.25)
                speedButton("1.5x", speed: 1.5)
                speedButton("2.0x", speed: 2.0)
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @State private var playbackProgress: Double = 0

    private func speedButton(_ label: String, speed: Double) -> some View {
        Button(action: { playbackSpeed = speed }) {
            Text(label)
                .font(.caption)
                .fontWeight(playbackSpeed == speed ? .bold : .regular)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(playbackSpeed == speed ? Color.blue.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                .foregroundColor(playbackSpeed == speed ? .blue : textColor.opacity(0.6))
        }
    }

    // MARK: - Navigation

    private func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        displayedChapterTitle = chapters?[currentChapterIndex].title ?? ""
        store.selectedChapterID = chapters?[currentChapterIndex].id
        ReaderStore.saveLastChapterIndex(currentChapterIndex, for: bookID)
        isPlaying = false
        store.stopPlayback()
    }

    private func nextChapter() {
        guard let chs = chapters, currentChapterIndex < chs.count - 1 else { return }
        if currentChapterIndex < chs.count {
            store.setChapterProgress(chs[currentChapterIndex].id, percent: 1.0)
        }
        currentChapterIndex += 1
        displayedChapterTitle = chs[currentChapterIndex].title
        store.selectedChapterID = chs[currentChapterIndex].id
        ReaderStore.saveLastChapterIndex(currentChapterIndex, for: bookID)
        isPlaying = false
        store.stopPlayback()
    }

    private func startPlayback() async {
        guard let chapter = currentChapter else { return }
        await store.playChapterWithTTS(chapter: chapter)
        isPlaying = false
    }

    private func updateBatteryLevel() {
        guard !UIDevice.current.isBatteryMonitoringEnabled else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel >= 0
            ? Int(UIDevice.current.batteryLevel * 100) : -1
    }
}

// MARK: - Selectable Text Reader

struct SelectableTextReader: UIViewRepresentable {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    let textColor: UIColor
    let lineSpacing: CGFloat
    let onSelect: (String) -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        updateTextView(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        updateTextView(tv)
    }

    private func updateTextView(_ tv: UITextView) {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = lineSpacing
        let font: UIFont
        if let custom = UIFont(name: fontName, size: fontSize) {
            font = custom
        } else {
            font = UIFont.systemFont(ofSize: fontSize)
        }
        tv.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paraStyle,
            ]
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        let onSelect: (String) -> Void
        private var lastSelection = ""
        private var lastSelectionTime: Date = .distantPast
        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = textView.selectedTextRange, !range.isEmpty else { return }
            let selected = textView.text(in: range) ?? ""
            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 && trimmed.count <= 4 else { return }
            // Avoid re-triggering same selection within 1 second
            guard trimmed != lastSelection || Date().timeIntervalSince(lastSelectionTime) > 1 else { return }
            lastSelection = trimmed
            lastSelectionTime = Date()
            onSelect(trimmed)
        }
    }
}

// MARK: - QuickCharacterAddView

fileprivate struct QuickCharacterAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReaderStore
    let candidateName: String
    let bookText: String
    let existingCharacters: [CharacterProfile]
    let onAdd: (String, String, String, String) -> Void
    let onEdit: (CharacterProfile) -> Void

    @State private var gender: String
    @State private var age: String
    @State private var tone: String
    @State private var recommendedVoice: String
    @State private var showEditSheet = false

    private let analyzer = CharacterAnalyzer()

    init(candidateName: String, bookText: String, existingCharacters: [CharacterProfile],
         onAdd: @escaping (String, String, String, String) -> Void,
         onEdit: @escaping (CharacterProfile) -> Void) {
        self.candidateName = candidateName
        self.bookText = bookText
        self.existingCharacters = existingCharacters
        self.onAdd = onAdd
        self.onEdit = onEdit

        let context = bookText.contextAround(candidateName, radius: 120)
        let attrs = CharacterAnalyzer().analyzeAttributes(for: candidateName, context: context)
        _gender = State(initialValue: attrs.gender)
        _age = State(initialValue: attrs.age)
        _tone = State(initialValue: attrs.baseTone)
        _recommendedVoice = State(initialValue: "")
    }

    private var existingMatch: CharacterProfile? {
        existingCharacters.first(where: { $0.name == candidateName })
    }

    private let genderOptions = ["未知", "男性", "女性"]
    private let ageOptions = ["未知", "少年", "少女", "青年", "中年", "年长"]
    private let toneOptions = ["平稳", "温柔", "激昂", "轻松", "疑问"]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("选中的文本")) {
                    Text("\"\(candidateName)\"")
                        .font(.headline)
                    if let match = existingMatch {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("该角色已存在，可编辑现有角色")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                }

                if existingMatch == nil {
                    Section(header: Text("自动分析结果")) {
                        HStack {
                            Text("性别")
                            Spacer()
                            Text(gender).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("年龄段")
                            Spacer()
                            Text(age).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("语气")
                            Spacer()
                            Text(tone).foregroundColor(.secondary)
                        }
                        if !recommendedVoice.isEmpty {
                            HStack {
                                Text("推荐音色")
                                Spacer()
                                Text(recommendedVoice).foregroundColor(.blue)
                            }
                        }
                    }

                    Section(header: Text("手动调整（可选）")) {
                        Picker("性别", selection: $gender) {
                            ForEach(genderOptions, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("年龄段", selection: $age) {
                            ForEach(ageOptions, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("语气", selection: $tone) {
                            ForEach(toneOptions, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                if existingMatch != nil {
                    Section {
                        Button("编辑现有角色「\(existingMatch!.name)」") {
                            onEdit(existingMatch!)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingMatch != nil ? "角色已存在" : "添加新角色")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if existingMatch == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            onAdd(candidateName, gender, age, tone)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AddCharacterView

fileprivate struct AddCharacterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var gender = "未知"
    @State private var age = "未知"
    @State private var tone = "平稳"
    let onAdd: (String, String, String, String) -> Void

    private let genderOptions = ["未知", "男性", "女性"]
    private let ageOptions = ["未知", "少年", "少女", "青年", "中年", "年长"]
    private let toneOptions = ["平稳", "温柔", "激昂", "轻松", "疑问"]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("角色信息")) {
                    TextField("角色名称", text: $name)
                    Picker("性别", selection: $gender) {
                        ForEach(genderOptions, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("年龄段", selection: $age) {
                        ForEach(ageOptions, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("语气", selection: $tone) {
                        ForEach(toneOptions, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .navigationTitle("新增角色")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onAdd(name.trimmingCharacters(in: .whitespaces), gender, age, tone)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - AllRecommendationsView

fileprivate struct AllRecommendationsView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.recommendations) { rec in
                    Section(header: Text("\(rec.profile.name)（出现 \(rec.count) 次）")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(rec.suggestedVoices) { voice in
                                    Button(action: {
                                        store.applyVoice(voice.id, toCharacterID: rec.id)
                                    }) {
                                        VStack(spacing: 2) {
                                            Text(voice.name)
                                                .font(.caption).fontWeight(.medium)
                                            Text(VoiceCatalog.tier(for: voice.id).displayName)
                                                .font(.caption2)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(10)
                                        .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("全部推荐")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}