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

// MARK: - ReaderView

struct ReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let bookID: UUID

    @State private var currentChapter: BookChapter
    @State private var currentChapterIndex: Int
    @State private var chaptersList: [BookChapter] = []

    @State private var showBookmarks = false
    @State private var showSettings = false
    @State private var showFontPicker = false
    @State private var showTOC = false
    @State private var isImmersive = false

    @State private var isAudioMode = false
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 1.0
    @State private var playbackProgress: Double = 0

    @State private var showCharacterPanel = false
    @State private var editingCharacter: CharacterProfile?
    @State private var showAddCharacter = false
    @State private var showAllRecommendations = false
    @State private var selectedTextForCharacter = ""
    @State private var showCharacterFromText = false

    @State private var currentTime = Date()
    @State private var batteryLevel: Int = 100
    @State private var screenBrightness: CGFloat = UIScreen.main.brightness
    @State private var useSystemBrightness = true

    @State private var chapterProgress: Double = 0
    @State private var scrollPositionID: String?
    @State private var navigationTarget: Int?
    @State private var immersiveBeforeAudioMode = false
    @State private var autoScrollWorkItem: DispatchWorkItem?
    @State private var scrolledAway = false
    @State private var lastAutoScrollTime: Date = .distantPast
    @State private var startPlaybackID: String?
    @State private var cachedParagraphs: [UUID: [String]] = [:]
    @StateObject private var scrollCoordinator = ScrollCoordinator()

    private func navigateToChapter(_ target: Int) {
        let safeTarget = min(max(0, target), chaptersList.count - 1)
        guard safeTarget >= 0, safeTarget < chaptersList.count else { return }
        if isPlaying { store.stopPlayback(); isPlaying = false }
        ReaderStore.saveLastChapterIndex(safeTarget, for: bookID)
        ReaderStore.debugLog("[NAV] idx=\(safeTarget)")
        navigationTarget = safeTarget
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { scrollPositionID = "ch_\(safeTarget)" }
        // LazyVStack lands one screen short; nudge one more viewport after layout
        DispatchQueue.main.async { [scrollCoordinator] in
            guard let sv = scrollCoordinator.scrollView else { return }
            sv.setContentOffset(CGPoint(x: 0, y: sv.contentOffset.y + UIScreen.main.bounds.height), animated: false)
        }
        // Timeout: if scroll never reaches target, force update after 2s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.navigationTarget == safeTarget {
                self.navigationTarget = nil
                self.currentChapterIndex = safeTarget
                if safeTarget < self.chaptersList.count {
                    self.currentChapter = self.chaptersList[safeTarget]
                    self.store.selectedChapterID = self.chaptersList[safeTarget].id
                }
            }
        }
    }

    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init(book: Book, chapter: BookChapter, bookID: UUID, chapterIndex: Int) {
        self.book = book
        self.bookID = bookID
        ReaderStore.debugLog("[RVIEW-INIT] bookID=\(bookID.uuidString) chapterIndex=\(chapterIndex)")
        _currentChapter = State(initialValue: chapter)
        _currentChapterIndex = State(initialValue: chapterIndex)
    }

    // MARK: - Computed Properties

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


    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundContent.ignoresSafeArea()

            ScrollView {
                ScrollViewAccessor(coordinator: scrollCoordinator)
                    .frame(height: 0)
                LazyVStack(spacing: 0) {
                    ForEach(chaptersList.indices, id: \.self) { i in
                        chapterContent(index: i)
                            .id("ch_\(i)")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPositionID, anchor: .top)
            .onChange(of: scrollPositionID) { _, newID in
                let isRecentAutoScroll = Date().timeIntervalSince(lastAutoScrollTime) < 0.4
                guard !isRecentAutoScroll else { return }
                guard let idStr = newID else { return }
                // If TTS is playing and user manually scrolled (not auto-scroll), mark scrolledAway
                if isPlaying, isAudioMode, isImmersive {
                    scrolledAway = true
                }
                // Parse "ch_N" or "ch_N_p_M"
                let parts = idStr.split(separator: "_", maxSplits: 3)
                guard parts.count >= 2, parts[0] == "ch", let chIdx = Int(parts[1]) else { return }
                let isAnchor = parts.count == 3 && parts[2] == "anchor"
                if let target = navigationTarget {
                    if isAnchor || chIdx == target {
                        navigationTarget = nil
                        currentChapterIndex = chIdx
                        chapterProgress = chaptersList.isEmpty ? 0 : Double(chIdx) / Double(chaptersList.count)
                        if chIdx < chaptersList.count {
                            currentChapter = chaptersList[chIdx]
                            store.selectedChapterID = chaptersList[chIdx].id
                        }
                    }
                    return
                }
                if currentChapterIndex != chIdx {
                    currentChapterIndex = chIdx
                    chapterProgress = chaptersList.isEmpty ? 0 : Double(chIdx) / Double(chaptersList.count)
                    if chIdx < chaptersList.count {
                        currentChapter = chaptersList[chIdx]
                        store.selectedChapterID = chaptersList[chIdx].id
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    if currentChapterIndex > 0 {
                        scrollPositionID = "ch_\(currentChapterIndex)"
                    }
                }
            }
            .onChange(of: chaptersList.count) { _, _ in
                // chapter list changed
            }
            .onChange(of: store.currentParagraphIndex) { _, _ in
                scheduleAutoScrollUpdate()
            }
            .onChange(of: store.currentSentenceIndex) { _, _ in
                scheduleAutoScrollUpdate()
            }
            .onChange(of: store.ttsIsPlaying) { _, newValue in
                isPlaying = newValue
                scheduleAutoScrollUpdate()
            }
            .onChange(of: store.selectedChapterID) { _, newID in
                guard let idx = chaptersList.firstIndex(where: { $0.id == newID }),
                      idx != currentChapterIndex else { return }
                currentChapterIndex = idx
                currentChapter = chaptersList[idx]
            }

            ReaderOverlayView(
                isImmersive: $isImmersive,
                isAudioMode: $isAudioMode,
                isPlaying: $isPlaying,
                showBookmarks: $showBookmarks,
                showCharacterPanel: $showCharacterPanel,
                showTOC: $showTOC,
                showSettings: $showSettings,
                showFontPicker: $showFontPicker,
                scrolledAway: $scrolledAway,
                immersiveBeforeAudioMode: $immersiveBeforeAudioMode,
                currentScrollID: scrollPositionID,
                startPlaybackID: startPlaybackID,
                chaptersList: chaptersList,
                currentChapterIndex: currentChapterIndex,
                currentTime: currentTime,
                batteryLevel: batteryLevel,
                textColor: textColor,
                bgColor: bgColor,
                bookID: bookID,
                navigateToChapter: navigateToChapter,
                startPlayback: { paraIndex in
                    startPlaybackID = scrollPositionID
                    await startPlayback(fromParagraphIndex: paraIndex)
                },
                onScrollToID: { newID in
                    scrollPositionID = newID
                }
            )
        }
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    handleZoneTap(at: value.location)
                }
        )
        .sheet(isPresented: $showCharacterPanel) {
            characterPanelSheet
                .presentationDetents([.medium, .large])
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .statusBarHidden(isImmersive || (isAudioMode && store.ttsIsPlaying))
        .onReceive(timer) { _ in
            currentTime = Date()
            if UIDevice.current.isBatteryMonitoringEnabled {
                batteryLevel = UIDevice.current.batteryLevel >= 0
                    ? Int(UIDevice.current.batteryLevel * 100) : -1
            } else {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
        }
        .onAppear(perform: onAppearSetup)
        .onDisappear(perform: onDisappearCleanup)
        .onChange(of: store.externalChapterNavigate) { _, newValue in
            handleExternalNavigate(nav: newValue)
        }
        .modifier(ReaderSheets(
            showSettings: $showSettings,
            showFontPicker: $showFontPicker,
            showTOC: $showTOC,
            editingCharacter: $editingCharacter,
            showAddCharacter: $showAddCharacter,
            showAllRecommendations: $showAllRecommendations,
            showCharacterFromText: $showCharacterFromText,
            selectedTextForCharacter: selectedTextForCharacter,
            bookID: book.id,
            currentChapterID: currentChapter.id,
            currentChapterIndex: currentChapterIndex,
            chaptersList: chaptersList,
            onTOCSelect: { index in
                if !chaptersList.isEmpty {
                    store.setChapterProgress(chaptersList[min(currentChapterIndex, chaptersList.count - 1)].id, percent: 1.0)
                }
                navigateToChapter(index)
            },
            onCharacterEdit: { updated in
                if let idx = store.characters.firstIndex(where: { $0.id == updated.id }) {
                    store.characters[idx] = updated
                    store.updateRecommendations()
                    store.saveState()
                }
            },
            store: store
        ))
    }


    @ViewBuilder private var backgroundContent: some View {
        if let data = store.customBackgroundImage, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable().scaledToFill()
        } else {
            bgColor
        }
    }

    // MARK: - Chapter Content

    @ViewBuilder
    private func chapterContent(index: Int) -> some View {
        let ch = chaptersList[index]
        let isCurrentChapter = index == currentChapterIndex && (store.ttsIsPlaying || store.currentSentenceText != nil)
        ChapterContentView(
            index: index,
            chapter: ch,
            isCurrentChapter: isCurrentChapter,
            playbackParagraphIndex: isCurrentChapter ? store.currentParagraphIndex : nil,
            playbackSentenceIndex: isCurrentChapter ? store.currentSentenceIndex : nil,
            isPlaybackActive: store.ttsIsPlaying || store.currentSentenceText != nil,
            readerFontName: store.readerFontName,
            readerFontSize: store.readerFontSize,
            readerLineSpacing: store.readerLineSpacing,
            readerFirstLineIndent: store.readerFirstLineIndent,
            textColor: textColor,
            onSentenceTap: { pi, si, sentenceText in
                selectSentence(paragraphIndex: pi, sentenceIndex: si, sentenceText: sentenceText)
                if !store.ttsIsPlaying {
                    Task {
                        let chapter = chaptersList[currentChapterIndex]
                        await store.immediateInterruptAndSeek(chapter: chapter, fromParagraphIndex: pi, sentenceIndex: si)
                    }
                }
            },
            onAddCharacter: { name in
                selectedTextForCharacter = name
                showCharacterFromText = true
            }
        )
        .equatable()
    }



    // MARK: - Character Panel

    private var characterPanelContent: some View {
        ScrollView {
            VStack(spacing: 10) {
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
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var characterPanelSheet: some View {
        NavigationStack {
            List {
                ForEach(store.characters) { character in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(character.name).font(.subheadline)
                                if let rec = store.recommendations.first(where: { $0.profile.id == character.id }) {
                                    Text("x\(rec.count)").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Text(character.voice).font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("试听") { Task { await store.previewVoice(for: character) } }
                            .font(.caption).buttonStyle(.borderless)
                        Button("编辑") { editingCharacter = character }
                            .font(.caption).buttonStyle(.borderless)
                    }
                }
                .onDelete { offsets in
                    for i in offsets where i < store.characters.count {
                        store.deleteCharacter(at: store.characters[i].id)
                    }
                }
            }
            .navigationTitle("角色音色 (\(store.characters.count))")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showCharacterPanel = false }
                }
            }
        }
    }

    // MARK: - Character Panel Components

    private var voiceCatalogRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle")
                .foregroundColor(.accentColor)
            Text("音色配置")
                .font(.subheadline)
                .foregroundColor(textColor)
            Spacer()
            Text("\(store.characters.count) 个角色")
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
                                Text(voice.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                                    .foregroundColor(.blue)
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
                        Text(character.voice)
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

    // MARK: - Lifecycle

    private func onAppearSetup() {
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        batteryLevel = UIDevice.current.batteryLevel >= 0
            ? Int(UIDevice.current.batteryLevel * 100) : -1
        store.selectedChapterID = currentChapter.id
        UIApplication.shared.isIdleTimerDisabled = store.keepScreenOn
        ensureChaptersLoaded()
        if let brightness = UserDefaults.standard.object(forKey: "readerBrightness") as? CGFloat {
            screenBrightness = brightness
            useSystemBrightness = false
            UIScreen.main.brightness = brightness
        }
        ReaderStore.debugLog("[RVIEW-APPEAR] idx=\(currentChapterIndex) chaptersList.count=\(chaptersList.count)")
    }

    private func onDisappearCleanup() {
        UIApplication.shared.isIdleTimerDisabled = false
        ReaderStore.saveLastChapterIndex(currentChapterIndex, for: bookID)
        ReaderStore.debugLog("[POS-SAVE] onDisappear idx=\(currentChapterIndex) bookID=\(bookID.uuidString)")
        if currentChapterIndex < chaptersList.count {
            let total = paragraphCache(for: chaptersList[currentChapterIndex]).count
            let cur = currentParaIndexFromID
            let progress = total > 0 ? Double(min(cur, total)) / Double(total) : 0
            store.setChapterProgress(chaptersList[currentChapterIndex].id, percent: max(0.0, min(1.0, progress)))
        }
        store.saveState()
        if !useSystemBrightness {
            UIScreen.main.brightness = UserDefaults.standard.object(forKey: "readerBrightness") as? CGFloat ?? 0.5
        }
    }

    private func ensureChaptersLoaded() {
        guard chaptersList.isEmpty else { return }
        if let cached = store.chaptersForBookCached(bookID) {
            chaptersList = cached
            return
        }
        Task {
            let text: String
            if store.bookText.isEmpty || store.currentBookID != bookID.uuidString {
                if !book.text.isEmpty {
                    text = book.text
                } else {
                    let bookID = bookID
                    text = await Task.detached(priority: .userInitiated) {
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
                        let url = docs.appendingPathComponent("book_texts/\(bookID.uuidString).txt")
                        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    }.value
                }
                store.bookText = text
                store.currentBookID = bookID.uuidString
            } else {
                text = store.bookText
            }
            guard !text.isEmpty else {
                chaptersList = [currentChapter]
                DispatchQueue.main.async { scrollPositionID = "ch_\(currentChapterIndex)" }
                return
            }
            let parsed = await Task.detached(priority: .userInitiated) {
                parseChapters(text: text)
            }.value
            if !parsed.isEmpty {
                store.bookChaptersCache[bookID] = parsed
                chaptersList = parsed
            } else {
                chaptersList = store.chaptersForBook(bookID, text: text)
            }
            if chaptersList.isEmpty { chaptersList = [currentChapter] }
            DispatchQueue.main.async { scrollPositionID = "ch_\(currentChapterIndex)" }
        }
    }

    private func handleExternalNavigate(nav: ChapterNavigate?) {
        guard let nav, nav.bookID == bookID, nav.chapterIndex < chaptersList.count else { return }
        store.externalChapterNavigate = nil
        navigateToChapter(nav.chapterIndex)
    }

    // MARK: - Navigation


    private func scrollToSentenceCenter(paragraphIndex: Int, sentenceIndex: Int?) {
        scrollPositionID = "ch_\(currentChapterIndex)_p_\(paragraphIndex)"
        lastAutoScrollTime = Date()
        scrolledAway = false
    }

    private func selectSentence(paragraphIndex: Int, sentenceIndex: Int, sentenceText: String) {
        store.currentParagraphIndex = paragraphIndex
        store.currentSentenceIndex = sentenceIndex
        store.currentSentenceText = sentenceText
        if store.ttsIsPlaying {
            store.audioController.skipToSegment(at: paragraphIndex)
        }
        scrollToSentenceCenter(paragraphIndex: paragraphIndex, sentenceIndex: sentenceIndex)
    }

    private func handleZoneTap(at location: CGPoint) {
        let screenH = UIScreen.main.bounds.height
        let yRatio = location.y / screenH
        if yRatio < 0.25 {
            scrollPageUp()
        } else if yRatio > 0.75 {
            scrollPageDown()
        } else {
            toggleImmersiveMode()
        }
    }

    private func scrollPageDown() {
        let screenH = UIScreen.main.bounds.height
        let currentOffset = scrollCoordinator.scrollView?.contentOffset.y ?? 0
        let maxOffset = max(0, (scrollCoordinator.scrollView?.contentSize.height ?? 0) - screenH)
        let target = min(currentOffset + screenH * 5 / 6, maxOffset)
        scrollCoordinator.scrollTo(offset: target, animated: true)
    }

    private func scrollPageUp() {
        let screenH = UIScreen.main.bounds.height
        let currentOffset = scrollCoordinator.scrollView?.contentOffset.y ?? 0
        let target = max(0, currentOffset - screenH * 5 / 6)
        scrollCoordinator.scrollTo(offset: target, animated: true)
    }

    private func toggleImmersiveMode() {
        withAnimation(.easeInOut(duration: 0.08)) {
            isImmersive.toggle()
        }
    }

    private func scheduleAutoScrollUpdate() {
        autoScrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            updateAutoScrollForCurrentPlayback()
        }
        autoScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func updateAutoScrollForCurrentPlayback() {
        guard store.ttsIsPlaying || store.currentParagraphIndex != nil else { return }
        if !scrolledAway, let paragraphIndex = store.currentParagraphIndex {
            scrollPositionID = "ch_\(currentChapterIndex)_p_\(paragraphIndex)"
            lastAutoScrollTime = Date()
            scrolledAway = false
        }
        withAnimation { isPlaying = store.ttsIsPlaying }
    }

    private func startPlayback(fromParagraphIndex: Int? = nil) async {
        guard currentChapterIndex < chaptersList.count else { return }
        guard !store.bookText.isEmpty else {
            await MainActor.run { store.statusMessage = "文本尚未加载，请稍后再试。" }
            isPlaying = false
            return
        }
        let chapter = chaptersList[currentChapterIndex]
        store.audioController.playbackRate = Float(playbackSpeed)
        if store.characters.isEmpty {
            await MainActor.run { store.statusMessage = "未检测到角色，正在自动扫描..." }
            await store.scanCharacters()
        }
        if store.scriptSegments.isEmpty || store.lastScannedBookText != store.bookText {
            await store.buildScript(for: false)
        }
        await store.startPlaybackTask(chapter: chapter, fromParagraphIndex: fromParagraphIndex)
    }

    private var currentParaIndexFromID: Int {
        guard let id = scrollPositionID else { return 0 }
        let parts = id.split(separator: "_")
        if parts.count == 4, parts[0] == "ch", parts[2] == "p", let pi = Int(parts[3]) {
            return pi
        }
        return 0
    }

    private func paragraphCache(for chapter: BookChapter) -> [String] {
        if let cached = cachedParagraphs[chapter.id] { return cached }
        let result = chapter.text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace).isEmpty }
        cachedParagraphs[chapter.id] = result
        return result
    }
}

