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

struct ReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book
    let chapter: BookChapter
    let bookID: UUID
    let chapterIndex: Int
    
    @State private var showControls: Bool = true
    @State private var showBookmarks: Bool = false
    @State private var showSettings: Bool = false
    @State private var showFontPicker: Bool = false
    @State private var showTOC: Bool = false
    @State private var currentScale: CGFloat = 1.0
    @State private var scrollProgress: Double = 0
    @State private var contentHeight: CGFloat = 0
    @State private var isSpeaking: Bool = false
    @State private var speakingIndex: Int = 0
    @State private var showParagraphMenu: Bool = false
    @State private var selectedParagraph: String = ""
    @State private var paragraphRect: CGRect = .zero
    @State private var paragraphs: [String] = []
    @State private var screenBrightness: CGFloat = UIScreen.main.brightness
    @State private var useSystemBrightness: Bool = true
    @State private var isImmersive: Bool = false
    @State private var pageMode: PageMode = .scroll
    @State private var currentPage: Int = 0
    @State private var pageCount: Int = 1
    @State private var paragraphFrames: [CGRect] = []
    
    private var textColor: Color {
        switch store.readerTheme {
        case .dark: return .white
        case .light: return .primary
        case .sepia: return Color(red: 0.2, green: 0.18, blue: 0.15)
        }
    }
    
    private var backgroundColor: Color {
        if let customBG = store.customBackgroundImage {
            return Color.clear
        }
        switch store.readerTheme {
        case .dark: return .black
        case .light: return .white
        case .sepia: return Color(red: 0.98, green: 0.93, blue: 0.82)
        }
    }
    
    private var chapterBookmarks: [BookBookmark] {
        store.bookmarks.filter { $0.chapterID == chapter.id }
    }
    
    private var fontBinding: Binding<Double> {
        Binding(get: { store.readerFontSize }, set: { store.readerFontSize = $0; store.saveState() })
    }
    
    private var lineSpacingBinding: Binding<Double> {
        Binding(get: { store.readerLineSpacing }, set: { store.readerLineSpacing = $0; store.saveState() })
    }
    
    private var paragraphSpacingBinding: Binding<Double> {
        Binding(get: { store.readerParagraphSpacing }, set: { store.readerParagraphSpacing = $0; store.saveState() })
    }
    
    var body: some View {
        ZStack {
            if let customBG = store.customBackgroundImage, let uiImage = UIImage(data: customBG) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                backgroundColor
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                if !isImmersive {
                    readerHeader
                }
                
                readerContent
                
                if !isImmersive || showControls {
                    readerControls
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(isImmersive || !showControls)
        .statusBarHidden(isImmersive)
        .onAppear {
            store.selectedChapterID = chapter.id
            store.rememberLastReadChapter(bookID: bookID, chapterIndex: chapterIndex)
            store.saveState()
            paragraphs = chapter.text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            if let savedBrightness = UserDefaults.standard.object(forKey: "readerBrightness") as? CGFloat {
                screenBrightness = savedBrightness
                useSystemBrightness = false
                UIScreen.main.brightness = savedBrightness
            }
        }
        .onDisappear {
            store.saveState()
            if !useSystemBrightness {
                UIScreen.main.brightness = UserDefaults.standard.object(forKey: "systemBrightness") as? CGFloat ?? 0.5
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFontPicker) {
            FontPickerView()
                .environmentObject(store)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showTOC) {
            ChapterListView()
                .environmentObject(store)
                .presentationDetents([.large])
        }
        .onTapGesture(count: 2) {
            if !selectedParagraph.isEmpty {
                HapticManager.impact(.medium)
                isSpeaking = true
                Task {
                    await store.playFromParagraph(selectedParagraph)
                    await MainActor.run { isSpeaking = false }
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            showParagraphMenu = true
        }
    }
    
    private var readerHeader: some View {
        HStack {
            Text(chapter.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(textColor)
            
            Spacer()
            
            if pageMode == .horizontal || pageMode == .vertical {
                Text("\(currentPage + 1) / \(pageCount)")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor.opacity(0.9))
        .overlay(Divider(), alignment: .bottom)
    }
    
    private var readerContent: some View {
        GeometryReader { geometry in
            switch pageMode {
            case .scroll:
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: store.readerParagraphSpacing) {
                            ForEach(paragraphs.indices, id: \.self) { index in
                                paragraphView(paragraphs[index], index: index)
                                    .id(index)
                                    .background(GeometryReader { geo in
                                        Color.clear.preference(key: ParagraphFrameKey.self, value: [index: geo.frame(in: .named("scroll"))])
                                    })
                            }
                        }
                        .padding()
                        .id("content")
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                        })
                        Spacer().frame(height: 100)
                        Color.clear.frame(height: 1).background(GeometryReader { geo in
                            Color.clear.preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                        })
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ContentHeightKey.self) { height in
                        contentHeight = height
                    }
                    .onPreferenceChange(ScrollOffsetKey.self) { minY in
                        DispatchQueue.main.async {
                            let contentH = max(contentHeight, geometry.size.height)
                            let offset = -minY
                            let percent = max(0, min(1, Double(offset / max(200, contentH))))
                            scrollProgress = percent * 100
                            if let chapterID = store.selectedChapterID {
                                store.setChapterProgress(chapterID, percent: percent)
                            }
                        }
                    }
                    .onPreferenceChange(ParagraphFrameKey.self) { frames in
                        paragraphFrames = frames.map { $0.value }
                    }
                    .onTapGesture { HapticManager.impact(.light); withAnimation { showControls.toggle() } }
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                if value.translation.width > 50 {
                                    HapticManager.impact(.light)
                                    previousChapter()
                                } else if value.translation.width < -50 {
                                    HapticManager.impact(.light)
                                    nextChapter()
                                }
                            }
                    )
                }
            case .horizontal:
                HorizontalPageView(
                    paragraphs: paragraphs,
                    fontSize: store.readerFontSize,
                    lineSpacing: store.readerLineSpacing,
                    paragraphSpacing: store.readerParagraphSpacing,
                    textColor: textColor,
                    backgroundColor: backgroundColor,
                    currentPage: $currentPage,
                    pageCount: $pageCount,
                    geometry: geometry
                )
                .onTapGesture { HapticManager.impact(.light); withAnimation { showControls.toggle() } }
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            if value.translation.width > 50 && currentPage > 0 {
                                HapticManager.impact(.light)
                                currentPage -= 1
                            } else if value.translation.width < -50 && currentPage < pageCount - 1 {
                                HapticManager.impact(.light)
                                currentPage += 1
                            }
                        }
                )
            case .vertical:
                VerticalPageView(
                    paragraphs: paragraphs,
                    fontSize: store.readerFontSize,
                    lineSpacing: store.readerLineSpacing,
                    paragraphSpacing: store.readerParagraphSpacing,
                    textColor: textColor,
                    backgroundColor: backgroundColor,
                    currentPage: $currentPage,
                    pageCount: $pageCount,
                    geometry: geometry
                )
                .onTapGesture { HapticManager.impact(.light); withAnimation { showControls.toggle() } }
            }
        }
    }
    
    private func paragraphView(_ para: String, index: Int) -> some View {
        Text(para)
            .font(.custom(store.readerFontName, size: store.readerFontSize))
            .foregroundColor(textColor)
            .lineSpacing(store.readerLineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(index)
            .onTapGesture(count: 2) {
                selectedParagraph = para
                isSpeaking = true
                Task {
                    await store.playFromParagraph(para)
                    await MainActor.run { isSpeaking = false }
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                selectedParagraph = para
                showParagraphMenu = true
            }
            .contextMenu {
                Button(action: { copyToClipboard(para) }) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                Button(action: { addBookmarkForParagraph(para) }) {
                    Label("书签", systemImage: "bookmark")
                }
                Button(action: { 
                    isSpeaking = true
                    Task {
                        await store.playFromParagraph(para)
                        await MainActor.run { isSpeaking = false }
                    }
                }) {
                    Label(isSpeaking ? "停止朗读" : "从这里朗读", systemImage: isSpeaking ? "stop.fill" : "play.fill")
                }
                Button(action: { shareText(para) }) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
    }
    
    private var readerControls: some View {
        VStack(spacing: 0) {
            if showBookmarks {
                bookmarksList
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer()
            }
            
            Divider()
            
            HStack(spacing: 16) {
                if pageMode != .scroll {
                    Button(action: { if currentPage > 0 { currentPage -= 1 } }) {
                        Image(systemName: "chevron.left.circle.fill").font(.title2)
                    }
                    Button(action: { if currentPage < pageCount - 1 { currentPage += 1 } }) {
                        Image(systemName: "chevron.right.circle.fill").font(.title2)
                    }
                } else {
                    Button(action: { adjustPage(by: -0.1) }) {
                        Image(systemName: "chevron.up.circle.fill").font(.title2)
                    }
                    Button(action: { adjustPage(by: 0.1) }) {
                        Image(systemName: "chevron.down.circle.fill").font(.title2)
                    }
                }
                
                Button(action: { showBookmarks.toggle() }) {
                    Image(systemName: chapterBookmarks.isEmpty ? "bookmark" : "bookmark.fill").font(.title2)
                }
                
                Button(action: { store.readerTheme = nextTheme(store.readerTheme); store.saveState() }) {
                    Image(systemName: themeIcon(store.readerTheme)).font(.title2)
                }
                
                Slider(value: fontBinding, in: 14...32, step: 1)
                    .frame(maxWidth: 150)
                
                Button(action: { showFontPicker = true }) {
                    Image(systemName: "textformat.alt").font(.title2)
                }
                
                Button(action: {
                    if isSpeaking {
                        store.stopPlayback()
                        isSpeaking = false
                    } else {
                        isSpeaking = true
                        Task {
                            await store.playChapterWithTTS(chapter: chapter)
                            await MainActor.run { isSpeaking = false }
                        }
                    }
                }) {
                    Image(systemName: isSpeaking ? "pause.fill" : "play.fill").font(.title2)
                }
                
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill").font(.title2)
                }
                
                Button(action: { addBookmarkForParagraph("") }) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }
            .padding()
            .foregroundColor(textColor)
            .background(VisualEffectView(style: .systemThinMaterial))
        }
        .animation(.easeInOut(duration: 0.2), value: showBookmarks)
    }
    
    private var bookmarksList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("书签 (\(chapterBookmarks.count))")
                    .font(.headline)
                    .foregroundColor(textColor)
                Spacer()
                Button("关闭") { showBookmarks = false }
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            if chapterBookmarks.isEmpty {
                Text("暂无书签").foregroundColor(textColor.opacity(0.5)).padding()
            } else {
                List {
                    ForEach(chapterBookmarks) { bookmark in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bookmark.note.isEmpty ? "\(Int(bookmark.percent * 100))%" : bookmark.note)
                                    .font(.caption)
                                    .foregroundColor(textColor)
                                Text(bookmark.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(textColor.opacity(0.6))
                            }
                            Spacer()
                            Button(action: { store.removeBookmark(bookmark.id) }) {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .listRowBackground(backgroundColor)
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 200)
            }
        }
        .background(backgroundColor)
    }
    
    private func adjustPage(by delta: Double) {
        if let chapterID = store.selectedChapterID {
            let current = store.getChapterProgress(chapterID)
            let next = min(max(0, current + delta), 1)
            store.setChapterProgress(chapterID, percent: next)
            store.statusMessage = "已翻页，进度：\(Int(next * 100))%"
        }
    }
    
    private func previousChapter() {
        guard chapterIndex > 0,
              let prevChapter = store.chapters[safe: chapterIndex - 1] else { return }
        store.selectedChapterID = prevChapter.id
        store.rememberLastReadChapter(bookID: bookID, chapterIndex: chapterIndex - 1)
        store.saveState()
    }
    
    private func nextChapter() {
        guard chapterIndex < store.chapters.count - 1,
              let nextChapter = store.chapters[safe: chapterIndex + 1] else { return }
        store.selectedChapterID = nextChapter.id
        store.rememberLastReadChapter(bookID: bookID, chapterIndex: chapterIndex + 1)
        store.saveState()
    }
    
    private func nextTheme(_ current: ReaderTheme) -> ReaderTheme {
        switch current {
        case .light: return .sepia
        case .sepia: return .dark
        case .dark: return .light
        }
    }
    
    private func themeIcon(_ theme: ReaderTheme) -> String {
        switch theme {
        case .light: return "sun.max"
        case .sepia: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        store.statusMessage = "已复制到剪贴板"
    }
    
    private func addBookmarkForParagraph(_ text: String) {
        guard let chapterID = store.selectedChapterID else { return }
        let percent = store.getChapterProgress(chapterID)
        let note = text.isEmpty ? "\(Int(percent * 100))%" : String(text.prefix(30))
        store.addBookmark(note: note)
    }
    
    private func shareText(_ text: String) {
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

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
        case .horizontal: return "book.closed"
        case .vertical: return "arrow.up.and.down"
        }
    }
}

