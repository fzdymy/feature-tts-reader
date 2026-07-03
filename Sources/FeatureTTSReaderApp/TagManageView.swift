import SwiftUI

struct TagManageView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var newTagName: String = ""
    @State private var selectedCategory: TagCategory = .role

    var body: some View {
        List {
            Section {
                Picker("分类", selection: $selectedCategory) {
                    ForEach(TagCategory.allCases) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }

                HStack {
                    TextField("标签名", text: $newTagName)
                        .submitLabel(.done)
                        .onSubmit { addTag() }
                    Button("添加") { addTag() }
                        .buttonStyle(.borderless)
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("现有标签") {
                let tags = store.tagPresets.filter { $0.category == selectedCategory }
                if tags.isEmpty {
                    Text("该分类尚无标签").foregroundColor(.secondary)
                }
                ForEach(tags) { tag in
                    HStack {
                        Text(tag.name)
                        Spacer()
                        Text(selectedCategory.displayName)
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .onDelete { indexSet in
                    let filtered = store.tagPresets.filter { $0.category == selectedCategory }
                    for i in indexSet {
                        let tag = filtered[i]
                        store.tagPresets.removeAll { $0.id == tag.id }
                    }
                    saveTags()
                }
            }

            Section {
                Button("重置为默认标签", role: .destructive) {
                    store.tagPresets = defaultTagPresets()
                    saveTags()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("标签预设")
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tag = TagPreset(name: trimmed, category: selectedCategory)
        store.tagPresets.append(tag)
        saveTags()
        newTagName = ""
    }

    private func saveTags() {
        if let data = try? JSONEncoder().encode(store.tagPresets) {
            UserDefaults.standard.set(data, forKey: "tagPresets")
        }
    }

    private func defaultTagPresets() -> [TagPreset] {
        [
            TagPreset(name: "旁白", category: .role),
            TagPreset(name: "男主", category: .role),
            TagPreset(name: "女主", category: .role),
            TagPreset(name: "配角", category: .role),
            TagPreset(name: "反派", category: .role),
            TagPreset(name: "小孩", category: .age),
            TagPreset(name: "青年", category: .age),
            TagPreset(name: "中年", category: .age),
            TagPreset(name: "老年", category: .age),
            TagPreset(name: "开朗", category: .trait),
            TagPreset(name: "沉稳", category: .trait),
            TagPreset(name: "温柔", category: .trait),
            TagPreset(name: "凶狠", category: .trait),
            TagPreset(name: "主角", category: .roleType),
            TagPreset(name: "龙套", category: .roleType),
        ]
    }
}