// MARK: - ChapterContentView (Equatable, isolated re-render)

@MainActor struct ChapterContentView: View, Equatable {
    let index: Int
    let chapter: BookChapter
    let isCurrentChapter: Bool
    let playbackParagraphIndex: Int?
    let playbackSentenceIndex: Int?
    let isPlaybackActive: Bool
    let readerFontName: String
    let readerFontSize: Double
    let readerLineSpacing: Double
    let readerFirstLineIndent: Double
    let textColor: Color
    let onSentenceTap: (Int, Int, String) -> Void
    let onAddCharacter: (String) -> Void

    @State private var paragraphs: [String] = []


    nonisolated static func == (lhs: ChapterContentView, rhs: ChapterContentView) -> Bool {
        lhs.index == rhs.index &&
        lhs.isCurrentChapter == rhs.isCurrentChapter &&
        lhs.playbackParagraphIndex == rhs.playbackParagraphIndex &&
        lhs.playbackSentenceIndex == rhs.playbackSentenceIndex &&
        lhs.isPlaybackActive == rhs.isPlaybackActive &&
        lhs.readerFontSize == rhs.readerFontSize &&
        lhs.readerLineSpacing == rhs.readerLineSpacing &&
        lhs.readerFirstLineIndent == rhs.readerFirstLineIndent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(chapter.title)
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(textColor)
            }
            .padding(.top, 24)
            .padding(.bottom, 12)

