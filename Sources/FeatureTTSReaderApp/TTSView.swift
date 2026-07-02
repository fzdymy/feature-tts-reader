import SwiftUI

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var rawText: String = ""

    var body: some View {
        NavigationStack {
            List {
                serverSection
                catalogSection
                importSection
                chapterSection
                characterSection
                playbackSection
                statusSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("TTS")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView().environmentObject(store)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onAppear { rawText = store.bookText }
            .onChange(of: store.bookText) { rawText = $0 }
        }
    }

    private var serverSection: some View {
        Section(header: Text("TTS 服务器")) {
            NavigationLink(destination: LazyView(TTSServerListView().environmentObject(store))) {
                HStack {
                    Label(store.activeServer?.name ?? "未配置", systemImage: "server.rack")
                    Spacer()
                    if store.activeServer != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var catalogSection: some View {
        Section(header: Text("音色目录")) {
            NavigationLink(destination: LazyView(VoiceFineTuneView().environmentObject(store))) {
                Label("音色微调管理", systemImage: "slider.horizontal.3")
            }
            HStack(spacing: 12) {
                catalogButton(.chinese35)
                catalogButton(.fullChinese)
            }
        }
    }

    private func catalogButton(_ source: VoiceCatalogSource) -> some View {
        Button(action: { store.switchCatalog(to: source) }) {
            Text(source.displayName)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(store.selectedVoiceCatalog == source ? Color.accentColor : Color.gray.opacity(0.15))
                .foregroundColor(store.selectedVoiceCatalog == source ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.borderless)
    }

    private var importSection: some View {
        Section(header: Text("导入")) {
            TextEditor(text: $rawText)
                .frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
            if store.importProgress > 0 {
                ProgressView(value: store.importProgress)
            }
            HStack {
                Button("导入文本") { Task { await store.importText(rawText); rawText = store.bookText } }
                Spacer()
                Button("扫描章节") { Task { await store.parseChaptersAsync() } }
                Spacer()
                Button("识别角色") { Task { await store.scanCharacters() } }
            }
        }
    }

    private var chapterSection: some View {
        Section(header: Text("章节")) {
            if store.chapters.isEmpty {
                Text("未发现章节，请先导入小说文本。").foregroundColor(.secondary)
            } else {
                Text("共 \(store.chapters.count) 章").font(.subheadline).foregroundColor(.secondary)
                Button("生成朗读脚本") { Task { await store.buildScript(for: false) } }
                if !store.scriptSegments.isEmpty {
                    Text("脚本段落：\(store.scriptSegments.count) 条").foregroundColor(.secondary)
                }
            }
        }
    }

    private var characterSection: some View {
        Section(header: Text("角色")) {
            if store.characters.isEmpty {
                Text("未识别到角色，请先导入小说并扫描。").foregroundColor(.secondary)
            } else {
                ForEach(store.characters) { ch in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.name).font(.headline)
                            Text(ch.info).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(ch.voice).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var playbackSection: some View {
        Section(header: Text("朗读")) {
            HStack {
                Button(action: { Task { await store.playSelectedChapter() } }) {
                    Label("当前章节", systemImage: "play.fill")
                }
                Spacer()
                Button(action: { Task { await store.playWholeBook() } }) {
                    Label("全书", systemImage: "book.fill")
                }
            }
            Button(action: store.stopPlayback) {
                Label("停止", systemImage: "stop.fill")
            }
            if !store.ttsChapterTitle.isEmpty {
                ProgressView(value: store.playProgress)
            }
        }
    }

    private var statusSection: some View {
        Section(header: Text("状态")) {
            Text(store.statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ view: @autoclosure @escaping () -> Content) { self.build = view }
    var body: some View { build() }
}

struct TTSView_Previews: PreviewProvider {
    static var previews: some View {
        TTSView().environmentObject(ReaderStore())
    }
}
