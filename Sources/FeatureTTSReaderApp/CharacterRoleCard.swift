import SwiftUI

/// 角色卡片 — 音色选择、别名、合并/分离/改名/删除
struct CharacterRoleCard: View {
    let speaker: String
    let aliases: [String]
    let segmentCount: Int
    let emotionSummary: String?
    let gender: Gender
    let autoMatchedVoiceID: String
    @Binding var voiceSelection: String
    let availableVoices: [EdgeVoiceInfo]
    let onResynthesize: (() -> Void)?
    let onMerge: ((String) -> Void)?
    let onSplit: ((String) -> Void)?
    let onDelete: (() -> Void)?
    let onRename: ((String) -> Void)?
    let otherSpeakers: [String]
    let showVoicePicker: Bool

    @State private var showVoicePickerPopover = false
    @State private var showMergePicker = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var isResynthesizing = false

    init(
        speaker: String,
        aliases: [String] = [],
        segmentCount: Int = 0,
        emotionSummary: String? = nil,
        gender: Gender = .unknown,
        autoMatchedVoiceID: String = "",
        voiceSelection: Binding<String>,
        availableVoices: [EdgeVoiceInfo] = [],
        onResynthesize: (() -> Void)? = nil,
        onMerge: ((String) -> Void)? = nil,
        onSplit: ((String) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onRename: ((String) -> Void)? = nil,
        otherSpeakers: [String] = [],
        showVoicePicker: Bool = true
    ) {
        self.speaker = speaker
        self.aliases = aliases
        self.segmentCount = segmentCount
        self.emotionSummary = emotionSummary
        self.gender = gender
        self.autoMatchedVoiceID = autoMatchedVoiceID
        self._voiceSelection = voiceSelection
        self.availableVoices = availableVoices
        self.onResynthesize = onResynthesize
        self.onMerge = onMerge
        self.onSplit = onSplit
        self.onDelete = onDelete
        self.onRename = onRename
        self.otherSpeakers = otherSpeakers
        self.showVoicePicker = showVoicePicker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 角色名 + 性别 + 段数
            HStack {
                HStack(spacing: 6) {
                    Text(speaker)
                        .font(.subheadline.weight(.medium))
                    genderBadge
                    if speaker == "旁白" {
                        Text("旁白")
                            .font(.caption2).foregroundColor(.orange)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                Spacer()
                Text("\(segmentCount) 段")
                    .font(.caption2).foregroundColor(.secondary)
                Menu {
                    Button("改名", systemImage: "pencil") { showRenameAlert = true }
                    if !aliases.isEmpty, let onSplit {
                        ForEach(aliases, id: \.self) { alias in
                            Button("分离「\(alias)」", systemImage: "arrow.triangle.branch") { onSplit(alias) }
                        }
                    }
                    if !otherSpeakers.isEmpty, let onMerge {
                        Button("合并到...", systemImage: "arrow.triangle.merge") { showMergePicker = true }
                    }
                    if let onDelete {
                        Button("删除角色", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // 情绪摘要
            if let emotionSummary, !emotionSummary.isEmpty {
                Text(emotionSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // 音色选择
            if showVoicePicker {
                HStack(spacing: 8) {
                    Button {
                        showVoicePickerPopover = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2")
                                .font(.caption2)
                            let label = selectedVoiceLabel
                            Text(label)
                                .font(.caption)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showVoicePickerPopover) {
                        VoicePickerPopover(availableVoices: availableVoices, selection: $voiceSelection) { _ in
                            showVoicePickerPopover = false
                        }
                    }

                    if let onResynthesize {
                        Button {
                            isResynthesizing = true
                            onResynthesize()
                        } label: {
                            HStack(spacing: 2) {
                                if isResynthesizing {
                                    ProgressView().scaleEffect(0.6)
                                }
                                Text("重合成")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                    }
                }
            }

            // 别名显示
            if !aliases.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(aliases.joined(separator: "、"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(uiColor: .systemGray6).opacity(0.5))
        .cornerRadius(10)

        .alert("重命名角色", isPresented: $showRenameAlert) {
            TextField("新名称", text: $renameText)
            Button("取消", role: .cancel) { renameText = "" }
            Button("确定") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { onRename?(trimmed) }
                renameText = ""
            }
        } message: {
            Text("将重命名「\(speaker)」及其所有片段")
        }

        .confirmationDialog("合并角色", isPresented: $showMergePicker) {
            ForEach(otherSpeakers, id: \.self) { target in
                Button("合并到「\(target)」") { onMerge?(target) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将「\(speaker)」合并到目标角色，合并后 source 成为别名")
        }

        .confirmationDialog("删除角色", isPresented: $showDeleteConfirm) {
            Button("删除「\(speaker)」", role: .destructive) { onDelete?() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 \(segmentCount) 个相关片段，不可撤销。")
        }
    }

    private var genderBadge: some View {
        Group {
            switch gender {
            case .male:
                Text("♂").font(.caption2).foregroundColor(.blue)
            case .female:
                Text("♀").font(.caption2).foregroundColor(.pink)
            case .unknown:
                EmptyView()
            }
        }
    }

    private var selectedVoiceLabel: String {
        guard !voiceSelection.isEmpty else {
            return "自动 - \(EdgeVoiceInfo.shortVoiceLabel(autoMatchedVoiceID, name: EdgeVoiceInfo.chineseVoiceName(for: autoMatchedVoiceID)))"
        }
        let base = EdgeVoiceInfo.shortVoiceLabel(voiceSelection, name: EdgeVoiceInfo.chineseVoiceName(for: voiceSelection))
        let g = availableVoices.first(where: { $0.id == voiceSelection })?.gender ?? ""
        let icon = g == "Male" ? " ♂" : (g == "Female" ? " ♀" : "")
        return base + icon
    }
}