            ForEach(paragraphs.indices, id: \.self) { pi in
                paragraphRow(pi: pi)
                    .id("ch_\(index)_p_\(pi)")
            }

            Divider()
                .foregroundColor(textColor.opacity(0.2))
                .padding(.vertical, 16)
        }
        .padding(.horizontal, 8)
        .onAppear {
            if paragraphs.isEmpty {
                paragraphs = chapter.text
                    .components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace).isEmpty }
            }
        }
    }

    @ViewBuilder
    private func paragraphRow(pi: Int) -> some View {
        let paraText = paragraphs[pi]
        let isActiveParagraph = isCurrentChapter && isPlaybackActive && playbackParagraphIndex == pi
        VStack(alignment: .leading, spacing: 0) {
            if isActiveParagraph {
                HStack(spacing: 6) {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    Text("当前段落")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                .padding(.bottom, 4)
            }
            paragraphView(pi: pi, paraText: paraText)
        }
    }

    @ViewBuilder
    private func paragraphView(pi: Int, paraText: String) -> some View {
        let isReading = isCurrentChapter && isPlaybackActive &&
            playbackParagraphIndex == pi
        let indentStr = readerFirstLineIndent > 0 && !paraText.isEmpty
            ? String(repeating: "\u{3000}", count: Int(readerFirstLineIndent))
            : ""
        Text(indentStr + paraText)
            .font(Font.custom(readerFontName, size: readerFontSize))
            .foregroundColor(textColor)
            .lineSpacing(readerLineSpacing + 2)
            .textSelection(.enabled)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(isReading ? Color.accentColor.opacity(0.18) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                ContextMenuContent(paraText: paraText, onAddCharacter: onAddCharacter)
            }
    }
}

