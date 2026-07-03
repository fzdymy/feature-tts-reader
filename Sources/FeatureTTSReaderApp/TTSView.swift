import SwiftUI

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var selectedCharacter: CharacterProfile?
    @State private var useWholeBook: Bool = false

    private var selectedChapterTitle: String {
        store.chapters.first(where: { $0.id == store.selectedChapterID })?.title ?? "当前章节"
    }

    var body: some View {
        NavigationStack {
            List {
                // 服务器
                Section("TTS 服务器") {
                    NavigationLink(destination: TTSServerListView().environmentObject(store)) {
                        HStack {
                            Label("服务器管理", systemImage: "server.rack")
                            Spacer()
                            if let s = store.activeServer {
                                Text(s.name).foregroundColor(.secondary)
                            } else {
                                Text("未配置").foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 音色目录
                Section("音色") {
                    HStack(spacing: 12) {
                        catalogButton(.chinese35)
                        catalogButton(.fullChinese)
                    }
                    NavigationLink(destination: VoiceFineTuneView().environmentObject(store)) {
                        Label("角色音色微调", systemImage: "slider.horizontal.3")
                    }
                }

                // 章节与脚本
                chapterSection

                // 角色列表
                characterSection

                // 音色推荐
                recommendationSection

                // 可用音色
                voiceSection

                // 播放控制
                playbackSection

                // 状态
                Section {
                    Text(store.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("TTS")
            .sheet(item: $selectedCharacter) { character in
                CharacterEditorView(character: character, voices: store.voices.isEmpty ? VoiceItem.defaultItems() : store.voices) { updated in
                    if let index = store.characters.firstIndex(where: { $0.id == updated.id }) {
                        store.characters[index] = updated
                        store.saveState()
                    }
                }
            }
        }
    }

    // MARK: - 音色目录按钮

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

    // MARK: - 章节

    private var chapterSection: some View {
        Section("章节与脚本") {
            if store.chapters.isEmpty {
                Text("未发现章节，请先导入小说文本。")
                    .foregroundColor(.secondary)
            } else {
                Text("共计 \(store.chapters.count) 章")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                NavigationLink(destination: ChapterListView().environmentObject(store)) {
                    HStack {
                        Text(selectedChapterTitle)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                }
                Button(action: { Task { await store.buildScript(for: useWholeBook) } }) {
                    Label("生成朗读脚本", systemImage: "doc.richtext")
                }
                if !store.scriptSegments.isEmpty {
                    Text("脚本段落：\(store.scriptSegments.count) 条")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 角色

    private var characterSection: some View {
        Section("全局角色") {
            if store.characters.isEmpty {
                Text("暂无全局角色。可导入小说后扫描识别，或手动添加。")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.characters) { character in
                    HStack {
                        Button(action: { selectedCharacter = character }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(character.name).font(.headline)
                                Text(character.info).font(.caption).foregroundColor(.secondary)
                                Text("音色：\(character.voice) · 语速：\(character.rate) · 音调：\(character.pitch) · 风格：\(character.style)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        HStack(spacing: 8) {
                            Button(action: {
                                if let rec = store.recommendations.first(where: { $0.id == character.id }),
                                   let suggested = rec.suggestedVoices.first {
                                    store.applyVoice(suggested.id, toCharacterID: character.id)
                                }
                            }) {
                                Image(systemName: "wand.and.stars")
                            }
                            Button(action: { Task { await store.previewVoice(for: character) } }) {
                                Image(systemName: "play.circle")
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                    }
                }
            }
        }
    }

    // MARK: - 推荐

    private var recommendationSection: some View {
        Section("音色推荐") {
            if store.recommendations.isEmpty {
                Text("请先扫描角色并加载音色目录，即可查看推荐。")
                    .foregroundColor(.secondary)
            } else {
                HStack {
                    Button("应用到未映射角色") { store.applyRecommendationsToUnmapped() }
                    Spacer()
                    Button("全部应用") { store.autoApplyRecommendedToAll() }
                }
                .padding(.vertical, 4)
                ForEach(store.recommendations) { rec in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(rec.profile.name).font(.headline)
                            Spacer()
                            Text("出现：\(rec.count) 次").font(.caption).foregroundColor(.secondary)
                        }
                        Text("建议：\(rec.suggestedVoices.map(\.name).joined(separator: "，"))")
                            .font(.caption).foregroundColor(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(rec.suggestedVoices) { voice in
                                    Button(action: { store.applyVoice(voice.id, toCharacterID: rec.id) }) {
                                        Text(voice.name)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color.blue.opacity(0.12))
                                            .foregroundColor(.blue)
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - 音色列表

    private var voiceSection: some View {
        Section("可用音色（\(store.selectedVoiceCatalog.displayName)）") {
            if store.voices.isEmpty {
                Text("无可用音色。请先在音色目录中选择。")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.voices) { voice in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(voice.name).font(.headline)
                        Text(voice.id).font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - 播放控制

    private var playbackSection: some View {
        Section("朗读控制") {
            if !store.chapters.isEmpty {
                HStack {
                    Button(action: { Task { await store.playSelectedChapter() } }) {
                        Label("当前章节", systemImage: "play.fill")
                    }
                    Spacer()
                    Button(action: { Task { await store.playWholeBook() } }) {
                        Label("全书", systemImage: "book.fill")
                    }
                }
                Button(role: .destructive, action: store.stopPlayback) {
                    Label("停止", systemImage: "stop.fill")
                }
            }
            if !store.currentPlayingLine.isEmpty {
                Text("当前：\(store.currentPlayingLine)")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            if store.playProgress > 0 {
                ProgressView(value: store.playProgress)
            }
        }
    }
}

struct TTSView_Previews: PreviewProvider {
    static var previews: some View {
        TTSView().environmentObject(ReaderStore())
    }
}
