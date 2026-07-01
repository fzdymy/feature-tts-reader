import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var rawText: String = ""
    @State private var selectedCharacter: CharacterProfile?
    @State private var useWholeBook: Bool = false

    private var selectedChapterTitle: String {
        store.chapters.first(where: { $0.id == store.selectedChapterID })?.title ?? "当前章节"
    }

    var body: some View {
        NavigationStack {
            List {
                homeEntrySection
                settingsSection
                importSection
                chapterSection
                quickNavigationSection
                characterSection
                recommendationSection
                actionSection
                voiceSection
                statusSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("多角色小说朗读")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: BookshelfView().environmentObject(store)) {
                        Image(systemName: "books.vertical")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { useWholeBook.toggle() }) {
                        Text(useWholeBook ? "全书模式" : "章节模式")
                    }
                    NavigationLink(destination: SettingsView().environmentObject(store)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(UIColor.systemBackground), for: .navigationBar)
            .onAppear {
                rawText = store.bookText
            }
            .onChange(of: store.bookText) { newBookText in
                rawText = newBookText
            }
            .sheet(item: $selectedCharacter) { character in
                CharacterEditorView(character: character, voices: store.voices.isEmpty ? VoiceItem.defaultItems() : store.voices) { updated in
                    if let index = store.characters.firstIndex(where: { $0.id == updated.id }) {
                        store.characters[index] = updated
                        store.updateRecommendations()
                        store.saveState()
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        Section(header: Text("全局参数与 TTS 设置")) {
            TextField("TTS 服务地址，例如 https://example.com/tts", text: $store.apiEndpoint)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .submitLabel(.done)
            SecureField("API Key（选填）", text: $store.apiKey)
                .textContentType(.password)
                .submitLabel(.done)
            HStack(spacing: 12) {
                Button(action: {
                    store.switchCatalog(to: .chinese35)
                }) {
                    Text("经典音色 (40)")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(store.selectedVoiceCatalog == .chinese35 ? Color.accentColor : Color.gray.opacity(0.15))
                        .foregroundColor(store.selectedVoiceCatalog == .chinese35 ? .white : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.borderless)
                Button(action: {
                    store.switchCatalog(to: .fullChinese)
                }) {
                    Text("全音色 (76)")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(store.selectedVoiceCatalog == .fullChinese ? Color.accentColor : Color.gray.opacity(0.15))
                        .foregroundColor(store.selectedVoiceCatalog == .fullChinese ? .white : .primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.borderless)
            }
            Text("经典音色涵盖 40 种常用中文音色；全音色含 76 种音色（含 Dragon HD / MAI 等）")
                        .font(.caption)
                        .foregroundColor(.secondary)
            Button(action: store.saveSettings) {
                Text("保存设置")
            }
        }
    }

    private var homeEntrySection: some View {
        Section(header: Text("快速入口")) {
            NavigationLink(destination: BookshelfView().environmentObject(store)) {
                Label("进入书架", systemImage: "books.vertical")
            }
            NavigationLink(destination: ChapterListView().environmentObject(store)) {
                Label("查看章节目录", systemImage: "list.bullet")
            }
            HStack {
                Button(action: { Task { await store.playSelectedChapter() } }) {
                    Label("播放当前章节", systemImage: "play.fill")
                }
                Spacer()
                Button(action: { Task { await store.playWholeBook() } }) {
                    Label("播放整本小说", systemImage: "book.fill")
                }
            }
        }
    }

    private var importSection: some View {
        Section(header: Text("小说导入与扫描")) {
            TextEditor(text: $rawText)
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
            if store.importProgress > 0 {
                ProgressView(value: store.importProgress)
                    .padding(.vertical, 4)
            }
            HStack {
                Button(action: { Task { await store.importText(rawText); rawText = store.bookText } }) {
                    Text("导入文本")
                }
                Spacer()
                Button(action: { Task { await store.parseChaptersAsync() } }) {
                    Text("扫描章节")
                }
                Spacer()
                Button(action: { Task { await store.scanCharacters() } }) {
                    Text("识别角色")
                }
            }
        }
    }

    private var chapterSection: some View {
        Section(header: Text("章节与脚本")) {
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
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
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

    private var characterSection: some View {
        Section(header: Text("角色与音色")) {
            if store.characters.isEmpty {
                Text("未识别到角色，请先导入小说并扫描角色。")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.characters) { character in
                    HStack {
                        Button(action: { selectedCharacter = character }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(character.name)
                                        .font(.headline)
                                    Text(character.info)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("音色：\(character.voice) · 语速：\(character.rate) · 音调：\(character.pitch) · 风格：\(character.style)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                        HStack(spacing: 8) {
                            Button(action: {
                                // quick apply first recommended voice for this character
                                if let rec = store.recommendations.first(where: { $0.id == character.id }), let suggested = rec.suggestedVoices.first {
                                    store.applyVoice(suggested.id, toCharacterID: character.id)
                                }
                            }) {
                                Image(systemName: "wand.and.stars")
                            }
                            Button(action: { Task { await store.previewVoice(for: character) } }) {
                                Image(systemName: "play.circle")
                            }
                            Button(action: {
                                if let idx = store.characters.firstIndex(where: { $0.id == character.id }) {
                                    store.characters[idx].sensitivity = store.defaultSensitivity
                                    store.saveState()
                                }
                            }) {
                                Image(systemName: "slider.horizontal.3")
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .foregroundColor(.blue)
                    }
                }
            }
        }
    }

    private var actionSection: some View {
        Section(header: Text("朗读控制")) {
            HStack {
                Button(action: { Task { await store.playSelectedChapter() } }) {
                    Label("播放当前章节", systemImage: "play.fill")
                }
                Spacer()
                Button(action: { Task { await store.playWholeBook() } }) {
                    Label("播放整本小说", systemImage: "book.fill")
                }
            }
            Button(action: store.stopPlayback) {
                Label("停止播放", systemImage: "stop.fill")
            }
            if !store.currentPlayingLine.isEmpty {
                Text("当前角色：\(store.currentPlayingLine)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: store.playProgress)
                .opacity(store.playProgress > 0 ? 1 : 0)
        }
    }

    private var recommendationSection: some View {
        Section(header: Text("角色音色推荐")) {
            if store.recommendations.isEmpty {
                Text("请先识别角色并刷新语音列表，即可查看推荐音色。")
                    .foregroundColor(.secondary)
            } else {
                HStack {
                    Button(action: { store.applyRecommendationsToUnmapped() }) {
                        Text("应用到未映射角色")
                    }
                    Spacer()
                    Button(action: { store.autoApplyRecommendedToAll() }) {
                        Text("全部应用")
                    }
                }
                .padding(.vertical, 4)
                ForEach(store.recommendations) { rec in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(rec.profile.name)
                                .font(.headline)
                            Spacer()
                            Text("出现次数：\(rec.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("建议音色：\(rec.suggestedVoices.map { $0.name }.joined(separator: "，"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

    private var voiceSection: some View {
        Section(header: Text("可用音色")) {
            Text("音色来源：\(store.selectedVoiceCatalog.displayName)")
                .font(.caption)
                .foregroundColor(.secondary)
            if store.voices.isEmpty {
                Text("请刷新语音列表以加载本地 TTS 服务支持的音色。")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.voices) { voice in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(voice.name)
                            .font(.headline)
                        Text(voice.id)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var quickNavigationSection: some View {
        Section(header: Text("快速导航")) {
            NavigationLink(destination: ChapterListView().environmentObject(store)) {
                Label("章节目录", systemImage: "list.bullet")
            }
            NavigationLink(destination: SettingsView().environmentObject(store)) {
                Label("设置", systemImage: "gearshape")
            }
        }
    }

    private var statusSection: some View {
        Section(header: Text("状态与提示")) {
            Text(store.statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ReaderStore())
    }
}
