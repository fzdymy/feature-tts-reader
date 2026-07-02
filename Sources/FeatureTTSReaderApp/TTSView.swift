import SwiftUI

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore

    var body: some View {
        NavigationStack {
            Form {
                serverPicker
                catalogSection
                playbackSection
                importSection
                statusSection
            }
            .navigationTitle("TTS")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView().environmentObject(store)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    // MARK: - 服务器

    private var serverPicker: some View {
        Section("TTS 服务器") {
            if store.ttsServers.isEmpty {
                NavigationLink(destination: TTSServerListView().environmentObject(store)) {
                    Label("添加服务器", systemImage: "plus.circle")
                }
            } else {
                NavigationLink(destination: TTSServerListView().environmentObject(store)) {
                    HStack {
                        Label("当前", systemImage: "server.rack")
                        Spacer()
                        Text(store.activeServer?.name ?? "未选择")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 音色目录

    private var catalogSection: some View {
        Section("音色") {
            HStack(spacing: 12) {
                catalogButton(.chinese35)
                catalogButton(.fullChinese)
            }

            NavigationLink(destination: VoiceFineTuneView().environmentObject(store)) {
                Label("微调管理", systemImage: "slider.horizontal.3")
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

    // MARK: - 朗读

    private var playbackSection: some View {
        Section("朗读") {
            if !store.chapters.isEmpty {
                HStack {
                    Button("当前章节") { Task { await store.playSelectedChapter() } }
                    Spacer()
                    Button("全书") { Task { await store.playWholeBook() } }
                }
                Button("停止", role: .destructive) { store.stopPlayback() }
            }

            if store.playProgress > 0 {
                ProgressView(value: store.playProgress)
            }
        }
    }

    // MARK: - 导入

    private var importSection: some View {
        Section("导入") {
            TextEditor(text: Binding(
                get: { store.bookText },
                set: { _ in }
            ))
            .frame(minHeight: 120)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

            if store.importProgress > 0 {
                ProgressView(value: store.importProgress)
            }

            Button("导入文本") { Task { await store.importText(store.bookText) } }
            Button("扫描章节") { Task { await store.parseChaptersAsync() } }
            Button("识别角色") { Task { await store.scanCharacters() } }
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section("状态") {
            Text(store.statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct TTSView_Previews: PreviewProvider {
    static var previews: some View {
        TTSView().environmentObject(ReaderStore())
    }
}
