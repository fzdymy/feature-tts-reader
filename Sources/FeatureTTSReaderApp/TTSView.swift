import SwiftUI

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore

    // MARK: - Server State
    @State private var serverConfigs: [EdgeTTSServerConfig] = []
    @State private var selectedServerID: UUID? {
        didSet {
            if let id = selectedServerID {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedTSServerID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedTSServerID")
            }
        }
    }
    @State private var serverStatuses: [UUID: String] = [:]
    @State private var isTestingAll = false

    // MARK: - Test State
    @State private var testText = "你好，欢迎使用语音合成。这是一个测试。"
    @State private var testResult = ""
    @State private var isTestingSynthesis = false
    @State private var availableVoices: [EdgeVoiceInfo] = []
    @State private var testVoice = ""
    @State private var testStyle = ""
    @State private var testRate: Double = 0
    @State private var testPitch: Double = 0
    @State private var showPreview = false

    // MARK: - Sheet State
    @State private var showAddSheet = false
    @State private var editingServer: EdgeTTSServerConfig?

    private var currentVoiceStyles: [String] {
        guard let v = availableVoices.first(where: { $0.id == testVoice }), let styles = v.styles else { return [] }
        return styles
    }

    var body: some View {
        NavigationStack {
            List {
                serverSection
                if selectedServerID != nil {
                    testSection
                }
                statusSection
            }
            .navigationTitle("语音引擎")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                ServerEditView { config in
                    var newConfig = config
                    if newConfig.name == "默认" || newConfig.name.isEmpty {
                        newConfig.name = "服务器 \(serverConfigs.count + 1)"
                    }
                    serverConfigs.append(newConfig)
                    selectedServerID = newConfig.id
                    serverStatuses[newConfig.id] = "未测试"
                    saveServers()
                }
            }
            .sheet(item: $editingServer) { config in
                ServerEditView(config: config) { updated in
                    if let idx = serverConfigs.firstIndex(where: { $0.id == config.id }) {
                        serverConfigs[idx] = updated
                        serverStatuses[updated.id] = "未测试"
                        saveServers()
                    }
                }
            }
            .task {
                await loadServers()
            }
            .task(id: selectedServerID) {
                await loadVoices()
            }
        }
    }

    // MARK: - Server Section

    private var serverSection: some View {
        Section {
            ForEach(serverConfigs) { config in
                HStack(spacing: 10) {
                    statusDot(serverStatuses[config.id] ?? "未测试")
                        .frame(width: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.name.isEmpty ? "未命名" : config.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(config.url.isEmpty ? "未配置地址" : config.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if config.id == selectedServerID {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.subheadline)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedServerID = config.id
                }
                .contextMenu {
                    Button { editingServer = config } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    if serverConfigs.count > 1 {
                        Divider()
                        Button(role: .destructive) {
                            deleteServer(config)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .onDelete { indexSet in
                guard serverConfigs.count > 1 else { return }
                for i in indexSet {
                    let id = serverConfigs[i].id
                    if selectedServerID == id {
                        selectedServerID = serverConfigs.first(where: { $0.id != id })?.id
                    }
                    serverStatuses.removeValue(forKey: id)
                }
                serverConfigs.remove(atOffsets: indexSet)
                saveServers()
            }
            .deleteDisabled(serverConfigs.count <= 1)
            .onMove { source, destination in
                serverConfigs.move(fromOffsets: source, toOffset: destination)
                saveServers()
            }
        } header: {
            HStack {
                Label("服务器", systemImage: "server.rack")
                Spacer()
                Text("\(serverConfigs.count) 个")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Test Section

    private var testSection: some View {
        Section {
            VStack(spacing: 12) {
                TextField("测试文本", text: $testText, axis: .vertical)
                    .font(.body)
                    .lineLimit(3...6)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                Picker("发音人", selection: $testVoice) {
                    ForEach(availableVoices) { v in
                        Text(v.displayName).tag(v.id)
                    }
                }
                .pickerStyle(.menu)

                if !currentVoiceStyles.isEmpty {
                    Picker("风格", selection: $testStyle) {
                        Text("无").tag("")
                        ForEach(currentVoiceStyles, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("语速").foregroundColor(.secondary).frame(width: 36, alignment: .leading)
                        Slider(value: $testRate, in: -10...10, step: 1)
                        Text("\(Int(testRate))").font(.caption.monospaced()).frame(width: 24)
                    }
                    HStack {
                        Text("音调").foregroundColor(.secondary).frame(width: 36, alignment: .leading)
                        Slider(value: $testPitch, in: -10...10, step: 1)
                        Text("\(Int(testPitch))").font(.caption.monospaced()).frame(width: 24)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        testConnection()
                    } label: {
                        HStack(spacing: 6) {
                            if serverStatuses[selectedServerID ?? UUID()] == "测试中..." {
                                ProgressView().scaleEffect(0.7)
                            }
                            Label("测试连接", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(serverStatuses[selectedServerID ?? UUID()] == "测试中...")

                    Button {
                        testSynthesis()
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingSynthesis {
                                ProgressView().scaleEffect(0.7)
                            }
                            Label("试听", systemImage: "play.circle")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTestingSynthesis || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !testResult.isEmpty {
                    let isSuccess = testResult.hasPrefix("合成成功") || testResult.contains("就绪")
                    HStack {
                        Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isSuccess ? .green : .red)
                        Text(testResult)
                            .font(.caption)
                        Spacer()
                    }
                }
            }

            Button {
                withAnimation { showPreview.toggle() }
            } label: {
                HStack {
                    Image(systemName: showPreview ? "eye.fill" : "eye")
                    Text("请求预览")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showPreview ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if showPreview {
                requestPreview
            }
        } header: {
            Label("语音测试", systemImage: "waveform")
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            ForEach(serverConfigs) { config in
                HStack(spacing: 10) {
                    statusDot(serverStatuses[config.id] ?? "未测试")
                        .frame(width: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(config.name.isEmpty ? "未命名" : config.name)
                            .font(.subheadline)
                        Text(serverStatuses[config.id] ?? "未测试")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if config.id == selectedServerID {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                            .font(.caption)
                    }
                }
            }

            Button {
                testAllServers()
            } label: {
                HStack {
                    if isTestingAll {
                        ProgressView().scaleEffect(0.7)
                    }
                    Label("全部测试", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isTestingAll)
        } header: {
            Label("服务器状态", systemImage: "gauge.with.dots.needle.33percent")
        }
    }

    // MARK: - Request Preview

    @ViewBuilder
    private var requestPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.secondary)
                Text("预发送内容（长按复制）")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            if let config = serverConfigs.first(where: { $0.id == selectedServerID }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("URL").font(.caption2.weight(.medium)).foregroundColor(.secondary)
                    let base = config.url.hasSuffix("/tts") ? config.url : config.url + "/tts"
                    let encoded = testText.addingPercentEncoding(withAllowedCharacters: .urlQueryParameterAllowed) ?? testText
                    let maskedKey = config.apiKey.isEmpty ? "" : "&api_key=" + String(config.apiKey.prefix(4)) + "***"
                    let urlParams = "t=\(encoded)&r=\(Int(testRate * 4))&p=\(Int(testPitch))"
                        + (testStyle.isEmpty ? "" : "&s=\(testStyle)")
                        + (testVoice.isEmpty ? "" : "&v=\(testVoice)")
                        + maskedKey
                    Text("\(base)?\(urlParams)")
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(4)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("请求参数").font(.caption2.weight(.medium)).foregroundColor(.secondary)
                    Group {
                        Text("t = \(testText)")
                        Text("r = \(Int(testRate * 4)) (\(Int(testRate)))")
                        Text("p = \(Int(testPitch))")
                        Text("s = \(testStyle.isEmpty ? "(空)" : testStyle)")
                        if !testVoice.isEmpty {
                            Text("v = \(testVoice)")
                        }
                        if !config.apiKey.isEmpty {
                            Text("api_key = \(String(config.apiKey.prefix(4)))***")
                        }
                    }
                    .font(.caption2.monospaced())
                }
                .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func statusDot(_ status: String) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 8, height: 8)
    }

    private func statusColor(_ status: String) -> Color {
        if status.contains("就绪") || status.contains("200") || status.contains("服务") {
            return .green
        } else if status == "未测试" || status.isEmpty {
            return .gray
        } else if status == "测试中..." {
            return .yellow
        } else {
            return .red
        }
    }

    private func deleteServer(_ config: EdgeTTSServerConfig) {
        if selectedServerID == config.id {
            selectedServerID = serverConfigs.first(where: { $0.id != config.id })?.id
        }
        serverStatuses.removeValue(forKey: config.id)
        serverConfigs.removeAll { $0.id == config.id }
        saveServers()
    }

    private func saveServers() {
        let valid = serverConfigs.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        Task {
            await EdgeTTSService.shared.setServers(valid)
        }
    }

    private func loadServers() async {
        let servers = await EdgeTTSService.shared.configuredServers
        await MainActor.run {
            serverConfigs = servers
            if serverConfigs.isEmpty {
                var config = EdgeTTSServerConfig(url: EdgeTTSService.defaultServerURL, apiKey: "")
                config.name = "默认服务器"
                serverConfigs = [config]
            }
            for s in serverConfigs {
                serverStatuses[s.id] = "未测试"
            }
            if let savedID = UserDefaults.standard.string(forKey: "selectedTSServerID"),
               let id = UUID(uuidString: savedID),
               serverConfigs.contains(where: { $0.id == id }) {
                selectedServerID = id
            }
            if selectedServerID == nil {
                selectedServerID = serverConfigs.first?.id
            }
        }
    }

    private func loadVoices() async {
        guard let id = selectedServerID else { return }
        let voices = await EdgeTTSService.shared.fetchVoices(serverID: id)
        await MainActor.run {
            availableVoices = voices.filter { $0.locale.hasPrefix("zh-CN") }
            if testVoice.isEmpty || !availableVoices.contains(where: { $0.id == testVoice }) {
                testVoice = availableVoices.first?.id ?? ""
            }
        }
    }

    private func testConnection() {
        guard let id = selectedServerID else { return }
        serverStatuses[id] = "测试中..."
        Task {
            let valid = serverConfigs.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            await EdgeTTSService.shared.setServers(valid)
            let result = await EdgeTTSService.shared.healthCheck(serverID: id)
            await MainActor.run {
                serverStatuses[id] = result
                store.edgeTTSLastHealth = result
            }
        }
    }

    private func testAllServers() {
        isTestingAll = true
        for s in serverConfigs {
            serverStatuses[s.id] = "测试中..."
        }
        Task {
            for s in serverConfigs {
                let result = await EdgeTTSService.shared.healthCheck(serverID: s.id)
                await MainActor.run {
                    serverStatuses[s.id] = result
                }
            }
            await MainActor.run {
                isTestingAll = false
            }
        }
    }

    private func testSynthesis() {
        guard !isTestingSynthesis, let id = selectedServerID else { return }
        isTestingSynthesis = true
        testResult = ""
        Task {
            let result = await store.testTTSSynthesize(serverID: id, text: testText, voice: testVoice, style: testStyle, rate: testRate, pitch: testPitch)
            await MainActor.run {
                testResult = result
                isTestingSynthesis = false
                if result.contains("成功"), let url = store.ttsTestAudioURL {
                    Task {
                        await store.audioController.playFilesAndWait([url])
                    }
                }
            }
        }
    }
}

// MARK: - Server Edit Sheet

private struct ServerEditView: View {
    @Environment(\.dismiss) private var dismiss

    let existingID: UUID?
    @State private var name: String
    @State private var url: String
    @State private var apiKey: String
    let onSave: (EdgeTTSServerConfig) -> Void

    init(config: EdgeTTSServerConfig? = nil, onSave: @escaping (EdgeTTSServerConfig) -> Void) {
        self.existingID = config?.id
        _name = State(initialValue: config?.name ?? "")
        _url = State(initialValue: config?.url ?? "")
        _apiKey = State(initialValue: config?.apiKey ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("名称") {
                        TextField("例如：本地服务器", text: $name)
                    }
                    LabeledContent("地址") {
                        TextField("http://192.168.1.100:37788", text: $url)
                            .font(.caption.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    LabeledContent("密钥") {
                        TextField("API Key（可选）", text: $apiKey)
                            .font(.caption.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Label("服务器信息", systemImage: "server.rack")
                }
            }
            .navigationTitle(existingID != nil ? "编辑服务器" : "添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let config = EdgeTTSServerConfig(
                            id: existingID ?? UUID(),
                            name: name,
                            url: url,
                            apiKey: apiKey
                        )
                        onSave(config)
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension CharacterSet {
    static let urlQueryParameterAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove("&")
        allowed.remove("+")
        return allowed
    }()
}
