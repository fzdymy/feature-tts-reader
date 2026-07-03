import SwiftUI
import UniformTypeIdentifiers

struct TemplateManageView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var showAddSheet = false
    @State private var editingTemplate: RoleTemplate?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportData = Data()

    var body: some View {
        List {
            if store.roleTemplates.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text("尚无推荐模板").foregroundColor(.secondary)
                        Text("按小说类型预设角色阵容，朗读时将自动推荐匹配的音色。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            }

            ForEach(store.roleTemplates) { template in
                Section {
                    Button(action: { editingTemplate = template }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(template.name).font(.headline)
                            if template.roles.isEmpty {
                                Text("无角色配置").font(.caption).foregroundColor(.secondary)
                            } else {
                                ForEach(template.roles) { role in
                                    HStack {
                                        Text(role.title).font(.subheadline)
                                        Spacer()
                                        Text(role.voiceSuggestion)
                                            .font(.caption).foregroundColor(.secondary)
                                        if role.rateOffset != 0 || role.pitchOffset != 0 {
                                            Text("语\(role.rateOffset) 调\(role.pitchOffset)")
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundColor(.primary)
                    .contextMenu {
                        Button(action: {
                            store.applyTemplate(template)
                        }) {
                            Label("应用模板", systemImage: "checkmark.circle")
                        }
                        Button(action: { editingTemplate = template }) {
                            Label("编辑", systemImage: "pencil")
                        }
                    }
                }
            }
            .onDelete { indexSet in
                for i in indexSet {
                    store.deleteRoleTemplate(store.roleTemplates[i].id)
                }
            }

            Section {
                Button(action: { showAddSheet = true }) {
                    Label("新建模板", systemImage: "plus.circle")
                }
            }

            if !store.roleTemplates.isEmpty {
                Section("导入/导出") {
                    Button(action: exportTemplates) {
                        Label("导出模板 (JSON)", systemImage: "square.and.arrow.up")
                    }
                    Button(action: { showImporter = true }) {
                        Label("导入模板 (JSON)", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("推荐模板")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            TemplateEditView(template: nil) { t in
                store.addRoleTemplate(t)
            }
            .environmentObject(store)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditView(template: template) { t in
                store.updateRoleTemplate(t)
            }
            .environmentObject(store)
        }
        .fileExporter(isPresented: $showExporter, document: JSONDocument(data: exportData),
                      contentType: .json, defaultFilename: "tts-role-templates") { result in
            switch result {
            case .success: store.statusMessage = "模板已导出"
            case .failure(let e): store.statusMessage = "导出失败: \(e.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                let succeeded = store.importRoleTemplates(from: data)
                if !succeeded && store.statusMessage.isEmpty {
                    store.statusMessage = "导入失败: 格式错误"
                }
            case .failure(let e):
                store.statusMessage = "导入失败: \(e.localizedDescription)"
            }
        }
    }

    private func exportTemplates() {
        guard let data = store.exportRoleTemplates() else {
            store.statusMessage = "导出失败: 无数据"
            return
        }
        exportData = data
        showExporter = true
    }
}

// MARK: - 模板编辑

struct TemplateEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReaderStore
    let template: RoleTemplate?
    let onSave: (RoleTemplate) -> Void

    @State private var name: String = ""
    @State private var roles: [TemplateRole] = []
    @State private var fallbackMaleVoiceID: String = ""
    @State private var fallbackFemaleVoiceID: String = ""
    @State private var fallbackRateOffset: Int = 0
    @State private var fallbackPitchOffset: Int = 0
    @State private var fallbackStyle: String = "neutral"

    private let isEditing: Bool

    init(template: RoleTemplate?, onSave: @escaping (RoleTemplate) -> Void) {
        self.template = template
        self.onSave = onSave
        self.isEditing = template != nil
        _name = State(initialValue: template?.name ?? "")
        _roles = State(initialValue: template?.roles ?? [])
        _fallbackMaleVoiceID = State(initialValue: template?.fallbackMaleVoiceID ?? "")
        _fallbackFemaleVoiceID = State(initialValue: template?.fallbackFemaleVoiceID ?? "")
        _fallbackRateOffset = State(initialValue: template?.fallbackRateOffset ?? 0)
        _fallbackPitchOffset = State(initialValue: template?.fallbackPitchOffset ?? 0)
        _fallbackStyle = State(initialValue: template?.fallbackStyle ?? "neutral")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("模板名称")) {
                    TextField("如：男频小说、历史穿越", text: $name)
                }

                Section(header: Text("未匹配角色容灾")) {
                    Picker("男性默认音色", selection: $fallbackMaleVoiceID) {
                        Text("不指定（使用系统默认）").tag("")
                        ForEach(store.voices) { voice in
                            Text("\(voice.name) (\(voice.gender.displayName))").tag(voice.id)
                        }
                    }
                    Picker("女性默认音色", selection: $fallbackFemaleVoiceID) {
                        Text("不指定（使用系统默认）").tag("")
                        ForEach(store.voices) { voice in
                            Text("\(voice.name) (\(voice.gender.displayName))").tag(voice.id)
                        }
                    }
                    HStack {
                        Stepper("容灾语速: \(fallbackRateOffset)", value: $fallbackRateOffset, in: -100...100, step: 5)
                    }
                    HStack {
                        Stepper("容灾音调: \(fallbackPitchOffset)", value: $fallbackPitchOffset, in: -100...100, step: 5)
                    }
                    Picker("容灾风格", selection: $fallbackStyle) {
                        Text("neutral").tag("neutral")
                        Text("cheerful").tag("cheerful")
                        Text("sad").tag("sad")
                        Text("angry").tag("angry")
                        Text("gentle").tag("gentle")
                        Text("serious").tag("serious")
                    }
                }

                Section(header: Text("角色阵容")) {
                    if roles.isEmpty {
                        Text("尚未添加角色").foregroundColor(.secondary)
                    }
                    ForEach($roles) { $role in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField("角色名", text: $role.title)
                                    .font(.subheadline)
                            }
                            Picker("音色", selection: $role.sourceVoiceID) {
                                Text("未选择").tag("")
                                ForEach(store.voices) { voice in
                                    Text("\(voice.name) (\(voice.gender.displayName))").tag(voice.id)
                                }
                            }
                            .font(.caption)
                            TextField("音色备注（如：沉稳男声·青年）", text: $role.voiceSuggestion)
                                .font(.caption)
                            HStack(spacing: 12) {
                                Stepper("语速: \(role.rateOffset)", value: $role.rateOffset, in: -100...100, step: 5)
                                Stepper("音调: \(role.pitchOffset)", value: $role.pitchOffset, in: -100...100, step: 5)
                            }
                            .font(.caption2)
                            Picker("风格", selection: $role.style) {
                                Text("neutral").tag("neutral")
                                Text("cheerful").tag("cheerful")
                                Text("sad").tag("sad")
                                Text("angry").tag("angry")
                                Text("gentle").tag("gentle")
                                Text("serious").tag("serious")
                            }
                            .font(.caption2)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { roles.remove(atOffsets: $0) }

                    Button(action: {
                        roles.append(TemplateRole(title: ""))
                    }) {
                        Label("添加角色", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑模板" : "新建模板")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let t = RoleTemplate(
                            id: template?.id ?? UUID(),
                            name: name,
                            roles: roles.filter { !$0.title.isEmpty },
                            fallbackMaleVoiceID: fallbackMaleVoiceID,
                            fallbackFemaleVoiceID: fallbackFemaleVoiceID,
                            fallbackRateOffset: fallbackRateOffset,
                            fallbackPitchOffset: fallbackPitchOffset,
                            fallbackStyle: fallbackStyle
                        )
                        onSave(t)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
