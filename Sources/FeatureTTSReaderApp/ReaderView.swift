import SwiftUI
import Combine
import UIKit

// MARK: - ChapterTextView (Pure UIKit, single UITextView, no double-scroll)

struct ChapterTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let lineSpacing: CGFloat
    let insets: UIEdgeInsets
    
    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.isAccessibilityElement = true
        return tv
    }
    
    func updateUIView(_ tv: UITextView, context: Context) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: style,
            .font: font,
            .foregroundColor: textColor
        ]
        
        // Indent paragraphs
        let indented = "\u{3000}\u{3000}" + text
            .replacingOccurrences(of: "\n", with: "\n\u{3000}\u{3000}")
        tv.attributedText = NSAttributedString(string: indented, attributes: attrs)
        
        tv.frame.size.width = UIScreen.main.bounds.width - insets.left - insets.right
        tv.invalidateIntrinsicContentSize()
    }
}

// MARK: - ReaderView

struct ReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let bookID: UUID
    
    // Chapter state – single source of truth
    @State private var currentChapter: BookChapter
    @State private var currentChapterIndex: Int
    @State private var anchorChapterIndex: Int
    @State private var displayedChapterTitle: String
    
    // UI state
    @State private var showBookmarks = false
    @State private var showSettings = false
    @State private var showFontPicker = false
    @State private var showTOC = false
    @State private var isSpeaking = false
    @State private var isImmersive = false
    
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
    
    private var chapters: [BookChapter]? {
        store.chaptersForBookCached(bookID)
    }
    
    private var textColor: Color {
        switch store.readerTheme {
        case .dark: return .white
        case .light: return Color(red: 0.1, green: 0.1, blue: 0.1)
        case .sepia: return Color(red: 0.2, green: 0.18, blue: 0.15)
        }
    }
    
    private var uiTextColor: UIColor {
        switch store.readerTheme {
        case .dark: return .white
        case .light: return UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        case .sepia: return UIColor(red: 0.2, green: 0.18, blue: 0.15, alpha: 1)
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
    
    private var uiFont: UIFont {
        UIFont(name: store.readerFontName, size: CGFloat(store.readerFontSize))
            ?? UIFont.systemFont(ofSize: CGFloat(store.readerFontSize))
    }
    
    private var contentInsets: UIEdgeInsets {
        UIEdgeInsets(top: 12, left: 20, bottom: 80, right: 20)
    }
    
    private var chapterBookmarks: [BookBookmark] {
        store.bookmarks.filter { $0.chapterID == currentChapter.id }
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                if let data = store.customBackgroundImage, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable().scaledToFill().ignoresSafeArea()
                } else {
                    bgColor.ignoresSafeArea()
                }
                
                // Main content – single UITextView inside ScrollView
                ScrollView {
                    ChapterTextView(
                        text: currentChapter.text,
                        font: uiFont,
                        textColor: uiTextColor,
                        lineSpacing: CGFloat(store.readerLineSpacing + 2),
                        insets: contentInsets
                    )
                    .frame(
                        minHeight: geo.size.height - contentInsets.top - contentInsets.bottom,
                        alignment: .top
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        withAnimation { isImmersive.toggle() }
                    }
                )
                
                // Immersive: floating chapter title
                if isImmersive, store.showChapterTitle {
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
                
                // Non-immersive: header + control bar
                VStack {
                    if !isImmersive, store.showChapterTitle { readerHeader }
                    Spacer()
                    if !isImmersive { controlBar }
                }
                
                // Immersive: mini status bar
                if isImmersive,
                   store.showProgressBar || store.showPageNumber || store.showTime || store.showBattery {
                    VStack {
                        Spacer()
                        readerStatusBar
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(isImmersive)
        .statusBarHidden(isImmersive)
        .onReceive(timer) { _ in
            currentTime = Date()
            updateBatteryLevel()
        }
        .onAppear {
            updateBatteryLevel()
            store.selectedChapterID = currentChapter.id
            UIApplication.shared.isIdleTimerDisabled = store.keepScreenOn
            if let brightness = UserDefaults.standard.object(forKey: "readerBrightness") as? CGFloat {
                screenBrightness = brightness
                useSystemBrightness = false
                UIScreen.main.brightness = brightness
            }
            ReaderStore.debugLog("[RVIEW-APPEAR] idx=\(currentChapterIndex)")
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            ReaderStore.saveLastChapterIndex(anchorChapterIndex, for: bookID)
            if let chs = chapters, anchorChapterIndex < chs.count {
                store.setChapterProgress(chs[anchorChapterIndex].id, percent: 1.0)
            }
            store.saveState()
            if !useSystemBrightness {
                UIScreen.main.brightness = UserDefaults.standard.object(forKey: "systemBrightness") as? CGFloat ?? 0.5
            }
        }
        .onChange(of: store.externalChapterNavigate) { nav in
            guard let nav, nav.bookID == bookID,
                  let chs = chapters, nav.chapterIndex < chs.count else { return }
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
                if let chs = chapters {
                    store.setChapterProgress(chs[min(currentChapterIndex, chs.count - 1)].id, percent: 1.0)
                }
                jumpTo(index, explicit: true)
            }
            .environmentObject(store)
            .presentationDetents([.large])
        }
    }
    
    // MARK: - Navigation
    
    private func jumpTo(_ index: Int, explicit: Bool) {
        guard let chs = chapters, index >= 0, index < chs.count else { return }
        currentChapterIndex = index
        currentChapter = chs[index]
        displayedChapterTitle = chs[index].title
        store.selectedChapterID = chs[index].id
        ReaderStore.saveLastChapterIndex(index, for: bookID)
        if explicit { anchorChapterIndex = index }
        // Preload adjacent texts in background
        let lower = max(0, index - 2)
        let upper = min(chs.count - 1, index + 2)
        DispatchQueue.global(qos: .background).async {
            for i in lower...upper where i != index {
                _ = chs[i].text // trigger text load
            }
        }
        ReaderStore.debugLog("[JUMP] idx=\(index)")
    }
    
    private func previousChapter() {
        guard let chs = chapters, currentChapterIndex > 0 else { return }
        let idx = currentChapterIndex - 1
        if idx + 1 < chs.count {
            store.setChapterProgress(chs[idx + 1].id, percent: 1.0)
        }
        jumpTo(idx, explicit: true)
    }
    
    private func nextChapter() {
        guard let chs = chapters, currentChapterIndex < chs.count - 1 else { return }
        store.setChapterProgress(chs[currentChapterIndex].id, percent: 1.0)
        jumpTo(currentChapterIndex + 1, explicit: true)
    }
    
    // MARK: - Subviews
    
    private var readerHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(textColor.opacity(0.7))
            }
            Text(displayedChapterTitle)
                .font(.headline).lineLimit(1)
                .foregroundColor(textColor)
                .padding(.leading, 8)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(bgColor.opacity(0.9))
        .overlay(Divider(), alignment: .bottom)
    }
    
    private var readerStatusBar: some View {
        HStack(spacing: 8) {
            if store.showProgressBar {
                Text(progressText)
                    .font(.caption2).foregroundColor(textColor.opacity(0.6)).monospacedDigit()
            }
            if store.showPageNumber {
                let pct = chapters?.isEmpty ?? true ? 0
                    : min(Double(currentChapterIndex + 1) / Double(max(chapters?.count ?? 1, 1)), 1)
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
        guard let chs = chapters, !chs.isEmpty else { return "—" }
        return "\(currentChapterIndex + 1)/\(chs.count)"
    }
    
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
                    systemName: isSpeaking ? "pause.fill" : "play.fill",
                    action: {
                        if isSpeaking { store.stopPlayback(); isSpeaking = false }
                        else {
                            isSpeaking = true
                            Task { await store.playChapterWithTTS(chapter: currentChapter); isSpeaking = false }
                        }
                    }
                )
                controlButton(
                    systemName: "chevron.right",
                    disabled: currentChapterIndex >= (chapters?.count ?? 1) - 1,
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
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel >= 0
            ? Int(UIDevice.current.batteryLevel * 100) : -1
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
}