// MARK: - ContextMenuContent (lazy candidate extraction)

private struct ContextMenuContent: View {
    let paraText: String
    let onAddCharacter: (String) -> Void
    @State private var names: [String] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                ProgressView().onAppear {
                    Task.detached(priority: .userInitiated) {
                        let result = Self.extractCandidateNamesStatic(from: paraText)
                        await MainActor.run { names = result; loaded = true }
                    }
                }
            } else {
                if !names.isEmpty {
                    Text("添加为角色").font(.caption).foregroundColor(.secondary)
                    ForEach(names, id: \.self) { name in
                        Button(name) { onAddCharacter(name) }
                    }
                }
                Button("复制段落") {
                    UIPasteboard.general.string = paraText
                }
            }
        }
    }

    nonisolated private static func extractCandidateNamesStatic(from text: String) -> [String] {
        var nameCounts: [String: Int] = [:]
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let runPattern = try? NSRegularExpression(pattern: "[\\p{Han}]+")
        runPattern?.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let m = match, let r = Range(m.range, in: text) else { return }
            let run = text[r]
            let chars = Array(run)
            for start in 0..<chars.count {
                for length in [2, 3, 4] where start + length <= chars.count {
                    let candidate = String(chars[start..<start+length])
                    if CharacterAnalyzer.isStopWord(candidate) { continue }
                    if candidate.count == 2 && !CharacterAnalyzer.looksLikeRealName(candidate) { continue }
                    nameCounts[candidate, default: 0] += 1
                }
            }
        }
        return nameCounts.sorted { a, b in
            a.value > b.value || (a.value == b.value && a.key < b.key)
        }.prefix(15).map(\.key)
    }
}