struct HorizontalPageView: View {
    let paragraphs: [String]
    let fontSize: Double
    let lineSpacing: Double
    let paragraphSpacing: Double
    let textColor: Color
    let backgroundColor: Color
    @Binding var currentPage: Int
    @Binding var pageCount: Int
    let geometry: GeometryProxy
    
    private var pages: [[String]] {
        var result: [[String]] = [[]]
        var currentHeight: CGFloat = 0
        let pageHeight = geometry.size.height - 120
        let estimatedLineHeight = fontSize + lineSpacing
        
        for para in paragraphs {
            let paraHeight = estimatedLineHeight * CGFloat(max(1, para.count / 20)) + paragraphSpacing
            if currentHeight + paraHeight > pageHeight && !result.last!.isEmpty {
                result.append([])
                currentHeight = 0
            }
            result[result.count - 1].append(para)
            currentHeight += paraHeight
        }
        return result
    }
    
    var body: some View {
        let pages = pages
        let _ = DispatchQueue.main.async { pageCount = pages.count }
        
        return TabView(selection: $currentPage) {
            ForEach(pages.indices, id: \.self) { index in
                ScrollView {
                    VStack(alignment: .leading, spacing: paragraphSpacing) {
                        ForEach(pages[index], id: \.self) { para in
                            Text(para)
                                .font(.system(size: fontSize))
                                .foregroundColor(textColor)
                                .lineSpacing(lineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .background(backgroundColor)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(backgroundColor)
    }
}

struct VerticalPageView: View {
    let paragraphs: [String]
    let fontSize: Double
    let lineSpacing: Double
    let paragraphSpacing: Double
    let textColor: Color
    let backgroundColor: Color
    @Binding var currentPage: Int
    @Binding var pageCount: Int
    let geometry: GeometryProxy
    
    private var pages: [[String]] {
        var result: [[String]] = [[]]
        var currentHeight: CGFloat = 0
        let pageHeight = geometry.size.height - 120
        let estimatedLineHeight = fontSize + lineSpacing
        
        for para in paragraphs {
            let paraHeight = estimatedLineHeight * CGFloat(max(1, para.count / 20)) + paragraphSpacing
            if currentHeight + paraHeight > pageHeight && !result.last!.isEmpty {
                result.append([])
                currentHeight = 0
            }
            result[result.count - 1].append(para)
            currentHeight += paraHeight
        }
        return result
    }
    
    var body: some View {
        let pages = pages
        let _ = DispatchQueue.main.async { pageCount = pages.count }
        
        return TabView(selection: $currentPage) {
            ForEach(pages.indices, id: \.self) { index in
                ScrollView {
                    VStack(alignment: .leading, spacing: paragraphSpacing) {
                        ForEach(pages[index], id: \.self) { para in
                            Text(para)
                                .font(.system(size: fontSize))
                                .foregroundColor(textColor)
                                .lineSpacing(lineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .background(backgroundColor)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .rotationEffect(.degrees(-90))
        .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
        .background(backgroundColor)
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ParagraphFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

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
                        Slider(value: Binding(get: { store.readerFontSize }, set: { store.readerFontSize = $0; store.saveState() }), in: 14...32, step: 1)
                        Text("\(Int(store.readerFontSize))")
                    }
                    HStack {
                        Text("行距")
                        Slider(value: Binding(get: { store.readerLineSpacing }, set: { store.readerLineSpacing = $0; store.saveState() }), in: 0...20, step: 1)
                        Text("\(Int(store.readerLineSpacing))")
                    }
                    HStack {
                        Text("段距")
                        Slider(value: Binding(get: { store.readerParagraphSpacing }, set: { store.readerParagraphSpacing = $0; store.saveState() }), in: 0...30, step: 1)
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
                    Picker("主题", selection: Binding(get: { store.readerTheme }, set: { store.readerTheme = $0; store.saveState() })) {
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
                    Button(action: { store.customBackgroundImage = nil; store.saveState() }) {
                        Text("清除背景图")
                            .foregroundColor(.red)
                    }
                    .disabled(store.customBackgroundImage == nil)
                }
                
                Section(header: Text("字体")) {
                    Button(action: { showFontPicker = true }) {
                        HStack {
                            Text("当前字体")
                            Spacer()
                            Text(store.readerFontName)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("屏幕与亮度")) {
                    Toggle("跟随系统亮度", isOn: $useSystemBrightness)
                        .onChange(of: useSystemBrightness) { newValue in
                            if newValue {
                                UIScreen.main.brightness = UIScreen.main.brightness
                            }
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
                        }
                }
                
                Section(header: Text("阅读界面显示")) {
                    Toggle("显示章节标题", isOn: Binding(get: { store.showChapterTitle }, set: { store.showChapterTitle = $0; store.saveState() }))
                    Toggle("显示进度条", isOn: Binding(get: { store.showProgressBar }, set: { store.showProgressBar = $0; store.saveState() }))
                    Toggle("显示页码", isOn: Binding(get: { store.showPageNumber }, set: { store.showPageNumber = $0; store.saveState() }))
                    Toggle("显示时间", isOn: Binding(get: { store.showTime }, set: { store.showTime = $0; store.saveState() }))
                    Toggle("显示电池", isOn: Binding(get: { store.showBattery }, set: { store.showBattery = $0; store.saveState() }))
                }
                
                Section {
                    Button("保存并应用") {
                        store.saveState()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.blue)
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
                FontPickerView()
                    .environmentObject(store)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showBackgroundPicker) {
                BackgroundPickerView()
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                useSystemBrightness = UserDefaults.standard.object(forKey: "useSystemBrightness") as? Bool ?? true
                customBrightness = UserDefaults.standard.object(forKey: "readerBrightness") as? Double ?? 0.5
                keepScreenOn = UIApplication.shared.isIdleTimerDisabled
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
            }
        }
    }
}

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
                        Button(action: {
                            store.readerFontName = font
                            store.saveState()
                            dismiss()
                        }) {
                            HStack {
                                Text(font)
                                    .font(.custom(font, size: 17))
                                Spacer()
                                if store.readerFontName == font {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
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
                            Button(action: {
                                store.readerFontName = font.name
                                store.saveState()
                                dismiss()
                            }) {
                                HStack {
                                    Text(font.name)
                                        .font(.custom(font.name, size: 17))
                                    Spacer()
                                    if store.readerFontName == font.name {
                                        Image(systemName: "checkmark").foregroundColor(.blue)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                        .onDelete { indexSet in
                            removeCustomFonts(at: indexSet)
                        }
                    }
                    Button(action: { showingFontImporter = true }) {
                        Label("导入字体", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("选择字体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showingFontImporter, allowedContentTypes: [.font], allowsMultipleSelection: true) { result in
                handleFontImport(result)
            }
            .onAppear { loadCustomFonts() }
        }
    }
    
    private func loadCustomFonts() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
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
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fontsDir = docs.appendingPathComponent("CustomFonts")
        try? FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        
        for url in urls {
            let dest = fontsDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                registerFont(at: dest)
            } catch {
                print("Font import error: \(error)")
            }
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
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fontsDir = docs.appendingPathComponent("CustomFonts")
        for index in offsets {
            let font = customFonts[index]
            try? FileManager.default.removeItem(at: font.url)
        }
        loadCustomFonts()
    }
}

struct _CustomFont: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

struct BackgroundPickerView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    
    private let presetBackgrounds = [
        ("无", nil),
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
                            store.saveState()
                            dismiss()
                        }) {
                            HStack {
                                if let assetName = assetName, let img = UIImage(named: assetName) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(8)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 40, height: 40)
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
                                Image(uiImage: img)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(8)
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
                            store.saveState()
                        }
                    }
                }
            }
            .navigationTitle("阅读背景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { newImage in
                if let img = newImage, let data = img.pngData() {
                    store.customBackgroundImage = data
                    store.saveState()
                    dismiss()
                }
            }
        }
    }
}

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
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct VisualEffectView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct ReaderView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ReaderView(book: Book(id: UUID(), title: "测试书籍", text: "内容", importedAt: Date()),
                       chapter: BookChapter(id: UUID(), title: "第一章", text: "测试内容\n\n第二段"),
                       bookID: UUID(), chapterIndex: 0)
                .environmentObject(ReaderStore())
        }
    }
}