import SwiftUI
import UniformTypeIdentifiers

struct VoiceFineTuneView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var showAddSheet = false
    @State private var editingProfile: VoiceProfileTuning?

    var body: some View {
        List {
            if store.voiceProfiles.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text("尚无微调音色")
                            .foregroundColor(.secondary)
                        Text("选择一个基准音色并调整语速/音调/风格来创建新的音色变体。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }

            Section(header: Text("已创建的微调音色")) {
                ForEach(store.voiceProfiles) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(profile.alias.isEmpty ? profile.sourceVoiceID : profile.alias)
                                .font(.headline)
                            Spacer()
                            if !profile.tags.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(profile.tags.prefix(3), id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .cornerRadius(4)
                                    }
                                    if profile.tags.count > 3 {
                                        Text("+\(profile.tags.count - 3)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        Text("源自: \(profile.sourceVoiceID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("语速\(profile.rateOffset) · 音调\(profile.pitchOffset) · 风格\(profile.style)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) {
                            store.removeVoiceProfile(profile.id)
                        }
                    }
                    .onTapGesture {
                        editingProfile = profile
                    }
                }
            }

            Section {
                Button(action: { showAddSheet = true }) {
                    Label("创建微调音色", systemImage: "plus.circle")
                }
            }

            if !store.voiceProfiles.isEmpty {
                Section(header: Text("导出/导入")) {
                    Button(action: exportProfile) {
                        Label("导出音色方案", systemImage: "square.and.arrow.up")
                    }
                    Button(action: importProfile) {
                        Label("导入音色方案", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("音色微调")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            VoiceFineTuneEditView(profile: nil) { newProfile in
                store.addVoiceProfile(newProfile)
            }
        }
        .sheet(item: $editingProfile) { profile in
            VoiceFineTuneEditView(profile: profile) { updated in
                store.updateVoiceProfile(updated)
            }
        }
        .fileExporter(isPresented: $showExporter, document: JSONDocument(data: exportData), contentType: .json, defaultFilename: "tts-voice-profiles") { result in
            switch result {
            case .success: store.statusMessage = "音色方案已导出"
            case .failure(let e): store.statusMessage = "导出失败: \(e.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                if store.importVoiceProfiles(from: data) {
                    store.statusMessage = "音色方案已导入"
                } else {
                    store.statusMessage = "导入失败: 格式错误"
                }
            case .failure(let e):
                store.statusMessage = "导入失败: \(e.localizedDescription)"
            }
        }
    }

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportData = Data()

    private func exportProfile() {
        guard let data = store.exportVoiceProfiles() else {
            store.statusMessage = "导出失败: 无数据"
            return
        }
        exportData = data
        showExporter = true
    }

    private func importProfile() {
        showImporter = true
    }
}

// MARK: - 微调编辑

struct VoiceFineTuneEditView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let profile: VoiceProfileTuning?
    let onSave: (VoiceProfileTuning) -> Void

    @State private var sourceVoiceID: String = ""
    @State private var alias: String = ""
    @State private var tagInput: String = ""
    @State private var tags: [String] = []
    @State private var rateOffset: Int = 0
    @State private var pitchOffset: Int = 0
    @State private var style: String = "neutral"

    private let styleOptions = ["neutral", "cheerful", "sad", "angry", "gentle", "serious"]

    private let isEditing: Bool

    init(profile: VoiceProfileTuning?, onSave: @escaping (VoiceProfileTuning) -> Void) {
        self.profile = profile
        self.onSave = onSave
        self.isEditing = profile != nil
        _sourceVoiceID = State(initialValue: profile?.sourceVoiceID ?? "")
        _alias = State(initialValue: profile?.alias ?? "")
        _tags = State(initialValue: profile?.tags ?? [])
        _rateOffset = State(initialValue: profile?.rateOffset ?? 0)
        _pitchOffset = State(initialValue: profile?.pitchOffset ?? 0)
        _style = State(initialValue: profile?.style ?? "neutral")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基准音色")) {
                    if isEditing {
                        Text(sourceVoiceID)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("选择音色", selection: $sourceVoiceID) {
                            ForEach(store.voices) { voice in
                                Text(voice.name).tag(voice.id)
                            }
                        }
                    }
                }

                Section(header: Text("别名与标签")) {
                    TextField("别名（如：二号男主）", text: $alias)
                    HStack {
                        TextField("添加标签", text: $tagInput)
                            .submitLabel(.done)
                            .onSubmit { addTag() }
                        Button("添加") { addTag() }
                            .buttonStyle(.borderless)
                            .disabled(tagInput.isEmpty)
                    }
                    if !tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                        .font(.caption)
                                    Button(action: { tags.removeAll { $0 == tag } }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(8)
                            }
                        }
                    }
                }

                Section(header: Text("微调参数")) {
                    HStack {
                        Text("语速偏移")
                        Slider(value: Binding(get: { Double(rateOffset) }, set: { rateOffset = Int($0) }), in: -100...100, step: 5)
                        Text("\(rateOffset)")
                            .frame(width: 40)
                    }
                    HStack {
                        Text("音调偏移")
                        Slider(value: Binding(get: { Double(pitchOffset) }, set: { pitchOffset = Int($0) }), in: -100...100, step: 5)
                        Text("\(pitchOffset)")
                            .frame(width: 40)
                    }
                    Picker("风格", selection: $style) {
                        ForEach(styleOptions, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑微调" : "新建微调")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let newProfile = VoiceProfileTuning(
                            id: profile?.id ?? UUID(),
                            sourceVoiceID: sourceVoiceID,
                            alias: alias,
                            tags: tags,
                            rateOffset: rateOffset,
                            pitchOffset: pitchOffset,
                            style: style
                        )
                        onSave(newProfile)
                        dismiss()
                    }
                    .disabled(sourceVoiceID.isEmpty)
                }
            }
        }
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        tagInput = ""
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        for s in sizes {
            if currentX + s.width > (proposal.width ?? 300) {
                height += currentRowHeight + spacing
                currentX = 0
                currentRowHeight = 0
            }
            currentX += s.width + spacing
            currentRowHeight = max(currentRowHeight, s.height)
        }
        height += currentRowHeight
        return CGSize(width: proposal.width ?? 300, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        var currentX = bounds.minX
        var currentRowHeight: CGFloat = 0
        for (i, s) in zip(subviews, sizes) {
            if currentX + s.width > bounds.maxX {
                y += currentRowHeight + spacing
                currentX = bounds.minX
                currentRowHeight = 0
            }
            i.place(at: CGPoint(x: currentX, y: y), proposal: .unspecified)
            currentX += s.width + spacing
            currentRowHeight = max(currentRowHeight, s.height)
        }
    }
}

// MARK: - JSON Document for file export

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file?.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
