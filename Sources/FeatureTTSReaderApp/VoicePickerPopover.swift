import SwiftUI

/// 通用的音色选择弹出菜单（List 替代 Menu，突破 HStack 限制，支持 gender badge）
struct VoicePickerPopover: View {
    let availableVoices: [EdgeVoiceInfo]
    @Binding var selection: String
    let onSelect: ((String) -> Void)?

    var body: some View {
        List {
            Button {
                selection = ""
                onSelect?("")
            } label: {
                HStack {
                    Text("自动")
                    if selection.isEmpty { Image(systemName: "checkmark") }
                }
            }
            ForEach(availableVoices) { v in
                Button {
                    selection = v.id
                    onSelect?(v.id)
                } label: {
                    HStack {
                        Text(EdgeVoiceInfo.shortVoiceLabel(v.id, name: EdgeVoiceInfo.chineseVoiceName(for: v.id)))
                            .font(.subheadline)
                        Text(v.gender == "Male" ? "♂" : "♀")
                            .font(.caption2)
                            .foregroundColor(v.gender == "Male" ? .blue : .pink)
                        if selection == v.id { Spacer(); Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .frame(minWidth: 300, maxWidth: 400)
    }
}
