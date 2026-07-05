import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Theme
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

// MARK: - Bookshelf Layout
enum BookshelfLayout: String, CaseIterable, Identifiable {
    case grid = "grid"
    case list = "list"
    case compact = "compact"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .grid: return "网格"
        case .list: return "列表"
        case .compact: return "紧凑"
        }
    }
    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .compact: return "rectangle.grid.1x2"
        }
    }
}

// MARK: - Font Manager
struct FontItem: Hashable {
    let postScriptName: String
    let displayName: String
    
    static func displayNameFor(_ name: String) -> String {
        let known: [String: String] = [
            "PingFangSC-Regular": "苹方", "PingFangSC-Medium": "苹方中黑",
            "PingFangSC-Semibold": "苹方粗体",
            "STHeitiSC-Light": "黑体", "STHeitiSC-Medium": "黑体中",
            "STSongti-SC-Regular": "宋体", "STSongti-SC-Bold": "宋体粗",
            "STKaitiSC-Regular": "楷体", "STKaitiSC-Bold": "楷体粗",
            "STFangsong": "仿宋",
            "HiraMinProN-W3": "明朝", "HiraMinProN-W6": "明朝粗",
            "NotoSansCJKsc-Regular": "思源黑体", "NotoSansCJKsc-Medium": "思源黑体中",
            "NotoSerifCJKsc-Regular": "思源宋体", "NotoSerifCJKsc-Bold": "思源宋体粗",
            "SourceHanSerifSC-Regular": "源ノ明朝", "SourceHanSerifSC-Bold": "源ノ明朝粗",
        ]
        if let chinese = known[name] { return chinese }
        return name.replacingOccurrences(of: "SC-", with: "SC ").replacingOccurrences(of: "-", with: " ")
    }
}

struct FontManager {
    static let availableFonts: [FontItem] = {
        let cjkFamilies = UIFont.familyNames.filter {
            $0.localizedCaseInsensitiveContains("PingFang") ||
            $0.localizedCaseInsensitiveContains("Heiti") ||
            $0.localizedCaseInsensitiveContains("STHeiti") ||
            $0.localizedCaseInsensitiveContains("Hiragino") ||
            $0.localizedCaseInsensitiveContains("Songti") ||
            $0.localizedCaseInsensitiveContains("Noto") ||
            $0.localizedCaseInsensitiveContains("Source Han") ||
            $0.localizedCaseInsensitiveContains("Kaiti") ||
            $0.localizedCaseInsensitiveContains("Fangsong") ||
            $0.localizedCaseInsensitiveContains("YuanTi") ||
            $0.localizedCaseInsensitiveContains("Xingkai")
        }
        var fonts: [FontItem] = []
        for family in cjkFamilies {
            for name in UIFont.fontNames(forFamilyName: family) {
                fonts.append(FontItem(postScriptName: name, displayName: FontItem.displayNameFor(name)))
            }
        }
        if fonts.isEmpty {
            let fallback = ["PingFangSC-Regular", "PingFangSC-Medium", "PingFangSC-Semibold",
                           "STHeitiSC-Light", "STHeitiSC-Medium", "STSongti-SC-Regular",
                           "HiraMinProN-W3", "HiraMinProN-W6", "NotoSansCJKsc-Regular"]
            fonts = fallback.map { FontItem(postScriptName: $0, displayName: FontItem.displayNameFor($0)) }
        }
        return fonts
    }()
}

