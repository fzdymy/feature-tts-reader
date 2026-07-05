import SwiftUI

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
                        .onChange(of: useSystemBrightness) { _, newValue in
                            if newValue { UIScreen.main.brightness = UIScreen.main.brightness }
                        }
                    if !useSystemBrightness {
                        HStack {
                            Text("亮度")
                            Slider(value: $customBrightness, in: 0...1)
                                .onChange(of: customBrightness) { _, newValue in
                                    UIScreen.main.brightness = newValue
                                    UserDefaults.standard.set(newValue, forKey: "readerBrightness")
                                }
                            Text("\(Int(customBrightness * 100))%")
                        }
                    }
                    Toggle("屏幕常亮", isOn: $keepScreenOn)
                        .onChange(of: keepScreenOn) { _, newValue in
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
                    Button("保存并应用") { dismiss() }
                        .frame(maxWidth: .infinity, alignment: .center).foregroundColor(.blue)
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
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

    private let availableCJKFonts: [String] = FontManager.availableFonts.map(\.postScriptName)

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("系统字体")) {
                    ForEach(availableCJKFonts, id: \.self) { fontName in
                        Button(action: { store.readerFontName = fontName; dismiss() }) {
                            HStack {
                                Text(displayNameFor(fontName)).font(.custom(fontName, size: 17))
                                Spacer()
                                if store.readerFontName == fontName { Image(systemName: "checkmark").foregroundColor(.blue) }
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
                            Button(action: { store.readerFontName = font.postScriptName; dismiss() }) {
                                HStack {
                                    Text(font.name).font(.custom(font.postScriptName, size: 17))
                                    Spacer()
                                    if store.readerFontName == font.postScriptName { Image(systemName: "checkmark").foregroundColor(.blue) }
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .fileImporter(isPresented: $showingFontImporter, allowedContentTypes: [.font], allowsMultipleSelection: true) { result in
                handleFontImport(result)
            }
            .onAppear { loadCustomFonts() }
        }
    }

    private func displayNameFor(_ postScriptName: String) -> String {
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
        if let chinese = known[postScriptName] { return chinese }
        let cleaned = postScriptName
            .replacingOccurrences(of: "SC-", with: "SC ")
            .replacingOccurrences(of: "-", with: " ")
        return cleaned
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
        for index in offsets { try? FileManager.default.removeItem(at: customFonts[index].url) }
        loadCustomFonts()
    }
}

struct _CustomFont: Identifiable {
    let id = UUID()
    let name: String
    let postScriptName: String
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
                        Button("清除自定义背景", role: .destructive) { store.customBackgroundImage = nil }
                    }
                }
            }
            .navigationTitle("阅读背景").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showingImagePicker) { ImagePicker(image: $selectedImage) }
            .onChange(of: selectedImage) { _, newImage in
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
