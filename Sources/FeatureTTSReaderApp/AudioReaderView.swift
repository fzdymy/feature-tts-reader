import SwiftUI

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
    @State private var selectedCharacter: CharacterProfile?
    @State private var editingCharacter: CharacterProfile?
    @State private var showVoiceCatalogPicker = false

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
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
                }
                ScrollView {
                    Text(chapterDisplayText)
                        .font(Font.custom(store.readerFontName, size: store.readerFontSize + 2))
                        .foregroundColor(textColor)
                        .lineSpacing(store.readerLineSpacing + 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                }
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
                    // 音色库选择
                    voiceCatalogRow

                    // 自动化流程按钮
                    automationRow

                    // 推荐音色
                    if !store.recommendations.isEmpty {
                        recommendationSection
                    }

                    // 角色列表
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
                    selectedCharacter = store.characters.first
                }
                .font(.caption).foregroundColor(.secondary)
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: 角色列表

    private var characterListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("角色列表")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(textColor)
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
                Text("点击「扫描角色」自动识别小说人物")
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
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel >= 0
            ? Int(UIDevice.current.batteryLevel * 100) : -1
    }
}
