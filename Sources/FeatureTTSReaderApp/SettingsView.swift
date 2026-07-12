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

struct SettingsView: View {
    @EnvironmentObject var store: ReaderStore
    @State private var showingFontPicker = false
    @State private var showingBackupOptions = false
    @State private var showingCacheSize = false
    @State private var showingFileImporter = false
    @State var cacheSize: String = "计算中..."
    @State var selectedAppTheme: AppTheme = .system
    @State var selectedBookshelfLayout: BookshelfLayout = .grid
    @State var enableHaptics = true
    @State var autoSaveInterval: Double = 30
    @State var maxCacheSize: Double = 500
    @State private var edgeStatus: String = "检查中..."
    @State private var isTestingEdge: Bool = false

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
                        .onChange(of: enableHaptics) { _, newValue in
                            if newValue { HapticManager.impact(.light) }
                            UserDefaults.standard.set(newValue, forKey: "enableHaptics")
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
                    .onChange(of: autoSaveInterval) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "autoSaveInterval")
                    }
                }

                // MARK: - 语音引擎
                Section(header: Label("语音引擎", systemImage: "waveform")) {
                    HStack {
                        Text("Edge TTS")
                        Spacer()
                        Circle()
                            .fill(edgeStatus.contains("就绪") || edgeStatus.contains("服务") ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(edgeStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("测试语音合成") {
                        Task {
                            isTestingEdge = true
                            let result = await store.testTTSSynthesize()
                            store.statusMessage = result
                            isTestingEdge = false
                        }
                    }
                    .disabled(isTestingEdge)

                    VStack(spacing: 6) {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("全局语速")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(UserDefaults.standard.double(forKey: "globalRate")))")
                                .font(.caption.monospaced())
                                .frame(width: 24)
                        }
                        Slider(value: Binding(
                            get: { UserDefaults.standard.double(forKey: "globalRate") },
                            set: { UserDefaults.standard.set($0, forKey: "globalRate") }
                        ), in: -10...10, step: 1)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - 书架设置
                Section(header: Text("书架设置")) {
                    Picker("默认视图", selection: $selectedBookshelfLayout) {
                        ForEach(BookshelfLayout.allCases) { layout in
                            Label(layout.name, systemImage: layout.icon).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedBookshelfLayout) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: "bookshelfLayout")
                    }

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
                    .onChange(of: selectedAppTheme) { _, newValue in
                        applyAppTheme(newValue)
                        UserDefaults.standard.set(newValue.rawValue, forKey: "appTheme")
                    }

                    HStack {
                        Text("最大缓存（MB）")
                        Slider(value: $maxCacheSize, in: 50...2000, step: 50)
                        Text("\(Int(maxCacheSize))")
                    }
                    .onChange(of: maxCacheSize) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "maxCacheSize")
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
                    let health = await EdgeTTSService.shared.healthCheck()
                    edgeStatus = health.contains("就绪") || health.contains("服务") ? health : "未就绪"
                    await MainActor.run { store.edgeTTSLastHealth = edgeStatus }
                }
            }
        }
    }

}