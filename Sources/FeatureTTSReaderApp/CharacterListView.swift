import SwiftUI

/// 角色列表页 — 可排序/搜索，旁白在首，其余按出现次数降序
/// 可在 ReaderView、BookDetailView 中复用
struct CharacterListView: View {
    @EnvironmentObject var store: ReaderStore
    let bookID: UUID?
    @Binding var characters: [CharacterProfile]
    let availableVoices: [EdgeVoiceInfo]
    let onDismiss: (() -> Void)?
    @Binding var resynthesizingSpeaker: String?
    @Binding var aiCacheAvailable: Bool

    @State private var searchText = ""
    @State private var showAddCharacter = false
    @State private var editingCharacter: CharacterProfile?

    private var sortedCharacters: [CharacterProfile] {
        let filtered = searchText.isEmpty ? characters : characters.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted { a, b in
            if a.isNarrator { return true }
            if b.isNarrator { return false }
            return a.appearanceCount > b.appearanceCount
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // AI 缓存指示器
                if aiCacheAvailable {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("AI 解析已缓存")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .listRowBackground(Color.green.opacity(0.05))
                }

                // 顶部操作
                Section {
                    HStack(spacing: 8) {
                        Button(action: { Task { await store.scanCharacters() } }) {
                            Label("扫描角色", systemImage: "person.badge.plus")
                                .font(.caption).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isBusy)

                        Button(action: { Task { await store.buildScript(for: false) } }) {
                            Label("生成脚本", systemImage: "doc.richtext")
                                .font(.caption).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isBusy)
                    }
                }

                // 旁白设置
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("旁白默认音色")
                                .font(.subheadline)
                            Text("首次朗读时立即用此音色启动播放")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        if !availableVoices.isEmpty {
                            let narratorVoice = UserDefaults.standard.string(forKey: "narratorVoice") ?? ""
                            let narratorLabel = narratorVoice.isEmpty
                                ? "自动选择"
                                : EdgeVoiceInfo.shortVoiceLabel(narratorVoice, name: EdgeVoiceInfo.chineseVoiceName(for: narratorVoice))
                            Button(narratorLabel) {
                                editingCharacter = characters.first(where: { $0.isNarrator })
                            }
                            .font(.caption)
                        }
                    }
                }

                // 角色列表
                Section {
                    if sortedCharacters.isEmpty {
                        Text("暂无角色，请先扫描或添加")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    ForEach(sortedCharacters) { character in
                        CharacterRow(character: character, availableVoices: availableVoices, resynthesizingSpeaker: $resynthesizingSpeaker) { updated in
                            if let idx = characters.firstIndex(where: { $0.id == updated.id }) {
                                characters[idx] = updated
                                store.saveState()
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets where i < sortedCharacters.count {
                            let c = sortedCharacters[i]
                            characters.removeAll { $0.id == c.id }
                            store.saveState()
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索角色")
            .navigationTitle("角色管理 (\(characters.count))")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if let onDismiss {
                        Button("完成") { onDismiss() }
                    }
                }
            }
            .sheet(item: $editingCharacter) { character in
                CharacterEditorView(character: character) { updated in
                    if let idx = characters.firstIndex(where: { $0.id == updated.id }) {
                        characters[idx] = updated
                        store.saveState()
                    }
                }
            }
        }
    }
}

// MARK: - CharacterRow

private struct CharacterRow: View {
    let character: CharacterProfile
    let availableVoices: [EdgeVoiceInfo]
    @Binding var resynthesizingSpeaker: String?
    let onUpdate: (CharacterProfile) -> Void

    @State private var showVoicePicker = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showVoiceChangeActionSheet = false
    @State private var pendingVoiceChange: (speaker: String, newVoice: String)?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(character.name)
                        .font(.subheadline.weight(.medium))
                    if character.isNarrator {
                        Text("旁白")
                            .font(.caption2).foregroundColor(.orange)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                    let genderIcon = character.gender == .male ? "♂" : (character.gender == .female ? "♀" : "")
                    if !genderIcon.isEmpty {
                        Text(genderIcon)
                            .font(.caption2)
                            .foregroundColor(character.gender == .male ? .blue : .pink)
                    }
                }
                Text(character.voiceID.isEmpty ? "未分配" : character.voiceID)
                    .font(.caption2).foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { showVoicePicker = true }) {
                Image(systemName: "music.note.list")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.blue)
            .popover(isPresented: $showVoicePicker) {
                if !availableVoices.isEmpty {
                    VoicePickerPopover(availableVoices: availableVoices,
                        selection: Binding(
                            get: { character.voiceID },
                            set: { newVoice in
                                guard newVoice != character.voiceID else { return }
                                pendingVoiceChange = (speaker: character.name, newVoice: newVoice)
                                showVoiceChangeActionSheet = true
                            }
                        ),
                        onSelect: nil
                    )
                }
            }
        }
        .contextMenu {
            Button("改名", systemImage: "pencil") {
                renameText = character.name
                showRenameAlert = true
            }
        }
        .alert("重命名角色", isPresented: $showRenameAlert) {
            TextField("新名称", text: $renameText)
            Button("取消", role: .cancel) { renameText = "" }
            Button("确定") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != character.name {
                    var c = character
                    c.name = trimmed
                    onUpdate(c)
                }
                renameText = ""
            }
        }
        .confirmationDialog("更换音色", isPresented: $showVoiceChangeActionSheet, titleVisibility: .visible) {
            Button("仅对后续段落生效") {
                if let change = pendingVoiceChange {
                    var c = character
                    c.voiceID = change.newVoice
                    onUpdate(c)
                }
            }
            Button("重新合成待播段", role: .destructive) {
                if let change = pendingVoiceChange {
                    var c = character
                    c.voiceID = change.newVoice
                    onUpdate(c)
                    resynthesizingSpeaker = change.speaker
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("更换「\(pendingVoiceChange?.speaker ?? "")」的音色后，如何处理已入队的音频？")
        }
    }
}
