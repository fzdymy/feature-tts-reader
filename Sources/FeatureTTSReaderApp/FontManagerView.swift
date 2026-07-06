import SwiftUI

// MARK: - Font Manager View
struct FontManagerView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var customFonts: [_CustomFont] = []
    @State private var showingFontImporter = false

    private let systemFonts = FontManager.availableFonts

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