struct SettingsView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var showingFontPicker = false
    @State private var showingBackupOptions = false
    @State private var showingCacheSize = false
    @State private var showingFileImporter = false
    @State private var cacheSize: String = "计算中..."
    @State private var selectedAppTheme: AppTheme = .system
    @State private var selectedBookshelfLayout: BookshelfLayout = .grid
    @State private var enableHaptics = true
    @State private var autoSaveInterval: Double = 30
    @State private var maxCacheSize: Double = 500
    @State private var cosyStatus: String = "检查中..."
    @State private var isTestingCosy: Bool = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 阅读器设置
                Section(header: Text("阅读器外观")) {
                    NavigationLink(destination: ReaderSettingsView().environmentObject(store)) {
                        Label("阅读设置", systemImage: "textformat")
                    }

                    Picker("主题", selection: Binding(
                        get: { store.readerTheme },
                        set: { store.readerTheme = $0; store.saveState() }
                    )) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("默认字体", selection: Binding(
                        get: { store.readerFontName },
                        set: { store.readerFontName = $0; store.saveState() }
                    )) {
                        ForEach(FontManager.availableFonts, id: \.postScriptName) { font in
                            Text(font.displayName).tag(font.postScriptName)
                        }
                    }

                    Toggle("启用自定义背景", isOn: Binding(
                        get: { store.customBackgroundImage != nil },
                        set: { newValue in
                            if !newValue { store.customBackgroundImage = nil; store.saveState() }
                        }
                    ))
                }

                // MARK: - 阅读界面显示配置
                Section(header: Text("阅读界面显示")) {
                    Toggle("显示章节标题", isOn: Binding(
                        get: { store.showChapterTitle },
                        set: { store.showChapterTitle = $0; store.saveState() }
                    ))
                    Toggle("显示进度条", isOn: Binding(
                        get: { store.showProgressBar },
                        set: { store.showProgressBar = $0; store.saveState() }
                    ))
                    Toggle("显示页码/章节号", isOn: Binding(
                        get: { store.showPageNumber },
                        set: { store.showPageNumber = $0; store.saveState() }
                    ))
                    Toggle("显示时间", isOn: Binding(
                        get: { store.showTime },
                        set: { store.showTime = $0; store.saveState() }
                    ))
                    Toggle("显示电池电量", isOn: Binding(
                        get: { store.showBattery },
                        set: { store.showBattery = $0; store.saveState() }
                    ))
                    Toggle("沉浸模式隐藏状态栏", isOn: Binding(
                        get: { store.immersiveMode },
                        set: { store.immersiveMode = $0; store.saveState() }
                    ))
                }

                // MARK: - 交互设置
                Section(header: Text("交互设置")) {
                    Toggle("启用触觉反馈", isOn: $enableHaptics)
                        .onChange(of: enableHaptics) { _ in
                            if enableHaptics { HapticManager.impact(.light) }
                        }
                    Toggle("双击朗读", isOn: Binding(
                        get: { store.enableDoubleTapToSpeak },
                        set: { store.enableDoubleTapToSpeak = $0; store.saveState() }
                    ))
                    Toggle("长按选中文本", isOn: Binding(
                        get: { store.enableLongPressSelect },
                        set: { store.enableLongPressSelect = $0; store.saveState() }
                    ))
                    Toggle("屏幕常亮", isOn: Binding(
                        get: { store.keepScreenOn },
                        set: { store.keepScreenOn = $0; store.saveState() }
                    ))

                    HStack {
                        Text("自动保存间隔（秒）")
                        Slider(value: $autoSaveInterval, in: 10...300, step: 10)
                        Text("\(Int(autoSaveInterval))")
                    }
                }

                // MARK: - 语音引擎
                Section(header: Label("语音引擎", systemImage: "waveform")) {
                    HStack {
                        Text("CosyVoice 3")
                        Spacer()
                        Circle()
                            .fill(cosyStatus == "就绪" ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(cosyStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("测试语音合成") {
                        Task {
                            isTestingCosy = true
                            let result = await store.testTTSSynthesize()
                            store.statusMessage = result
                            isTestingCosy = false
                        }
                    }
                    .disabled(isTestingCosy)
                }

                // MARK: - 书架设置
                Section(header: Text("书架设置")) {
                    Picker("默认视图", selection: $selectedBookshelfLayout) {
                        ForEach(BookshelfLayout.allCases) { layout in
                            Label(layout.name, systemImage: layout.icon).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("默认排序", selection: Binding(
                        get: { store.defaultSortOption },
                        set: { store.defaultSortOption = $0; store.saveState() }
                    )) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.name).tag(option)
                        }
                    }

                    Toggle("显示封面", isOn: Binding(
                        get: { store.showBookCover },
                        set: { store.showBookCover = $0; store.saveState() }
                    ))
                    Toggle("显示阅读进度", isOn: Binding(
                        get: { store.showReadingProgress },
                        set: { store.showReadingProgress = $0; store.saveState() }
                    ))
                }

                // MARK: - 字体管理
                Section(header: Text("字体管理")) {
                    NavigationLink(destination: FontManagerView().environmentObject(store)) {
                        Label("字体库", systemImage: "textformat.alt")
                    }

                    HStack {
                        Text("当前字体")
                        Spacer()
                        Text(store.readerFontName)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showingFontPicker = true }
                }

                // MARK: - 数据管理
                Section(header: Text("数据管理")) {
                    Button(action: { showingBackupOptions = true }) {
                        Label("备份与恢复", systemImage: "externaldrive.badge.plus")
                    }

                    Button(action: {
                        showingCacheSize = true
                        Task { await calculateCacheSize() }
                    }) {
                        HStack {
                            Label("清理缓存", systemImage: "trash")
                            Spacer()
                            Text(cacheSize)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.red)

                    Button(role: .destructive, action: {
                        store.clearLibrary()
                    }) {
                        Label("清空书架", systemImage: "trash")
                    }
                }

                // MARK: - 应用设置
                Section(header: Text("应用设置")) {
                    Picker("App 主题", selection: $selectedAppTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.name).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedAppTheme) { newValue in
                        applyAppTheme(newValue)
                    }

                    HStack {
                        Text("最大缓存（MB）")
                        Slider(value: $maxCacheSize, in: 50...2000, step: 50)
                        Text("\(Int(maxCacheSize))")
                    }
                }

                // MARK: - 关于
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    Link("隐私政策", destination: URL(string: "https://example.com/privacy")!)
                    Link("用户协议", destination: URL(string: "https://example.com/terms")!)
                    Button("检查更新") {
                        // Check for updates
                    }
                }

                // MARK: - 保存
                Section {
                    Button("保存所有设置") {
                        store.saveSettings()
                        store.saveState()
                        saveAppSettings()
                        store.restartAutoSaveTimer()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showingFontPicker) {
                FontPickerView()
                    .environmentObject(store)
                    .presentationDetents([.medium])
            }
            .actionSheet(isPresented: $showingBackupOptions) {
                ActionSheet(
                    title: Text("备份与恢复"),
                    buttons: [
                        .default(Text("导出数据")) { exportData() },
                        .default(Text("导入数据")) { showingFileImporter = true },
                        .destructive(Text("恢复默认设置")) { resetToDefaults() },
                        .cancel()
                    ]
                )
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.json]) { result in
                handleImportResult(result)
            }
            .alert("缓存大小", isPresented: $showingCacheSize) {
                Button("清理", role: .destructive) { clearCache() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("当前缓存大小：\(cacheSize)\n清理将删除临时音频文件和缩略图")
            }
            .onAppear {
                loadAppSettings()
                Task {
                    await calculateCacheSize()
                    cosyStatus = await CosyVoiceService.shared.isAvailable ? "就绪" : "未就绪"
                }
            }
        }
    }

    // MARK: - Helper Methods
    private func loadAppSettings() {
        selectedAppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "system") ?? .system
        selectedBookshelfLayout = BookshelfLayout(rawValue: UserDefaults.standard.string(forKey: "bookshelfLayout") ?? "grid") ?? .grid
        enableHaptics = UserDefaults.standard.object(forKey: "enableHaptics") as? Bool ?? true
        autoSaveInterval = UserDefaults.standard.object(forKey: "autoSaveInterval") as? Double ?? 30
        maxCacheSize = UserDefaults.standard.object(forKey: "maxCacheSize") as? Double ?? 500
    }

    private func saveAppSettings() {
        UserDefaults.standard.set(selectedAppTheme.rawValue, forKey: "appTheme")
        UserDefaults.standard.set(selectedBookshelfLayout.rawValue, forKey: "bookshelfLayout")
        UserDefaults.standard.set(enableHaptics, forKey: "enableHaptics")
        UserDefaults.standard.set(autoSaveInterval, forKey: "autoSaveInterval")
        UserDefaults.standard.set(maxCacheSize, forKey: "maxCacheSize")
    }

    private func applyAppTheme(_ theme: AppTheme) {
        switch theme {
        case .system:
            UIApplication.shared.windows.forEach { $0.overrideUserInterfaceStyle = .unspecified }
        case .light:
            UIApplication.shared.windows.forEach { $0.overrideUserInterfaceStyle = .light }
        case .dark:
            UIApplication.shared.windows.forEach { $0.overrideUserInterfaceStyle = .dark }
        }
    }

    private func calculateCacheSize() async {
        let urls = [
            FileManager.default.temporaryDirectory,
            (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        ]
        var totalSize: Int64 = 0
        for url in urls {
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                       let size = attrs.fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        await MainActor.run {
            cacheSize = formatter.string(fromByteCount: totalSize)
        }
    }

    private func clearCache() {
        let urls = [
            FileManager.default.temporaryDirectory,
            (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        ]
        for url in urls {
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
        Task { await calculateCacheSize() }
    }

    private func exportData() {
        let docs = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let exportURL = docs.appendingPathComponent("tts-reader-backup-\(Date().timeIntervalSince1970).json")

        do {
            let state = ReaderState(
                bookText: store.bookText,
                chapters: store.chapters,
                characters: store.characters,
                scriptSegments: store.scriptSegments,
                selectedChapterID: store.selectedChapterID,
                books: store.books,
                currentBookTitle: store.currentBookTitle,
                currentBookID: store.currentBookID,
                currentBookProgress: store.currentBookProgress,
                readerFontSize: store.readerFontSize,
                readerLineSpacing: store.readerLineSpacing,
                readerTheme: store.readerTheme,
                selectedVoiceCatalog: store.selectedVoiceCatalog,
                defaultVoice: store.characters.first?.voice ?? "zh-CN-XiaoxiaoNeural",
                defaultRate: store.defaultRate,
                defaultPitch: store.defaultPitch,
                defaultStyle: store.defaultStyle,
                bookmarks: store.bookmarks,
                bookProgressByChapter: store.bookProgressByChapter,
                lastReadChapterIndexByBook: store.lastReadChapterIndexByBook,
                defaultSensitivity: store.defaultSensitivity,
                lastScannedBookText: store.lastScannedBookText,
                playTimeoutSeconds: store.playTimeoutSeconds,
                readerFontName: store.readerFontName,
                readerParagraphSpacing: store.readerParagraphSpacing,
                customBackgroundImage: store.customBackgroundImage,
                showChapterTitle: store.showChapterTitle,
                showProgressBar: store.showProgressBar,
                showPageNumber: store.showPageNumber,
                showTime: store.showTime,
                showBattery: store.showBattery,
                showBookCover: store.showBookCover,
                showReadingProgress: store.showReadingProgress,
                ttsQueue: store.ttsQueue,
                ttsCurrentIndex: store.ttsCurrentIndex,
                ttsIsPlaying: store.ttsIsPlaying,
                ttsChapterTitle: store.ttsChapterTitle,
                ttsSegmentTitle: store.ttsSegmentTitle,
                recommendations: store.recommendations,
                statusMessage: store.statusMessage,
                isBusy: store.isBusy,
                currentPlayingLine: store.currentPlayingLine,
                playProgress: store.playProgress,
                isSpeaking: store.isSpeaking
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: exportURL, options: Data.WritingOptions.atomic)

            let activityVC = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Export failed: \(error)")
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let data = try Data(contentsOf: url)
                let state = try JSONDecoder().decode(ReaderState.self, from: data)
                store.restoreState(state)
                store.statusMessage = "数据导入成功。"
            } catch {
                store.statusMessage = "导入失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            store.statusMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func resetToDefaults() {
        store.clearLibrary()
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }
}

// MARK: - Font Manager View
struct FontManagerView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var customFonts: [_CustomFont] = []
    @State private var showingFontImporter = false

    private let systemFonts: [FontItem] = {
        let cjkFamilies = UIFont.familyNames.filter {
            $0.localizedCaseInsensitiveContains("PingFang") ||
            $0.localizedCaseInsensitiveContains("Heiti") ||
            $0.localizedCaseInsensitiveContains("STHeiti") ||
            $0.localizedCaseInsensitiveContains("Hiragino") ||
            $0.localizedCaseInsensitiveContains("Songti") ||
            $0.localizedCaseInsensitiveContains("Noto") ||
            $0.localizedCaseInsensitiveContains("Source Han") ||
            $0.localizedCaseInsensitiveContains("Kaiti") ||
            $0.localizedCaseInsensitiveContains("Fangsong") ||
            $0.localizedCaseInsensitiveContains("YuanTi") ||
            $0.localizedCaseInsensitiveContains("Xingkai")
        }
        var fonts: [FontItem] = []
        for family in cjkFamilies {
            for name in UIFont.fontNames(forFamilyName: family) {
                fonts.append(FontItem(postScriptName: name, displayName: FontItem.displayNameFor(name)))
            }
        }
        if fonts.isEmpty {
            let fallback = ["PingFangSC-Regular", "PingFangSC-Medium", "PingFangSC-Semibold",
                           "STHeitiSC-Light", "STHeitiSC-Medium", "STSongti-SC-Regular",
                           "HiraMinProN-W3", "HiraMinProN-W6", "NotoSansCJKsc-Regular"]
            fonts = fallback.map { FontItem(postScriptName: $0, displayName: FontItem.displayNameFor($0)) }
        }
        return fonts
    }()

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("系统字体")) {
                    ForEach(systemFonts, id: \.postScriptName) { font in
                        Button(action: {
                            store.readerFontName = font.postScriptName
                            store.saveState()
                            dismiss()
                        }) {
                            HStack {
                                Text(font.displayName)
                                    .font(.custom(font.postScriptName, size: 17))
                                Spacer()
                                if store.readerFontName == font.postScriptName {
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
                                store.readerFontName = font.postScriptName
                                store.saveState()
                                dismiss()
                            }) {
                                HStack {
                                    Text(font.name)
                                        .font(.custom(font.postScriptName, size: 17))
                                    Spacer()
                                    if store.readerFontName == font.postScriptName {
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
            .navigationTitle("字体库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存设置") {
                        store.saveState()
                    }
                }
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
                guard let data = try? Data(contentsOf: url),
                      let provider = CGDataProvider(data: data as CFData),
                      let cgFont = CGFont(provider) else {
                    let name = url.deletingPathExtension().lastPathComponent
                    return _CustomFont(name: name, postScriptName: name, url: url)
                }
                let psName = (cgFont.postScriptName as String?) ?? url.deletingPathExtension().lastPathComponent
                return _CustomFont(name: psName, postScriptName: psName, url: url)
            }
        }
    }

    private func handleFontImport(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get() else { return }
        let docs = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let fontsDir = docs.appendingPathComponent("CustomFonts")
        try? FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
              let font = CGFont(provider) else {
            print("[FONT] Failed to create CGFont from \(url.lastPathComponent)")
            return
        }
        var error: Unmanaged<CFError>?
        CTFontManagerUnregisterGraphicsFont(font, &error)
        error = nil
        CTFontManagerRegisterGraphicsFont(font, &error)
        if let e = error?.takeRetainedValue() {
            print("[FONT] Registration failed for \(url.lastPathComponent): \(e.localizedDescription)")
        } else {
            print("[FONT] Registered font from \(url.lastPathComponent), PS name=\(font.postScriptName as String? ?? "?")")
        }
    }

    private func removeCustomFonts(at offsets: IndexSet) {
        let docs = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let fontsDir = docs.appendingPathComponent("CustomFonts")
        for index in offsets {
            let font = customFonts[index]
            try? FileManager.default.removeItem(at: font.url)
        }
        loadCustomFonts()
    }
}