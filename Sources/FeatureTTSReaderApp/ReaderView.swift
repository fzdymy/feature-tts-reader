import SwiftUI
import Combine
import UIKit

enum TextAlign: Int, CaseIterable, Identifiable {
    case leading = 0, center = 1, trailing = 2, justified = 3
    var id: Self { self }
    var displayName: String {
        switch self {
        case .leading: return "左对齐"
        case .center: return "居中对齐"
        case .trailing: return "右对齐"
        case .justified: return "两端对齐"
        }
    }
}

// MARK: - ReaderView (unified silent reading + TTS multi-character audio)

struct ReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let bookID: UUID

    // Chapter state
    @State private var currentChapter: BookChapter
    @State private var currentChapterIndex: Int
    @State private var anchorChapterIndex: Int
    @State private var displayedChapterTitle: String
    @State private var chaptersList: [BookChapter] = []

    // UI state – silent reading
    @State private var showBookmarks = false
    @State private var showSettings = false
    @State private var showFontPicker = false
    @State private var showTOC = false
    @State private var isImmersive = false

    // UI state – TTS audio mode
    @State private var isAudioMode = false
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 1.0
    @State private var playbackProgress: Double = 0

    // Character management
    @State private var showCharacterPanel = false
    @State private var editingCharacter: CharacterProfile?
    @State private var showAddCharacter = false
    @State private var showAllRecommendations = false
    @State private var selectedTextForCharacter = ""
    @State private var showCharacterFromText = false

    // Status
    @State private var currentTime = Date()
    @State private var batteryLevel: Int = 100
    @State private var screenBrightness: CGFloat = UIScreen.main.brightness
    @State private var useSystemBrightness = true

    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init(book: Book, chapter: BookChapter, bookID: UUID, chapterIndex: Int) {
        self.book = book
        self.bookID = bookID
        ReaderStore.debugLog("[RVIEW-INIT] bookID=\(bookID.uuidString) chapterIndex=\(chapterIndex)")
        self._currentChapter = State(initialValue: chapter)
        self._currentChapterIndex = State(initialValue: chapterIndex)
        self._anchorChapterIndex = State(initialValue: chapterIndex)
        self._displayedChapterTitle = State(initialValue: chapter.title)
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

    private var chapterDisplayText: String {
        "\u{3000}\u{3000}" + currentChapter.text
            .replacingOccurrences(of: "\n", with: "\n\u{3000}\u{3000}")
    }

    private var chapterBookmarks: [BookBookmark] {
        store.bookmarks.filter { $0.chapterID == currentChapter.id }
    }

    var body: some View {
        ZStack {
            if let data = store.customBackgroundImage, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill().ignoresSafeArea()
            } else {
                bgColor.ignoresSafeArea()
            }

            // ── Silent reading: always in hierarchy ──
            ScrollView {
                Text(chapterDisplayText)
                    .font(Font.custom(store.readerFontName, size: store.readerFontSize))
                    .foregroundColor(textColor)
                    .lineSpacing(store.readerLineSpacing + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                    .textSelection(.enabled)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    withAnimation { isImmersive.toggle() }
                }
            )
            .opacity(isAudioMode ? 0 : 1)
            .allowsHitTesting(!isAudioMode)

            // Header overlay (pinned to top) — silent mode
            if !isImmersive && !isAudioMode {
                VStack {
                    readerHeader
                    Spacer()
                }
            }

            // Control bar overlay (pinned to bottom) — silent mode
            if !isImmersive && !isAudioMode {
                VStack {
                    Spacer()
                    controlBar
                }
            }

            // Immersive overlays — silent mode
            if isImmersive && !isAudioMode {
                if store.showChapterTitle {
                    VStack {
                        HStack {
                            Text(displayedChapterTitle)
                                .font(.caption)
                                .foregroundColor(textColor.opacity(0.6))
                                .lineLimit(1)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                if store.showProgressBar || store.showPageNumber || store.showTime || store.showBattery {
                    VStack {
                        Spacer()
                        readerStatusBar
                    }
                }
            }

            // ── Audio mode: overlay on top, only visible when active ──
            VStack(spacing: 0) {
                readerHeader
                if showCharacterPanel {
                    characterPanel
                        .frame(maxHeight: max(UIScreen.main.bounds.height * 0.35, 300))
                }
                ScrollView {
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                automationToolbar
                audioControlBar
            }
            .opacity(isAudioMode ? 1 : 0)
            .allowsHitTesting(isAudioMode)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(isImmersive || isAudioMode)
        .statusBarHidden(isImmersive || isAudioMode)
        .onReceive(timer) { _ in
            currentTime = Date()
            updateBatteryLevel()
        }
        .onAppear {
            updateBatteryLevel()
            store.selectedChapterID = currentChapter.id
            UIApplication.shared.isIdleTimerDisabled = store.keepScreenOn
            if chaptersList.isEmpty {
                if let cached = store.chaptersForBookCached(bookID) {
                    chaptersList = cached
                } else {
                    let text: String
                    if store.bookText.isEmpty || store.currentBookID != bookID.uuidString {
                        let fileText = store.loadBookTextFromFile(bookID: bookID) ?? ""
                        if fileText.isEmpty {
                            text = book.text
                        } else {
                            text = fileText
                            store.bookText = fileText
                            store.currentBookID = bookID.uuidString
                        }
                    } else {
                        text = store.bookText
                    }
                    chaptersList = store.chaptersForBook(bookID, text: text)
                    if chaptersList.isEmpty { chaptersList = [currentChapter] }
                }
            }
            if let brightness = UserDefaults.standard.object(forKey: "readerBrightness") as? CGFloat {
                screenBrightness = brightness
                useSystemBrightness = false
                UIScreen.main.brightness = brightness
            }
            ReaderStore.debugLog("[RVIEW-APPEAR] idx=\(currentChapterIndex) chaptersList.count=\(chaptersList.count)")
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            ReaderStore.saveLastChapterIndex(anchorChapterIndex, for: bookID)
            if anchorChapterIndex < chaptersList.count {
                store.setChapterProgress(chaptersList[anchorChapterIndex].id, percent: 1.0)
            }
            store.saveState()
            if !useSystemBrightness {
                UIScreen.main.brightness = UserDefaults.standard.object(forKey: "systemBrightness") as? CGFloat ?? 0.5
            }
        }
        .onChange(of: store.externalChapterNavigate) { nav in
            guard let nav, nav.bookID == bookID,
                   nav.chapterIndex < chaptersList.count else { return }
            store.externalChapterNavigate = nil
            jumpTo(nav.chapterIndex, explicit: true)
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView().environmentObject(store).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFontPicker) {
            FontPickerView().environmentObject(store).presentationDetents([.medium])
        }
        .sheet(isPresented: $showTOC) {
            ChapterListView(currentChapterID: currentChapter.id) { chapter, index in
                ReaderStore.debugLog("[TOC] idx=\(index)")
                if !chaptersList.isEmpty {
                    store.setChapterProgress(chaptersList[min(currentChapterIndex, chaptersList.count - 1)].id, percent: 1.0)
                }
                jumpTo(index, explicit: true)
            }
            .environmentObject(store)
            .presentationDetents([.large])
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

    // MARK: - Navigation

    private func jumpTo(_ index: Int, explicit: Bool) {
        guard index >= 0, index < chaptersList.count else { return }
        if isPlaying { store.stopPlayback(); isPlaying = false }
        currentChapterIndex = index
        currentChapter = chaptersList[index]
        displayedChapterTitle = chaptersList[index].title
        store.selectedChapterID = chaptersList[index].id
        ReaderStore.saveLastChapterIndex(index, for: bookID)
        if explicit { anchorChapterIndex = index }
        let lower = max(0, index - 2)
        let upper = min(chaptersList.count - 1, index + 2)
        DispatchQueue.global(qos: .background).async {
            for i in lower...upper where i != index {
                _ = chaptersList[i].text
            }
        }
        ReaderStore.debugLog("[JUMP] idx=\(index)")
    }

    private func previousChapter() {
        guard currentChapterIndex > 0, currentChapterIndex < chaptersList.count else { return }
        let idx = currentChapterIndex - 1
        if isAudioMode {
            displayedChapterTitle = chaptersList[idx].title
            store.selectedChapterID = chaptersList[idx].id
            ReaderStore.saveLastChapterIndex(idx, for: bookID)
            isPlaying = false
            store.stopPlayback()
            currentChapterIndex = idx
            currentChapter = chaptersList[idx]
        } else {
            if idx + 1 < chaptersList.count {
                store.setChapterProgress(chaptersList[idx + 1].id, percent: 1.0)
            }
            jumpTo(idx, explicit: true)
        }
    }

    private func nextChapter() {
        guard currentChapterIndex < chaptersList.count - 1 else { return }
        let idx = currentChapterIndex + 1
        if isAudioMode {
            store.setChapterProgress(chaptersList[currentChapterIndex].id, percent: 1.0)
            displayedChapterTitle = chaptersList[idx].title
            store.selectedChapterID = chaptersList[idx].id
            ReaderStore.saveLastChapterIndex(idx, for: bookID)
            isPlaying = false
            store.stopPlayback()
            currentChapterIndex = idx
            currentChapter = chaptersList[idx]
        } else {
            store.setChapterProgress(chaptersList[currentChapterIndex].id, percent: 1.0)
            jumpTo(idx, explicit: true)
        }
    }

    private func startPlayback() async {
        guard currentChapterIndex < chaptersList.count else { return }
        let chapter = chaptersList[currentChapterIndex]
        store.audioController.playbackRate = Float(playbackSpeed)
        if store.characters.isEmpty {
            store.statusMessage = "未检测到角色，正在自动扫描..."
            await store.scanCharacters()
        }
        if store.scriptSegments.isEmpty || store.lastScannedBookText != store.bookText {
            await store.buildScript(for: false)
        }
        await store.playChapterWithTTS(chapter: chapter)
        isPlaying = false
    }

    // MARK: - Header

    private var readerHeader: some View {
        HStack {
            if isAudioMode {
                Button(action: { isAudioMode = false; isPlaying = false; store.stopPlayback() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(textColor.opacity(0.7))
                }
            } else {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(textColor.opacity(0.7))
                }
            }
            Text(displayedChapterTitle)
                .font(.headline).lineLimit(1)
                .foregroundColor(textColor)
                .padding(.leading, 8)
            Spacer()
            if isAudioMode {
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
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(bgColor.opacity(0.9))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Character Panel

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

    // MARK: - Automation Toolbar

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

    // MARK: - Audio Control Bar

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
                .disabled(currentChapterIndex >= chaptersList.count - 1)
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

    // MARK: - Status Bar

    private var readerStatusBar: some View {
        HStack(spacing: 8) {
            if store.showProgressBar {
                Text(progressText)
                    .font(.caption2).foregroundColor(textColor.opacity(0.6)).monospacedDigit()
            }
            if store.showPageNumber {
                let pct = chaptersList.isEmpty ? 0
                    : min(Double(currentChapterIndex + 1) / Double(max(chaptersList.count, 1)), 1)
                Text("\(Int(pct * 100))%")
                    .font(.caption2).foregroundColor(textColor.opacity(0.5))
            }
            Spacer()
            if store.showTime {
                Text(currentTime, style: .time)
                    .font(.caption2).foregroundColor(textColor.opacity(0.5))
            }
            if store.showBattery, batteryLevel >= 0 {
                HStack(spacing: 2) {
                    Image(systemName: batteryIcon)
                        .font(.caption2).foregroundColor(textColor.opacity(0.5))
                    Text("\(batteryLevel)%")
                        .font(.caption2).foregroundColor(textColor.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(bgColor.opacity(0.9))
    }

    private var batteryIcon: String {
        batteryLevel > 90 ? "battery.100" :
        batteryLevel > 60 ? "battery.75" :
        batteryLevel > 30 ? "battery.50" :
        "battery.0"
    }

    private var progressText: String {
        guard !chaptersList.isEmpty else { return "—" }
        return "\(currentChapterIndex + 1)/\(chaptersList.count)"
    }

    // MARK: - Control Bar (silent reading)

    private var controlBar: some View {
        VStack(spacing: 0) {
            if showBookmarks { bookmarkPanel }
            HStack(spacing: 12) {
                controlButton(systemName: "chevron.left", disabled: currentChapterIndex <= 0, action: previousChapter)
                controlButton(systemName: "list.bullet", action: { showTOC = true })
                controlButton(
                    systemName: chapterBookmarks.isEmpty ? "bookmark" : "bookmark.fill",
                    action: { showBookmarks.toggle() }
                )
                controlButton(systemName: themeIcon(store.readerTheme), action: {
                    store.readerTheme = nextTheme(store.readerTheme)
                })
                controlButton(systemName: "textformat.alt", action: { showFontPicker = true })
                controlButton(systemName: "gearshape.fill", action: { showSettings = true })
                controlButton(
                    systemName: "play.circle.fill",
                    action: {
                        isAudioMode = true
                        isPlaying = true
                        Task { await startPlayback() }
                    }
                )
                controlButton(
                    systemName: "chevron.right",
                    disabled: currentChapterIndex >= chaptersList.count - 1,
                    action: nextChapter
                )
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .foregroundColor(textColor)
            .background(.ultraThinMaterial)
        }
        .animation(.easeInOut(duration: 0.2), value: showBookmarks)
    }

    private func controlButton(systemName: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.title2)
        }
        .disabled(disabled)
    }

    private var bookmarkPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("书签 (\(chapterBookmarks.count))").font(.headline).foregroundColor(textColor)
                Spacer()
                Button("关闭") { showBookmarks = false }.font(.caption)
            }
            .padding(.horizontal).padding(.top, 8)
            if chapterBookmarks.isEmpty {
                Text("暂无书签").foregroundColor(textColor.opacity(0.5)).padding()
            } else {
                List {
                    ForEach(chapterBookmarks) { bm in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bm.note.isEmpty ? "\(Int(bm.percent * 100))%" : bm.note)
                                    .font(.caption).foregroundColor(textColor)
                                Text(bm.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundColor(textColor.opacity(0.6))
                            }
                            Spacer()
                            Button(action: { store.removeBookmark(bm.id) }) {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .listRowBackground(bgColor)
                    }
                }
                .listStyle(.plain).frame(maxHeight: 180)
            }
        }
        .background(bgColor)
    }

    // MARK: - Helpers

    private func nextTheme(_ t: ReaderTheme) -> ReaderTheme {
        switch t {
        case .light: return .sepia
        case .sepia: return .dark
        case .dark: return .light
        }
    }

    private func themeIcon(_ t: ReaderTheme) -> String {
        switch t {
        case .light: return "sun.max"
        case .sepia: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        }
    }

    private func updateBatteryLevel() {
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
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
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        updateTextView(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        updateTextView(tv)
        DispatchQueue.main.async {
            tv.invalidateIntrinsicContentSize()
        }
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

// MARK: - PageMode

enum PageMode: String, CaseIterable, Identifiable {
    case scroll = "scroll"
    case horizontal = "horizontal"
    case vertical = "vertical"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .scroll: return "滚动"
        case .horizontal: return "左右翻页"
        case .vertical: return "上下翻页"
        }
    }
    var icon: String {
        switch self {
        case .scroll: return "scroll"
        case .horizontal: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        }
    }
}

// MARK: - ReaderSettingsView

struct ReaderSettingsView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var useSystemBrightness: Bool = true
    @State private var customBrightness: Double = 0.5
    @State private var keepScreenOn: Bool = false
    @State private var pageMode: PageMode = .scroll
    @State private var showFontPicker: Bool = false
    @State private var showBackgroundPicker: Bool = false
    @State private var enableHyphenation: Bool = false
    @State private var enableKerning: Bool = true
    @State private var firstLineIndent: Double = 0
    @State private var textAlignment: TextAlign = .leading

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("翻页模式")) {
                    Picker("翻页模式", selection: $pageMode) {
                        ForEach(PageMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("排版设置")) {
                    HStack {
                        Text("字号")
                        Slider(value: Binding(get: { store.readerFontSize }, set: { store.readerFontSize = $0 }), in: 14...32, step: 1)
                        Text("\(Int(store.readerFontSize))")
                    }
                    HStack {
                        Text("行距")
                        Slider(value: Binding(get: { store.readerLineSpacing }, set: { store.readerLineSpacing = $0 }), in: 0...20, step: 1)
                        Text("\(Int(store.readerLineSpacing))")
                    }
                    HStack {
                        Text("段距")
                        Slider(value: Binding(get: { store.readerParagraphSpacing }, set: { store.readerParagraphSpacing = $0 }), in: 0...30, step: 1)
                        Text("\(Int(store.readerParagraphSpacing))")
                    }
                    HStack {
                        Text("首行缩进")
                        Slider(value: $firstLineIndent, in: 0...40, step: 2)
                        Text("\(Int(firstLineIndent))")
                    }
                    Picker("对齐方式", selection: $textAlignment) {
                        Text("左对齐").tag(TextAlign.leading)
                        Text("居中对齐").tag(TextAlign.center)
                        Text("右对齐").tag(TextAlign.trailing)
                        Text("两端对齐").tag(TextAlign.justified)
                    }
                    Toggle("字距调整", isOn: $enableKerning)
                    Toggle("自动断字", isOn: $enableHyphenation)
                }

                Section(header: Text("主题与背景")) {
                    Picker("主题", selection: Binding(get: { store.readerTheme }, set: { store.readerTheme = $0 })) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button(action: { showBackgroundPicker = true }) {
                        HStack {
                            Text("自定义背景图")
                            Spacer()
                            if store.customBackgroundImage != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            }
                        }
                    }
                    Button(action: { store.customBackgroundImage = nil }) {
                        Text("清除背景图").foregroundColor(.red)
                    }
                    .disabled(store.customBackgroundImage == nil)
                }

                Section(header: Text("字体")) {
                    Button(action: { showFontPicker = true }) {
                        HStack {
                            Text("当前字体")
                            Spacer()
                            Text(store.readerFontName).foregroundColor(.secondary)
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("屏幕与亮度")) {
                    Toggle("跟随系统亮度", isOn: $useSystemBrightness)
                        .onChange(of: useSystemBrightness) { newValue in
                            if newValue { UIScreen.main.brightness = UIScreen.main.brightness }
                        }
                    if !useSystemBrightness {
                        HStack {
                            Text("亮度")
                            Slider(value: $customBrightness, in: 0...1)
                                .onChange(of: customBrightness) { newValue in
                                    UIScreen.main.brightness = newValue
                                    UserDefaults.standard.set(newValue, forKey: "readerBrightness")
                                }
                            Text("\(Int(customBrightness * 100))%")
                        }
                    }
                    Toggle("屏幕常亮", isOn: $keepScreenOn)
                        .onChange(of: keepScreenOn) { newValue in
                            UIApplication.shared.isIdleTimerDisabled = newValue
                            store.keepScreenOn = newValue
                        }
                }

                Section(header: Text("阅读界面显示")) {
                    Toggle("显示章节标题", isOn: Binding(get: { store.showChapterTitle }, set: { store.showChapterTitle = $0 }))
                    Toggle("显示进度条", isOn: Binding(get: { store.showProgressBar }, set: { store.showProgressBar = $0 }))
                    Toggle("显示页码", isOn: Binding(get: { store.showPageNumber }, set: { store.showPageNumber = $0 }))
                    Toggle("显示时间", isOn: Binding(get: { store.showTime }, set: { store.showTime = $0 }))
                    Toggle("显示电池", isOn: Binding(get: { store.showBattery }, set: { store.showBattery = $0 }))
                }

                Section {
                    Button("保存并应用") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center).foregroundColor(.blue)
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showFontPicker) {
                FontPickerView().environmentObject(store).presentationDetents([.medium])
            }
            .sheet(isPresented: $showBackgroundPicker) {
                BackgroundPickerView().environmentObject(store).presentationDetents([.medium, .large])
            }
            .onAppear {
                useSystemBrightness = UserDefaults.standard.object(forKey: "useSystemBrightness") as? Bool ?? true
                customBrightness = UserDefaults.standard.object(forKey: "readerBrightness") as? Double ?? 0.5
                keepScreenOn = store.keepScreenOn
                pageMode = PageMode(rawValue: UserDefaults.standard.string(forKey: "pageMode") ?? "scroll") ?? .scroll
                firstLineIndent = UserDefaults.standard.object(forKey: "firstLineIndent") as? Double ?? 0
                textAlignment = TextAlign(rawValue: UserDefaults.standard.integer(forKey: "textAlignment")) ?? .leading
                enableKerning = UserDefaults.standard.object(forKey: "enableKerning") as? Bool ?? true
                enableHyphenation = UserDefaults.standard.object(forKey: "enableHyphenation") as? Bool ?? false
            }
            .onDisappear {
                UserDefaults.standard.set(useSystemBrightness, forKey: "useSystemBrightness")
                UserDefaults.standard.set(customBrightness, forKey: "readerBrightness")
                UserDefaults.standard.set(pageMode.rawValue, forKey: "pageMode")
                UserDefaults.standard.set(firstLineIndent, forKey: "firstLineIndent")
                UserDefaults.standard.set(textAlignment.rawValue, forKey: "textAlignment")
                UserDefaults.standard.set(enableKerning, forKey: "enableKerning")
                UserDefaults.standard.set(enableHyphenation, forKey: "enableHyphenation")
                store.keepScreenOn = keepScreenOn
            }
        }
    }
}

// MARK: - FontPickerView

struct FontPickerView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var customFonts: [_CustomFont] = []
    @State private var showingFontImporter = false

    private let systemFonts = [
        "PingFang SC", "Heiti SC", "STHeiti", "Hiragino Sans GB",
        "Arial", "Helvetica", "Georgia", "Times New Roman",
        "Menlo", "Courier New", "Marker Felt", "Noteworthy"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("系统字体")) {
                    ForEach(systemFonts, id: \.self) { font in
                        Button(action: { store.readerFontName = font; dismiss() }) {
                            HStack {
                                Text(font).font(.custom(font, size: 17))
                                Spacer()
                                if store.readerFontName == font { Image(systemName: "checkmark").foregroundColor(.blue) }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }

                Section(header: Text("自定义字体"), footer: Text("支持 TTF/OTF 格式")) {
                    if customFonts.isEmpty {
                        Text("暂无自定义字体").foregroundColor(.secondary)
                    } else {
                        ForEach(customFonts) { font in
                            Button(action: { store.readerFontName = font.name; dismiss() }) {
                                HStack {
                                    Text(font.name).font(.custom(font.name, size: 17))
                                    Spacer()
                                    if store.readerFontName == font.name { Image(systemName: "checkmark").foregroundColor(.blue) }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                        .onDelete(perform: removeCustomFonts)
                    }
                    Button(action: { showingFontImporter = true }) {
                        Label("导入字体", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("选择字体").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .fileImporter(isPresented: $showingFontImporter, allowedContentTypes: [.font], allowsMultipleSelection: true) { result in
                handleFontImport(result)
            }
            .onAppear { loadCustomFonts() }
        }
    }

    private func loadCustomFonts() {
        let docs = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let fontsDir = docs.appendingPathComponent("CustomFonts")
        if let files = try? FileManager.default.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil) {
            customFonts = files.compactMap { url in
                guard url.pathExtension.lowercased() == "ttf" || url.pathExtension.lowercased() == "otf" else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                return _CustomFont(name: name, url: url)
            }
        }
    }

    private func handleFontImport(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get() else { return }
        let docs = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let fontsDir = docs.appendingPathComponent("CustomFonts")
        try? FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        for url in urls {
            let dest = fontsDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                registerFont(at: dest)
            } catch { print("Font import error: \(error)") }
        }
        loadCustomFonts()
    }

    private func registerFont(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let font = CGFont(provider) else { return }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterGraphicsFont(font, &error)
    }

    private func removeCustomFonts(at offsets: IndexSet) {
        let docs = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let fontsDir = docs.appendingPathComponent("CustomFonts")
        for index in offsets {
            try? FileManager.default.removeItem(at: customFonts[index].url)
        }
        loadCustomFonts()
    }
}

struct _CustomFont: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

// MARK: - BackgroundPickerView

struct BackgroundPickerView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?

    private let presetBackgrounds = [
        ("无", nil as String?),
        ("淡雅纹理", "bg_texture_1"),
        ("复古纸张", "bg_texture_2"),
        ("深色纹理", "bg_texture_3")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("预设背景")) {
                    ForEach(presetBackgrounds, id: \.0) { name, assetName in
                        Button(action: {
                            store.customBackgroundImage = assetName.flatMap { UIImage(named: $0)?.pngData() }
                            dismiss()
                        }) {
                            HStack {
                                if let assetName = assetName, let img = UIImage(named: assetName) {
                                    Image(uiImage: img).resizable().frame(width: 40, height: 40).cornerRadius(8)
                                } else {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(width: 40, height: 40)
                                }
                                Text(name)
                                Spacer()
                                if store.customBackgroundImage == (assetName.flatMap { UIImage(named: $0)?.pngData() }) {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }

                Section(header: Text("自定义背景")) {
                    Button(action: { showingImagePicker = true }) {
                        HStack {
                            if let data = store.customBackgroundImage, let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().frame(width: 40, height: 40).cornerRadius(8)
                                Text("当前自定义背景")
                            } else {
                                Label("从相册选择", systemImage: "photo")
                            }
                            Spacer()
                        }
                    }
                    .foregroundColor(.primary)

                    if store.customBackgroundImage != nil {
                        Button("清除自定义背景", role: .destructive) {
                            store.customBackgroundImage = nil
                        }
                    }
                }
            }
            .navigationTitle("阅读背景").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .sheet(isPresented: $showingImagePicker) { ImagePicker(image: $selectedImage) }
            .onChange(of: selectedImage) { newImage in
                if let img = newImage, let data = img.pngData() {
                    store.customBackgroundImage = data
                    dismiss()
                }
            }
        }
    }
}

// MARK: - ImagePicker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.image = img }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - VisualEffectView

struct VisualEffectView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
