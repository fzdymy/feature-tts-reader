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
    @State private var scrollOffset: CGFloat = 0
    @State private var segmentStartOffset: CGFloat = 0
    @State private var scrolledAway = false
    @State private var lastAutoScrollTime: Date = .distantPast
    @State private var chapterHeights: [CGFloat] = []  // cached heights
    @StateObject private var scrollCoordinator = ScrollCoordinator()

    private func navigateToChapter(_ target: Int) {
        guard target >= 0, target < chaptersList.count else { return }
        if isPlaying { store.stopPlayback(); isPlaying = false }
        currentChapterIndex = target
        currentChapter = chaptersList[target]
        store.selectedChapterID = chaptersList[target].id
        chapterProgress = chaptersList.isEmpty ? 0 : Double(target) / Double(chaptersList.count)
        ReaderStore.saveLastChapterIndex(target, for: bookID)
        ReaderStore.debugLog("[NAV] idx=\(target)")
        navigationTarget = target
        scrollPositionID = "ch_\(target)"
        // Use precise UIScrollView contentOffset for top-anchored scroll
        let chapterTop = chaptersList[0..<target].reduce(0) { $0 + estimatedChapterHeight($1) }
        scrollCoordinator.scrollTo(offset: chapterTop, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if self.navigationTarget == target { self.navigationTarget = nil }
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

    private func indentedText(_ text: String) -> String {
        "\u{3000}\u{3000}" + text.replacingOccurrences(of: "\n", with: "\n\u{3000}\u{3000}")
    }

    private var chapterProgressInChapter: Double {
        guard currentChapterIndex < chaptersList.count else { return 0 }
        let cached = chapterHeights
        guard currentChapterIndex < cached.count else { return 0 }
        let pastHeight = cached[0..<currentChapterIndex].reduce(0, +)
        let chHeight = cached[currentChapterIndex]
        guard chHeight > 0 else { return 0 }
        return min(1, max(0, Double(scrollOffset - pastHeight) / Double(chHeight)))
    }

    private var chapterBookmarks: [BookBookmark] {
        store.bookmarks.filter { $0.chapterID == currentChapter.id }
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

    private var displayedChapterTitle: String {
        guard currentChapterIndex < chaptersList.count else { return currentChapter.title }
        return chaptersList[currentChapterIndex].title
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundContent.ignoresSafeArea()

            ScrollView {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.frame(in: .scrollView).minY) { newY in
                            scrollOffset = -newY
                            if isAudioMode && isImmersive {
                                let screenH = UIScreen.main.bounds.height
                                // Don't mark scrolledAway during auto-scroll animation (within 0.4s)
                                if Date().timeIntervalSince(lastAutoScrollTime) > 0.4,
                                   abs(-newY - segmentStartOffset) > screenH * 0.5 {
                                    scrolledAway = true
                                }
                            }
                        }
                }
                .frame(height: 0)
                LazyVStack(spacing: 0) {
                    ForEach(chaptersList.indices, id: \.self) { i in
                        chapterContent(index: i)
                            .id("ch_\(i)")
                    }
                }
                .scrollTargetLayout()
                .simultaneousGesture(
                    TapGesture().onEnded { withAnimation(.easeInOut(duration: 0.25)) { isImmersive.toggle() } }
                )
            }
            .scrollPosition(id: $scrollPositionID)
            .background(ScrollViewAccessor(coordinator: scrollCoordinator))
            .onChange(of: scrollPositionID) { newID in
                guard let idStr = newID, idStr.hasPrefix("ch_"), let idx = Int(idStr.dropFirst(3)) else { return }
                // While navigating to a target, ignore intermediate chapters
                if let target = navigationTarget {
                    if idx == target { navigationTarget = nil }
                    return
                }
                if currentChapterIndex != idx {
                    currentChapterIndex = idx
                    chapterProgress = chaptersList.isEmpty ? 0 : Double(idx) / Double(chaptersList.count)
                    if idx < chaptersList.count {
                        currentChapter = chaptersList[idx]
                        store.selectedChapterID = chaptersList[idx].id
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    if currentChapterIndex > 0 {
                        scrollPositionID = "ch_\(currentChapterIndex)"
                    }
                    chapterHeights = chaptersList.map { estimatedChapterHeight($0) }
                }
            }
            .onChange(of: chaptersList.count) { _ in
                chapterHeights = chaptersList.map { estimatedChapterHeight($0) }
            }
            .onChange(of: store.ttsCurrentIndex) { _ in
                if !scrolledAway, let offset = autoScrollOffset(for: currentSegmentText) {
                    lastAutoScrollTime = Date()
                    scrollCoordinator.scrollTo(offset: offset, animated: true)
                    segmentStartOffset = offset
                } else {
                    segmentStartOffset = scrollOffset
                }
                scrolledAway = false
                withAnimation { isPlaying = store.ttsIsPlaying }
            }
            .onChange(of: store.ttsIsPlaying) { newValue in
                isPlaying = newValue
            }

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
                    // Right-side floating playback controls
                    VStack(spacing: 12) {
                        Spacer()
                        Button(action: {
                            store.audioController.playPrevious()
                        }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 20))
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
                        Button(action: {
                            store.audioController.playNext()
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 20))
                                .foregroundColor(textColor)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(bgColor.opacity(0.8)).shadow(radius: 2))
                        }
                        .buttonStyle(.borderless)
                        if !store.ttsProgressMessage.isEmpty {
                            Text(store.ttsProgressMessage)
                                .font(.system(size: 8))
                                .foregroundColor(textColor.opacity(0.6))
                                .lineLimit(2)
                                .frame(width: 60)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else if !isImmersive {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                isAudioMode = true
                                isPlaying = true
                                segmentStartOffset = scrollOffset
                                Task { await startPlayback() }
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
            }
        }
        .sheet(isPresented: $showCharacterPanel) {
            characterPanelSheet
                .presentationDetents([.medium, .large])
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .statusBarHidden(isImmersive || isAudioMode)
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
        .onChange(of: store.externalChapterNavigate, perform: handleExternalNavigate)
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

    // MARK: - Header

    private var readerHeader: some View {
        HStack {
            if isAudioMode {
                Button(action: {
                    isAudioMode = false
                    isPlaying = false
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
                Button(action: {
                    ReaderStore.saveLastChapterIndex(currentChapterIndex, for: bookID)
                    store.saveState()
                    dismiss()
                }) {
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

    // MARK: - Chapter Content

    private var currentSegmentText: String? {
        guard store.ttsCurrentIndex < store.ttsQueue.count else { return nil }
        return store.ttsQueue[store.ttsCurrentIndex].segment.text
    }

    @ViewBuilder
    private func chapterContent(index: Int) -> some View {
        let ch = chaptersList[index]
        let paragraphs = ch.text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let isCurrentChapter = index == currentChapterIndex && store.ttsIsPlaying
        VStack(alignment: .leading, spacing: 0) {
            Text(ch.title)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(textColor)
                .padding(.top, 24)
                .padding(.bottom, 12)

            ForEach(paragraphs.indices, id: \.self) { pi in
                let paraText = paragraphs[pi]
                let isReading = isCurrentChapter && (store.currentParagraphIndex.map { $0 == pi } ?? currentSegmentText.map { paraText.contains($0) || $0.contains(paraText) } ?? false)
                Text(indentedText(paraText))
                    .font(Font.custom(store.readerFontName, size: store.readerFontSize))
                    .foregroundColor(textColor)
                    .lineSpacing(store.readerLineSpacing + 2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, paraText == paragraphs.last ? 0 : 4)
                    .background(isReading ? Color.accentColor.opacity(0.3) : Color.clear)
                    .cornerRadius(4)
                    .contextMenu {
                        let names = extractCandidateNames(from: paraText)
                        if !names.isEmpty {
                            Text("添加为角色").font(.caption).foregroundColor(.secondary)
                            ForEach(names, id: \.self) { name in
                                Button(name) {
                                    selectedTextForCharacter = name
                                    showCharacterFromText = true
                                }
                            }
                        }
                        Button("复制段落") {
                            UIPasteboard.general.string = paraText
                        }
                    }
            }

            Divider()
                .foregroundColor(textColor.opacity(0.2))
                .padding(.vertical, 16)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: estimatedChapterHeight(ch))
    }

    private func extractCandidateNames(from text: String) -> [String] {
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
                    if CharacterAnalyzer().isStopWord(candidate) { continue }
                    if store.characters.contains(where: { $0.name == candidate || $0.aliases.contains(candidate) }) { continue }
                    // 2-char candidates: must pass name filter (too noisy otherwise)
                    if candidate.count == 2 && !CharacterAnalyzer.looksLikeRealName(candidate) { continue }
                    nameCounts[candidate, default: 0] += 1
                }
            }
        }
        // Sort by frequency descending, limit to top 15
        return nameCounts.sorted { a, b in
            a.value > b.value || (a.value == b.value && a.key < b.key)
        }.prefix(15).map(\.key)
    }

    private func estimatedChapterHeight(_ ch: BookChapter) -> CGFloat {
        let titleHeight: CGFloat = 58
        let bottomPad: CGFloat = 40
        let hPad: CGFloat = 40
        let containerWidth = UIScreen.main.bounds.width - hPad
        let fontSize = store.readerFontSize
        let font = UIFont(name: store.readerFontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let cjkCharWidth = fontSize
        let charsPerLine = max(1, Int(containerWidth / cjkCharWidth))
        let lineHeight = font.lineHeight + store.readerLineSpacing + 2
        let totalChars = ch.text.count
        let lineCount = max(1, (totalChars + charsPerLine - 1) / charsPerLine)
        return titleHeight + CGFloat(lineCount) * lineHeight + bottomPad
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
                    get: { chapterProgressInChapter },
                    set: { newValue in
                        guard currentChapterIndex < chaptersList.count else { return }
                        let pastHeight = chaptersList[0..<currentChapterIndex].reduce(0) { $0 + estimatedChapterHeight($1) }
                        let chHeight = estimatedChapterHeight(chaptersList[currentChapterIndex])
                        guard chHeight > 0 else { return }
                        let targetOffset = pastHeight + CGFloat(newValue) * chHeight
                        scrollCoordinator.scrollTo(offset: targetOffset, animated: false)
                    }
                ))
                    .tint(.blue)

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
            Divider()
            if scrolledAway {
                HStack(spacing: 32) {
                    Button(action: {
                        scrollCoordinator.scrollTo(offset: segmentStartOffset, animated: true)
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
                        let paraText = segmentTextForCurrentPosition()
                        segmentStartOffset = scrollOffset
                        Task { await startPlayback(fromParagraphText: paraText) }
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
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Audio Bottom Bar (matches silentBottomBar layout)

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
                    get: { chapterProgressInChapter },
                    set: { newValue in
                        guard currentChapterIndex < chaptersList.count else { return }
                        let pastHeight = chaptersList[0..<currentChapterIndex].reduce(0) { $0 + estimatedChapterHeight($1) }
                        let chHeight = estimatedChapterHeight(chaptersList[currentChapterIndex])
                        guard chHeight > 0 else { return }
                        let targetOffset = pastHeight + CGFloat(newValue) * chHeight
                        scrollCoordinator.scrollTo(offset: targetOffset, animated: false)
                    }
                ))
                    .tint(.blue)

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
                Divider().frame(height: 20)
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
                            if let rec = store.recommendations.first(where: { $0.profile.id == character.id }),
                               !rec.suggestedVoices.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(rec.suggestedVoices.prefix(4)) { voice in
                                            Button(voice.name) {
                                                store.applyVoice(voice.id, toCharacterID: rec.id)
                                            }
                                            .buttonStyle(.bordered).tint(.blue).font(.caption2).controlSize(.small)
                                        }
                                    }
                                }
                            }
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

    // MARK: - Character Panel Components

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
            store.setChapterProgress(chaptersList[currentChapterIndex].id, percent: 1.0)
        }
        store.saveState()
        if !useSystemBrightness {
            UIScreen.main.brightness = UserDefaults.standard.object(forKey: "systemBrightness") as? CGFloat ?? 0.5
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


    private func segmentTextForCurrentPosition() -> String? {
        guard currentChapterIndex < chaptersList.count else { return nil }
        let ch = chaptersList[currentChapterIndex]
        let paragraphs = ch.text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let cached = chapterHeights
        let pastHeight = currentChapterIndex < cached.count ? cached[0..<currentChapterIndex].reduce(0, +) : chaptersList[0..<currentChapterIndex].reduce(0) { $0 + estimatedChapterHeight($1) }
        let offsetInChapter = scrollOffset - pastHeight
        let titleHeight: CGFloat = 58
        let hPad: CGFloat = 40
        let containerWidth = UIScreen.main.bounds.width - hPad
        let fontSize = store.readerFontSize
        let font = UIFont(name: store.readerFontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let cjkCharWidth = fontSize
        let charsPerLine = max(1, Int(containerWidth / cjkCharWidth))
        let lineHeight = font.lineHeight + store.readerLineSpacing + 2
        var y: CGFloat = titleHeight
        for paraText in paragraphs {
            let trimmed = paraText.trimmingCharacters(in: .whitespacesAndNewlines)
            let paraLineCount = max(1, (trimmed.count + charsPerLine - 1) / charsPerLine)
            let paraHeight = CGFloat(paraLineCount) * lineHeight + 8
            if offsetInChapter >= y && offsetInChapter < y + paraHeight {
                return trimmed
            }
            y += paraHeight
        }
        return nil
    }

    /// Compute scroll offset to bring the paragraph containing `segmentText` into view.
    /// Returns the target content offset, or nil if the segment text cannot be located.
    private func autoScrollOffset(for segmentText: String?) -> CGFloat? {
        guard let segText = segmentText, !segText.isEmpty else { return nil }
        guard currentChapterIndex < chaptersList.count else { return nil }
        let ch = chaptersList[currentChapterIndex]
        let paragraphs = ch.text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let paraIndex = paragraphs.firstIndex(where: { $0.contains(segText) || segText.contains($0) }) else { return nil }
        let cached = chapterHeights
        let pastHeight = currentChapterIndex < cached.count ? cached[0..<currentChapterIndex].reduce(0, +) : chaptersList[0..<currentChapterIndex].reduce(0) { $0 + estimatedChapterHeight($1) }
        let titleHeight: CGFloat = 58
        let hPad: CGFloat = 40
        let containerWidth = UIScreen.main.bounds.width - hPad
        let fontSize = store.readerFontSize
        let font = UIFont(name: store.readerFontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let cjkCharWidth = fontSize
        let charsPerLine = max(1, Int(containerWidth / cjkCharWidth))
        let lineHeight = font.lineHeight + store.readerLineSpacing + 2
        var y: CGFloat = titleHeight
        for i in 0..<paraIndex {
            let trimmed = paragraphs[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let paraLineCount = max(1, (trimmed.count + charsPerLine - 1) / charsPerLine)
            y += CGFloat(paraLineCount) * lineHeight + 8
        }
        return pastHeight + y - 2 * lineHeight
    }

    private func startPlayback(fromParagraphText: String? = nil) async {
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
        store.startPlaybackTask(chapter: chapter, fromParagraph: fromParagraphText)
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
}


