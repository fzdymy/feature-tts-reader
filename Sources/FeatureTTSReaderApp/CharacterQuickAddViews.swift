import SwiftUI

// MARK: - QuickCharacterAddView

struct QuickCharacterAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReaderStore
    let candidateName: String
    let bookText: String
    let existingCharacters: [CharacterProfile]
    let onAdd: (String, String, String, String) -> Void
    let onEdit: (CharacterProfile) -> Void

    @State private var gender: String
    @State private var age: String
    @State private var tone: String
    @State private var recommendedVoice: String

    init(candidateName: String, bookText: String, existingCharacters: [CharacterProfile],
         onAdd: @escaping (String, String, String, String) -> Void,
         onEdit: @escaping (CharacterProfile) -> Void) {
        self.candidateName = candidateName
        self.bookText = bookText
        self.existingCharacters = existingCharacters
        self.onAdd = onAdd
        self.onEdit = onEdit
        // Multi-paragraph global voting for attributes, not single truncated context.
        // Aggregates signals from ALL paragraphs containing the name, producing
        // more reliable gender/age/tone defaults. Falls to "未知"/"平稳" when weak.
        let analyzer = CharacterAnalyzer()
        let attrs = analyzer.estimateAttributes(for: candidateName, in: bookText)
        _gender = State(initialValue: attrs.gender)
        _age = State(initialValue: attrs.age)
        _tone = State(initialValue: attrs.baseTone)
        _recommendedVoice = State(initialValue: "")
    }

    private var existingMatch: CharacterProfile? {
        existingCharacters.first(where: { $0.name == candidateName })
    }

    private let genderOptions = ["未知", "男性", "女性"]
    private let ageOptions = ["未知", "少年", "少女", "青年", "中年", "年长"]
    private let toneOptions = ["平稳", "温柔", "激昂", "轻松", "疑问"]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("选中的文本")) {
                    Text("\"\(candidateName)\"").font(.headline)
                    if let match = existingMatch {
                        HStack {
                            Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                            Text("该角色已存在，可编辑现有角色").font(.caption).foregroundColor(.orange)
                        }
                    }
                }
                if existingMatch == nil {
                    Section(header: Text("自动分析结果")) {
                        HStack { Text("性别"); Spacer(); Text(gender).foregroundColor(.secondary) }
                        HStack { Text("年龄段"); Spacer(); Text(age).foregroundColor(.secondary) }
                        HStack { Text("语气"); Spacer(); Text(tone).foregroundColor(.secondary) }
                        if !recommendedVoice.isEmpty {
                            HStack { Text("推荐音色"); Spacer(); Text(recommendedVoice).foregroundColor(.blue) }
                        }
                    }
                    Section(header: Text("手动调整（可选）")) {
                        Picker("性别", selection: $gender) { ForEach(genderOptions, id: \.self) { Text($0).tag($0) } }
                        Picker("年龄段", selection: $age) { ForEach(ageOptions, id: \.self) { Text($0).tag($0) } }
                        Picker("语气", selection: $tone) { ForEach(toneOptions, id: \.self) { Text($0).tag($0) } }
                    }
                }
                if existingMatch != nil {
                    Section {
                        Button("编辑现有角色「\(existingMatch!.name)」") {
                            onEdit(existingMatch!)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingMatch != nil ? "角色已存在" : "添加新角色")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                if existingMatch == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            onAdd(candidateName, gender, age, tone)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AddCharacterView

struct AddCharacterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var gender = "未知"
    @State private var age = "未知"
    @State private var tone = "平稳"
    let onAdd: (String, String, String, String) -> Void
    private let genderOptions = ["未知", "男性", "女性"]
    private let ageOptions = ["未知", "少年", "少女", "青年", "中年", "年长"]
    private let toneOptions = ["平稳", "温柔", "激昂", "轻松", "疑问"]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("角色信息")) {
                    TextField("角色名称", text: $name)
                    Picker("性别", selection: $gender) { ForEach(genderOptions, id: \.self) { Text($0).tag($0) } }
                    Picker("年龄段", selection: $age) { ForEach(ageOptions, id: \.self) { Text($0).tag($0) } }
                    Picker("语气", selection: $tone) { ForEach(toneOptions, id: \.self) { Text($0).tag($0) } }
                }
            }
            .navigationTitle("新增角色")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onAdd(name.trimmingCharacters(in: .whitespaces), gender, age, tone)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