// MARK: - ReaderOverlayView

private struct ReaderOverlayView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss

    @Binding var isImmersive: Bool
    @Binding var isAudioMode: Bool
    @Binding var isPlaying: Bool
    @Binding var showBookmarks: Bool
    @Binding var showCharacterPanel: Bool
    @Binding var showTOC: Bool
    @Binding var showSettings: Bool
    @Binding var showFontPicker: Bool
    @Binding var scrolledAway: Bool
    @Binding var immersiveBeforeAudioMode: Bool

    let currentScrollID: String?
    let startPlaybackID: String?
    let chaptersList: [BookChapter]
    let currentChapterIndex: Int
    let currentTime: Date
    let batteryLevel: Int
    let textColor: Color
    let bgColor: Color
    let bookID: UUID

    let navigateToChapter: (Int) -> Void
    let startPlayback: (Int?) async -> Void
    let onScrollToID: (String) -> Void

    var body: some View {
        ZStack {
            VStack {
                if !isImmersive { readerHeader }
                Spacer()
                if isAudioMode && isImmersive {
                    immersiveAudioBottomBar
                } else if isImmersive && (store.showProgressBar || store.showPageNumber || store.showTime || store.showBattery) {
                    readerStatusBar
                } else if !isImmersive {
                    if isAudioMode { audioBottomBar } else { silentBottomBar }
                }
            }

            if !chaptersList.isEmpty {
                if isAudioMode {
                    floatingAudioControls
                } else if !isImmersive {
                    floatingPlayButton
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var displayedChapterTitle: String {
        guard currentChapterIndex < chaptersList.count else { return chaptersList.first?.title ?? "" }
        return chaptersList[currentChapterIndex].title
    }

    private var currentPlaybackInfoText: String {
        if let sentence = store.currentSentenceText, !sentence.isEmpty {
            return sentence
        }
        if store.ttsIsPlaying {
            return store.ttsSegmentTitle.isEmpty ? "正在朗读..." : store.ttsSegmentTitle
        }
        return ""
    }

    private var chapterBookmarks: [BookBookmark] {
        guard currentChapterIndex >= 0, currentChapterIndex < chaptersList.count else { return [] }
        return store.bookmarks.filter { $0.chapterID == chaptersList[currentChapterIndex].id }
    }

    private var progressText: String {
        guard !chaptersList.isEmpty else { return "\u{2014}" }
        return "\(currentChapterIndex + 1)/\(chaptersList.count)"
    }

    private var batteryIcon: String {
        batteryLevel > 90 ? "battery.100" :
        batteryLevel > 60 ? "battery.75" :
        batteryLevel > 30 ? "battery.50" :
        "battery.0"
    }

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

    private var currentParaIndex: Int {
        guard let id = currentScrollID else { return 0 }
        let parts = id.split(separator: "_")
        if parts.count == 4, parts[0] == "ch", parts[2] == "p", let pi = Int(parts[3]) {
            return pi
        }
        return 0  // anchor → top of chapter
    }

    private var totalParasInCurrentChapter: Int {
        guard currentChapterIndex < chaptersList.count else { return 1 }
        let text = chaptersList[currentChapterIndex].text
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace).isEmpty }
            .count
    }

    private var sliderProgress: Double {
        let total = totalParasInCurrentChapter
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(currentParaIndex) / Double(total)))
    }

    // MARK: - Header

    private var readerHeader: some View {
        HStack {
            if isAudioMode {
                Button(action: {
                    isAudioMode = false
                    isPlaying = false
                    isImmersive = immersiveBeforeAudioMode
                    store.stopPlayback()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                        Text("退出朗读")
                            .font(.subheadline)
                    }
                    .foregroundColor(textColor.opacity(0.7))
                }
            } else {
                HStack(spacing: 8) {
                    Button(action: {
                        ReaderStore.saveLastChapterIndex(currentChapterIndex, for: bookID)
                        store.saveState()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(textColor.opacity(0.7))
                    }
                    Button(action: { isImmersive.toggle() }) {
                        Image(systemName: isImmersive ? "rectangle" : "rectangle.split.2x1")
                            .font(.title3)
                            .foregroundColor(textColor.opacity(0.7))
                    }
                }
            }

            Text(displayedChapterTitle)
                .font(.headline).lineLimit(1)
                .foregroundColor(textColor)
                .padding(.leading, 8)

            Spacer()

            if isAudioMode {
                Button(action: { showCharacterPanel.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showCharacterPanel ? "person.2.fill" : "person.2")
                            .font(.title3)
                        if !store.characters.isEmpty {
                            Text("\(store.characters.count)")
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(showCharacterPanel ? .blue : textColor.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(bgColor.opacity(0.9))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Playback Status Summary

    private var playbackStatusSummary: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.ttsIsPlaying ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.ttsIsPlaying ? "正在朗读" : "已暂停")
                    .font(.caption2).fontWeight(.semibold)
                Text(currentPlaybackInfoText.isEmpty ? "轻点任意句子，从这里开始朗读" : currentPlaybackInfoText)
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.75))
                    .lineLimit(2)
            }
            Spacer()
            if let paragraphIndex = store.currentParagraphIndex, let sentenceIndex = store.currentSentenceIndex {
                Text("第\(paragraphIndex + 1)段 · 第\(sentenceIndex + 1)句")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.65))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(textColor.opacity(0.06))
        .cornerRadius(10)
    }

    // MARK: - Silent Bottom Bar

    private var silentBottomBar: some View {
        VStack(spacing: 0) {
            if showBookmarks { bookmarkPanel }

            HStack(spacing: 8) {
                Button(action: {
                    guard currentChapterIndex > 0 else { return }
                    navigateToChapter(currentChapterIndex - 1)
                }) {
                    Text("上一章")
                        .font(.subheadline)
                        .frame(minWidth: 50, minHeight: 36)
                }
                .disabled(currentChapterIndex <= 0)

                Slider(value: Binding(
                    get: { sliderProgress },
                    set: { newValue in
                        let total = totalParasInCurrentChapter
                        let idx = min(max(0, Int(newValue * Double(total))), total - 1)
                        onScrollToID("ch_\(currentChapterIndex)_p_\(idx)")
                    }
                ))
                    .tint(.blue)
                    .highPriorityGesture(TapGesture().onEnded {})

                Button(action: {
                    guard currentChapterIndex < chaptersList.count - 1 else { return }
                    navigateToChapter(currentChapterIndex + 1)
                }) {
                    Text("下一章")
                        .font(.subheadline)
                        .frame(minWidth: 50, minHeight: 36)
                }
                .disabled(currentChapterIndex >= chaptersList.count - 1)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundColor(textColor)

            Divider()

            HStack(spacing: 0) {
                barButton("list.bullet", label: "目录", action: { showTOC = true })
                Divider().frame(height: 20)
                barButton(themeIcon(store.readerTheme), label: "主题", action: {
                    store.readerTheme = nextTheme(store.readerTheme)
                })
                Divider().frame(height: 20)
                barButton("gearshape.fill", label: "设置", action: { showSettings = true })
                Divider().frame(height: 20)
                barButton(chapterBookmarks.isEmpty ? "bookmark" : "bookmark.fill", label: "书签", action: { showBookmarks.toggle() })
                Divider().frame(height: 20)
                barButton("textformat.alt", label: "字体", action: { showFontPicker = true })
            }
            .padding(.vertical, 6)
            .foregroundColor(textColor)
        }
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: showBookmarks)
    }

    private func barButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemName)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 40)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Immersive Audio Bottom Bar

    private var immersiveAudioBottomBar: some View {
        VStack(spacing: 0) {
            if !currentPlaybackInfoText.isEmpty {
                Text(currentPlaybackInfoText)
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            Divider()
            if scrolledAway {
                HStack(spacing: 32) {
                    Button(action: {
                        if let id = startPlaybackID {
                            onScrollToID(id)
                        }
                        scrolledAway = false
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.backward.circle")
                                .font(.system(size: 16))
                            Text("原进度")
                                .font(.caption)
                        }
                    }
                    Button(action: {
                        scrolledAway = false
                        store.stopPlayback()
                        let paraIndex = currentParaIndex
                        Task { await startPlayback(paraIndex) }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "headphones.circle")
                                .font(.system(size: 16))
                            Text("从本页听")
                                .font(.caption)
                        }
                    }
                }
                .foregroundColor(textColor)
                .padding(.vertical, 4)
            } else {
                Button(action: {
                    if store.ttsIsPlaying {
                        store.audioController.pause()
                    } else {
                        store.audioController.resume()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: store.ttsIsPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 20))
                        Text(store.ttsIsPlaying ? "暂停播放" : "继续播放")
                            .font(.caption)
                    }
                    .foregroundColor(textColor)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderless)
            }
        }
        .background(bgColor.opacity(0.9))
    }

    // MARK: - Audio Bottom Bar

    private var audioBottomBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: {
                    guard currentChapterIndex > 0 else { return }
                    navigateToChapter(currentChapterIndex - 1)
                }) {
                    Text("上一章")
                        .font(.subheadline)
                        .frame(minWidth: 50, minHeight: 36)
                }
                .disabled(currentChapterIndex <= 0)

                Slider(value: Binding(
                    get: { sliderProgress },
                    set: { newValue in
                        let total = totalParasInCurrentChapter
                        let idx = min(max(0, Int(newValue * Double(total))), total - 1)
                        onScrollToID("ch_\(currentChapterIndex)_p_\(idx)")
                    }
                ))
                    .tint(.blue)
                    .highPriorityGesture(TapGesture().onEnded {})

                Button(action: {
                    guard currentChapterIndex < chaptersList.count - 1 else { return }
                    navigateToChapter(currentChapterIndex + 1)
                }) {
                    Text("下一章")
                        .font(.subheadline)
                        .frame(minWidth: 50, minHeight: 36)
                }
                .disabled(currentChapterIndex >= chaptersList.count - 1)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundColor(textColor)

            if !currentPlaybackInfoText.isEmpty {
                Text(currentPlaybackInfoText)
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            Divider()

            playbackStatusSummary
                .padding(.horizontal, 12)
                .padding(.top, 8)

            HStack(spacing: 8) {
                Button(action: { store.audioController.skipPreviousSentence() }) {
                    Label("上一句", systemImage: "backward")
                        .font(.caption2)
                        .frame(minWidth: 70, minHeight: 36)
                }
                .buttonStyle(.borderless)
                Button(action: { store.audioController.skipCurrentSentence() }) {
                    Label("下一句", systemImage: "forward")
                        .font(.caption2)
                        .frame(minWidth: 70, minHeight: 36)
                }
                .buttonStyle(.borderless)
                Button(action: {
                    if store.ttsIsPlaying {
                        store.audioController.pause()
                    } else {
                        store.audioController.resume()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: store.ttsIsPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 20))
                        Text(store.ttsIsPlaying ? "暂停" : "播放")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                }
                .buttonStyle(.borderless)
                Button(action: { store.audioController.skipPreviousParagraph() }) {
                    Label("上一段", systemImage: "backward.end")
                        .font(.caption2)
                        .frame(minWidth: 70, minHeight: 36)
                }
                .buttonStyle(.borderless)
                Button(action: { store.audioController.skipCurrentParagraph() }) {
                    Label("下一段", systemImage: "forward.end")
                        .font(.caption2)
                        .frame(minWidth: 70, minHeight: 36)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            HStack(spacing: 0) {
                barButton("list.bullet", label: "目录", action: { showTOC = true })
                Divider().frame(height: 20)
                barButton(themeIcon(store.readerTheme), label: "主题", action: {
                    store.readerTheme = nextTheme(store.readerTheme)
                })
                Divider().frame(height: 20)
                barButton("gearshape.fill", label: "设置", action: { showSettings = true })
                Divider().frame(height: 20)
                barButton("textformat.alt", label: "字体", action: { showFontPicker = true })
            }
            .padding(.vertical, 6)
            .foregroundColor(textColor)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Floating Audio Controls

    private var floatingAudioControls: some View {
        VStack(spacing: 12) {
            Spacer()
            Button(action: { store.audioController.skipCurrentParagraph() }) {
                Image(systemName: "forward.end")
                    .font(.system(size: 18))
                    .foregroundColor(textColor)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(bgColor.opacity(0.8)).shadow(radius: 2))
            }
            .buttonStyle(.borderless)
            Button(action: { store.audioController.skipCurrentSentence() }) {
                Image(systemName: "forward")
                    .font(.system(size: 18))
                    .foregroundColor(textColor)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(bgColor.opacity(0.8)).shadow(radius: 2))
            }
            .buttonStyle(.borderless)
            Button(action: {
                if store.ttsIsPlaying {
                    store.audioController.pause()
                } else {
                    store.audioController.resume()
                }
            }) {
                Image(systemName: store.ttsIsPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)
                    .background(Circle().fill(bgColor).shadow(radius: 4))
            }
            .buttonStyle(.borderless)
            Button(action: { store.audioController.playNext() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .foregroundColor(textColor)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(bgColor.opacity(0.8)).shadow(radius: 2))
            }
            .buttonStyle(.borderless)
            VStack(spacing: 2) {
                if !store.ttsProgressMessage.isEmpty {
                    Text(store.ttsProgressMessage)
                        .font(.system(size: 8))
                        .foregroundColor(textColor.opacity(0.6))
                        .lineLimit(2)
                        .frame(width: 60)
                        .multilineTextAlignment(.center)
                }
                if let paragraphIndex = store.currentParagraphIndex, let sentenceIndex = store.currentSentenceIndex {
                    Text("段\(paragraphIndex + 1)-句\(sentenceIndex + 1)")
                        .font(.system(size: 8))
                        .foregroundColor(textColor.opacity(0.6))
                        .lineLimit(2)
                        .frame(width: 60)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.trailing, 8)
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var floatingPlayButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    immersiveBeforeAudioMode = isImmersive
                    isAudioMode = true
                    isPlaying = true
                    Task { await startPlayback(nil) }
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                        .background(Circle().fill(bgColor).shadow(radius: 4))
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 20)
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Bookmark Panel

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

    // MARK: - Status Bar (immersive)

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
}


