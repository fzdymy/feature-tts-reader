import SwiftUI

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                catalogSection
                playbackSection
                statusSection
            }
            .navigationTitle("TTS")
        }
    }

    // MARK: - 服务器

    private var serverSection: some View {
        Section("TTS 服务器") {
            NavigationLink(destination: TTSServerListView().environmentObject(store)) {
                HStack {
                    Label("当前服务器", systemImage: "server.rack")
                    Spacer()
                    Text(store.activeServer?.name ?? "未配置")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 音色

    private var catalogSection: some View {
        Section("音色") {
            HStack(spacing: 12) {
                catalogButton(.chinese35)
                catalogButton(.fullChinese)
            }
            NavigationLink(destination: VoiceFineTuneView().environmentObject(store)) {
                Label("角色音色管理", systemImage: "slider.horizontal.3")
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

    // MARK: - 朗读控制

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

    // MARK: - 状态

    private var statusSection: some View {
        Section {
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
