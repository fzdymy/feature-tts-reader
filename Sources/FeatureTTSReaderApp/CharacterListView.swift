import SwiftUI

struct CharacterListView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCharacter: CharacterProfile?
    @State private var voices: [VoiceItem] = []

    var body: some View {
        NavigationStack {
            List {
                if store.characters.isEmpty {
                    Text("未识别到角色，请先导入小说并扫描角色。")
                        .foregroundColor(.secondary)
                } else {
                    Section(header: Text("角色与音色")) {
                        ForEach(store.characters) { character in
                            Button(action: { selectedCharacter = character }) {
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
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section(header: Text("角色扫描")) {
                        Button(action: {
                            if let chapter = store.chapters.first(where: { $0.id == store.selectedChapterID }) {
                                Task { await store.scanCharacters(chapterText: chapter.text) }
                            }
                        }) {
                            Label("扫描当前章节", systemImage: "doc.text")
                        }
                        Button(action: {
                            Task { await store.scanCharacters() }
                        }) {
                            Label("扫描全文", systemImage: "book.fill")
                        }
                    }

                    Section(header: Text("朗读脚本")) {
                        Button(action: {
                            Task { await store.buildScript(for: false) }
                        }) {
                            Label("生成朗读脚本（当前章节）", systemImage: "doc.richtext")
                        }
                        Button(action: {
                            Task { await store.buildScript(for: true) }
                        }) {
                            Label("生成朗读脚本（整本书）", systemImage: "book.fill")
                        }
                    }
                }
            }
            .navigationTitle("角色音色设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                voices = store.voices
                if store.characters.isEmpty || store.lastScannedBookText != store.bookText {
                    Task { await store.scanCharacters() }
                }
            }
            .sheet(item: $selectedCharacter) { character in
                CharacterEditorView(
                    character: character,
                    voices: voices
                ) { updated in
                    if let idx = store.characters.firstIndex(where: { $0.id == updated.id }) {
                        store.characters[idx] = updated
                        store.saveState()
                    }
                }
                .environmentObject(store)
            }
        }
    }
}
