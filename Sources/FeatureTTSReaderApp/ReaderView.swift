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
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let bookID: UUID
    @State private var currentChapter: BookChapter
    @State private var currentChapterIndex: Int
    @State private var paragraphs: [String] = []

    init(book: Book, chapter: BookChapter, bookID: UUID, chapterIndex: Int) {
        self.book = book
        self.bookID = bookID
        let paras = Self.splitParagraphs(chapter.text)
        self._paragraphs = State(initialValue: paras)
        self._currentChapter = State(initialValue: chapter)
        self._currentChapterIndex = State(initialValue: chapterIndex)
    }

    static func splitParagraphs(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let byDoubleNewline = trimmed.components(separatedBy: "\n\n")
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 1 }

        if byDoubleNewline.count >= 2 && byDoubleNewline.allSatisfy({ $0.count < 2000 }) {
            return byDoubleNewline.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        let byNewline = trimmed.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 1 }

        if byNewline.count >= 2 && byNewline.allSatisfy({ $0.count < 2000 }) {
            return byNewline.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        let chunkSize = 800
        var result: [String] = []
        var start = trimmed.startIndex
        while start < trimmed.endIndex {
            let end = trimmed.index(start, offsetBy: chunkSize, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            var split = end
            if end < trimmed.endIndex {
                let segment = trimmed[start..<end]
                if let punct = segment.lastIndex(where: { "。！？!?".contains($0) }) {
                    split = trimmed.index(after: punct)
                }
            }
            let chunk = String(trimmed[start..<split]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { result.append(chunk) }
            start = split
        }
        return result.isEmpty ? [trimmed] : result
    }

    @State private var showBookmarks: Bool = false
    @State private var showSettings: Bool = false
    @State private var showFontPicker: Bool = false
    @State private var showTOC: Bool = false
    @State private var isSpeaking: Bool = false
    @State private var screenBrightness: CGFloat = UIScreen.main.brightness
    @State private var useSystemBrightness: Bool = true
    @State private var isImmersive: Bool = false

    private var textColor: Color {
        switch store.readerTheme {
        case .dark: return .white
        case .light: return Color(red: 0.1, green: 0.1, blue: 0.1)
        case .sepia: return Color(red: 0.2, green: 0.18, blue: 0.15)
        }
    }

    private var backgroundColor: Color {
        if let _ = store.customBackgroundImage { return Color.clear }
        switch store.readerTheme {
        case .dark: return .black
        case .light: return .white
        case .sepia: return Color(red: 0.98, green: 0.93, blue: 0.82)
        }
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
                backgroundColor.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if !isImmersive, store.showChapterTitle { readerHeader }

                if paragraphs.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: store.readerParagraphSpacing + 4) {
                                ForEach(paragraphs.indices, id: \.self) { index in
                                    paragraphView(paragraphs[index], index: index)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture { withAnimation { isImmersive.toggle() } }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { value in
                                    let h = value.translation.width
                                    let v = value.translation.height
                                    if abs(h) > 80, abs(v) < abs(h) * 0.5 {
                                        HapticManager.impact(.light)
                                        if h > 0 { previousChapter() } else { nextChapter() }
                                    } else if abs(v) > 120, abs(h) < abs(v) * 0.3 {
                                        HapticManager.impact(.light)
                                        if v > 0 { previousChapter() } else { nextChapter() }
                                    }
                                }
                        )
                    }
                }

                if !isImmersive { controlBar }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(isImmersive)
        .statusBarHidden(isImmersive)
        .onAppear {
            if currentChapter.text.isEmpty {
                if let cached = store.chaptersForBookCached(bookID), currentChapterIndex < cached.count {
                    currentChapter = cached[currentChapterIndex]
                    paragraphs = Self.splitParagraphs(currentChapter.text)
                }
            }
            store.selectedChapterID = currentChapter.id
            store.rememberLastReadChapter(bookID: bookID, chapterIndex: currentChapterIndex)
            UIApplication.shared.isIdleTimerDisabled = store.keepScreenOn
            if let savedBrightness = UserDefaults.standard.object(forKey: "readerBrightness") as? CGFloat {
                screenBrightness = savedBrightness
                useSystemBrightness = false
                UIScreen.main.brightness = savedBrightness
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if !useSystemBrightness {
                UIScreen.main.brightness = UserDefaults.standard.object(forKey: "systemBrightness") as? CGFloat ?? 0.5
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView().environmentObject(store).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFontPicker) {
            FontPickerView().environmentObject(store).presentationDetents([.medium])
        }
        .sheet(isPresented: $showTOC) {
            ChapterListView().environmentObject(store).presentationDetents([.large])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.page.slash").font(.system(size: 48)).foregroundColor(textColor.opacity(0.3))
            Text("暂无内容").font(.title3).foregroundColor(textColor.opacity(0.5))
            Text("请检查章节内容是否为空").font(.caption).foregroundColor(textColor.opacity(0.3))
        }
    }

    private var readerHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(textColor.opacity(0.7))
            }
            Text(currentChapter.title).font(.headline).lineLimit(1).foregroundColor(textColor).padding(.leading, 8)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(backgroundColor.opacity(0.9))
        .overlay(Divider(), alignment: .bottom)
    }

    private var controlBar: some View {
        VStack(spacing: 0) {
            if showBookmarks {
                bookmarksList
                    .frame(maxHeight: 260)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 12) {
                Button(action: { showBookmarks.toggle() }) {
                    Image(systemName: chapterBookmarks.isEmpty ? "bookmark" : "bookmark.fill").font(.title2)
                }
                Button(action: { store.readerTheme = nextTheme(store.readerTheme) }) {
                    Image(systemName: themeIcon(store.readerTheme)).font(.title2)
                }
                Button(action: { showFontPicker = true }) {
                    Image(systemName: "textformat.alt").font(.title2)
                }
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill").font(.title2)
                }
                Button(action: {
                    if isSpeaking { store.stopPlayback(); isSpeaking = false }
                    else {
                        isSpeaking = true
                        Task { await store.playChapterWithTTS(chapter: currentChapter); isSpeaking = false }
                    }
                }) {
                    Image(systemName: isSpeaking ? "pause.fill" : "play.fill").font(.title2)
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .foregroundColor(textColor)
            .background(.ultraThinMaterial)
        }
        .animation(.easeInOut(duration: 0.2), value: showBookmarks)
    }

    private var bookmarksList: some View {
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
                    ForEach(chapterBookmarks) { bookmark in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bookmark.note.isEmpty ? "\(Int(bookmark.percent * 100))%" : bookmark.note)
                                    .font(.caption).foregroundColor(textColor)
                                Text(bookmark.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundColor(textColor.opacity(0.6))
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
                .listStyle(.plain).frame(maxHeight: 180)
            }
        }
        .background(backgroundColor)
    }

    private func previousChapter() {
        guard let chapters = store.chaptersForBookCached(bookID), !chapters.isEmpty,
              currentChapterIndex > 0, currentChapterIndex - 1 < chapters.count else { return }
        let prev = chapters[currentChapterIndex - 1]
        currentChapter = prev
        currentChapterIndex -= 1
        reloadParagraphs()
        store.selectedChapterID = prev.id
        store.rememberLastReadChapter(bookID: bookID, chapterIndex: currentChapterIndex)
    }

    private func nextChapter() {
        guard let chapters = store.chaptersForBookCached(bookID), !chapters.isEmpty,
              currentChapterIndex < chapters.count - 1 else { return }
        let next = chapters[currentChapterIndex + 1]
        currentChapter = next
        currentChapterIndex += 1
        reloadParagraphs()
        store.selectedChapterID = next.id
        store.rememberLastReadChapter(bookID: bookID, chapterIndex: currentChapterIndex)
    }

    private func reloadParagraphs() {
        paragraphs = Self.splitParagraphs(currentChapter.text)
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

    private func paragraphView(_ para: String, index: Int) -> some View {
        Text("\u{3000}\u{3000}" + para)
            .font(.custom(store.readerFontName, size: store.readerFontSize))
            .foregroundColor(textColor)
            .lineSpacing(store.readerLineSpacing + 2)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(index)
            .onTapGesture(count: 2) {
                guard store.enableDoubleTapToSpeak else { return }
                isSpeaking = true
                Task { await store.playFromParagraph(para); isSpeaking = false }
            }
            .contextMenu {
                Button(action: { UIPasteboard.general.string = para; store.statusMessage = "已复制到剪贴板" }) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                Button(action: { addBookmarkForParagraph(para) }) {
                    Label("书签", systemImage: "bookmark")
                }
                Button(action: { isSpeaking = true; Task { await store.playFromParagraph(para); isSpeaking = false } }) {
                    Label(isSpeaking ? "停止朗读" : "从这里朗读", systemImage: isSpeaking ? "stop.fill" : "play.fill")
                }
                Button(action: shareText(para)) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
    }

    private func addBookmarkForParagraph(_ text: String) {
        guard let chapterID = store.selectedChapterID else { return }
        let percent = store.getChapterProgress(chapterID)
        let note = text.isEmpty ? "\(Int(percent * 100))%" : String(text.prefix(30))
        store.addBookmark(note: note)
    }

    private func shareText(_ text: String) -> () -> Void {
        return {
            let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
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
            if currentHeight + paraHeight > pageHeight && !(result.last?.isEmpty ?? true) {
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
                            Text(para).font(.system(size: fontSize)).foregroundColor(textColor)
                                .lineSpacing(lineSpacing).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding()
                }.background(backgroundColor).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never)).background(backgroundColor)
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
            if currentHeight + paraHeight > pageHeight && !(result.last?.isEmpty ?? true) {
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
                            Text(para).font(.system(size: fontSize)).foregroundColor(textColor)
                                .lineSpacing(lineSpacing).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding()
                }.background(backgroundColor).tag(index)
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
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
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
