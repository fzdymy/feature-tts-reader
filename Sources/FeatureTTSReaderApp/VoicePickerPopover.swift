import SwiftUI
import AVFoundation

/// 通用的音色选择弹出菜单（List 替代 Menu，支持搜索、试听、分组、性别标签）
struct VoicePickerPopover: View {
    let availableVoices: [EdgeVoiceInfo]
    @Binding var selection: String
    let onSelect: ((String) -> Void)?

    @State private var searchText: String = ""
    @State private var selectedPreviewVoice: String? = nil
    @State private var previewPlayer: AVAudioPlayer? = nil

    enum GroupMode: String, CaseIterable {
        case locale = "按语言"
        case gender = "按性别"
    }
    @State private var groupMode: GroupMode = .locale

    private var filteredVoices: [EdgeVoiceInfo] {
        let base = availableVoices
        if searchText.isEmpty { return base }
        return base.filter {
            $0.id.localizedCaseInsensitiveContains(searchText) ||
            EdgeVoiceInfo.chineseVoiceName(for: $0.id).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedVoices: [(key: String, value: [EdgeVoiceInfo])] {
        let dict = Dictionary(grouping: filteredVoices) { voice in
            switch groupMode {
            case .locale: return voice.locale
            case .gender: return voice.gender
            }
        }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search & Group controls
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索音色...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                Picker("分组", selection: $groupMode) {
                    ForEach(GroupMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()

            // Voice list
            List {
                // Auto option
                Section {
                    Button {
                        selection = ""
                        onSelect?("")
                    } label: {
                        HStack {
                            Text("自动")
                            if selection.isEmpty { Image(systemName: "checkmark") }
                        }
                    }
                }

                ForEach(groupedVoices, id: \.key) { groupKey, voices in
                    Section(header: Text(groupKey).font(.caption).foregroundColor(.secondary)) {
                        ForEach(voices) { v in
                            voiceRow(v)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(minWidth: 320, maxWidth: 420, maxHeight: 500)
        }
    }

    @ViewBuilder
    private func voiceRow(_ voice: EdgeVoiceInfo) -> some View {
        let chineseName = EdgeVoiceInfo.chineseVoiceName(for: voice.id)
        let label = EdgeVoiceInfo.shortVoiceLabel(voice.id, name: chineseName)
        let isSelected = selection == voice.id
        let isPreviewing = selectedPreviewVoice == voice.id

        HStack {
            Button {
                selection = voice.id
                onSelect?(voice.id)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.subheadline)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(voice.locale)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(voice.gender == "Male" ? "♂" : "♀")
                                .font(.caption2)
                                .foregroundColor(voice.gender == "Male" ? .blue : .pink)
                        }
                    }
                    Spacer()
                    if isSelected { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                }
            }
            .buttonStyle(.plain)

            // Preview button
            Button {
                if selectedPreviewVoice == voice.id {
                    stopPreview()
                } else {
                    playPreview(voice)
                }
            } label: {
                Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isPreviewing ? .red : .accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func playPreview(_ voice: EdgeVoiceInfo) {
        stopPreview()
        selectedPreviewVoice = voice.id

        Task {
            do {
                let text = "你好，我是\(EdgeVoiceInfo.chineseVoiceName(for: voice.id))。"
                let data = try await EdgeTTSService.shared.synthesize(text: text, voice: voice.id)
                if let player = try? AVAudioPlayer(data: data) {
                    await MainActor.run {
                        previewPlayer = player
                        previewPlayer?.prepareToPlay()
                        previewPlayer?.play()
                    }
                }
            } catch {
                print("Preview failed: \(error)")
            }
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        selectedPreviewVoice = nil
    }
}