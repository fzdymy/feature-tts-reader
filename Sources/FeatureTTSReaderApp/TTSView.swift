import SwiftUI
import Foundation

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

    // MARK: - Multi-Role Test State
    @State private var isTestingMultiRole = false
    @State private var multiRoleTestResult = ""
    @State private var multiRoleGlobalRate: Double = 0

    // MARK: - Custom Multi-Role Test State
    @State private var customMultiRoleText = ""
    @State private var isProcessingCustom = false
    @State private var customWorkerSegments: [AISegment] = []
    @State private var customCharacterVoices: [String: String] = [:] // characterName -> voiceID
    @State private var customSynthesisResult = ""
    @State private var isProcessingWorker = false
    @State private var workerProgress: Double = 0
    @State private var workerProgressMessage = ""

    // MARK: - AI Worker Config State
    @State private var aiWorkerConfigs: [AIWorkerConfig] = []
    @State private var selectedWorkerID: UUID? {
        didSet {
            if let id = selectedWorkerID {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedAIWorkerID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedAIWorkerID")
            }
        }
    }
    @State private var showWorkerEditSheet = false
    @State private var editingWorkerConfig: AIWorkerConfig?
    @State private var showAddWorkerSheet = false
    @State private var workerTestResult = ""

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
                } header: {
                    HStack {
                        Label("服务器", systemImage: "server.rack")
                        Spacer()
                        Text("\(serverConfigs.count) 个")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if selectedServerID != nil {
                    testSection
                    multiRoleTestSection
                    customMultiRoleSection
                }
                statusSection
                aiWorkerSection
            }
            .navigationTitle("语音引擎")
            .toolbar {
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
            .sheet(item: $editingWorkerConfig) { config in
                WorkerEditView(config: config) { updated in
                    if let idx = aiWorkerConfigs.firstIndex(where: { $0.id == config.id }) {
                        aiWorkerConfigs[idx] = updated
                        saveWorkerConfigs()
                    }
                }
            }
            .sheet(isPresented: $showAddWorkerSheet) {
                WorkerEditView { config in
                    var newConfig = config
                    if newConfig.name == "默认" || newConfig.name.isEmpty {
                        newConfig.name = "Worker \(aiWorkerConfigs.count + 1)"
                    }
                    aiWorkerConfigs.append(newConfig)
                    if aiWorkerConfigs.count == 1 {
                        selectedWorkerID = newConfig.id
                    }
                    saveWorkerConfigs()
                }
            }
            .task {
                await loadServers()
                await loadWorkerConfigs()
            }
            .task(id: selectedServerID) {
                await loadVoices()
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

    }

    // MARK: - AI Worker Section

    private var aiWorkerSection: some View {
        Section {
            if aiWorkerConfigs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("暂无 AI Worker 配置")
                        .font(.subheadline.weight(.medium))
                    Text("点击下方按钮添加 Worker，用于小说角色、情绪识别")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                ForEach(aiWorkerConfigs) { config in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(config.isDefault ? Color.accentColor : Color.secondary)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(config.name)
                                .font(.subheadline.weight(.medium))
                            Text(config.baseURL)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if config.isDefault {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.subheadline)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectWorker(config.id)
                    }
                    .contextMenu {
                        Button { selectWorker(config.id) } label: {
                            Label("设为默认", systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive) { deleteWorker(config.id) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                showAddWorkerSheet = true
            } label: {
                Label("添加 AI Worker", systemImage: "plus.circle")
            }

            if !workerTestResult.isEmpty {
                HStack {
                    Image(systemName: workerTestResult.hasPrefix("成功") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(workerTestResult.hasPrefix("成功") ? .green : .red)
                    Text(workerTestResult)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        } header: {
            Label("AI 剧本解析 Worker", systemImage: "brain.head.profile")
        }
    }

    private func loadWorkerConfigs() async {
        if let data = UserDefaults.standard.data(forKey: "aiWorkerConfigs"),
           let decoded = try? JSONDecoder().decode([AIWorkerConfig].self, from: data) {
            await MainActor.run {
                aiWorkerConfigs = decoded
            }
            if let savedID = UserDefaults.standard.string(forKey: "selectedAIWorkerID"),
               let id = UUID(uuidString: savedID),
               aiWorkerConfigs.contains(where: { $0.id == id }) {
                await MainActor.run { selectedWorkerID = id }
            } else if aiWorkerConfigs.first?.isDefault == true {
                await MainActor.run { selectedWorkerID = aiWorkerConfigs.first?.id }
            }
        }
    }

    private func saveWorkerConfigs() {
        if let data = try? JSONEncoder().encode(aiWorkerConfigs) {
            UserDefaults.standard.set(data, forKey: "aiWorkerConfigs")
        }
    }

    private func selectWorker(_ id: UUID) {
        selectedWorkerID = id
        for i in aiWorkerConfigs.indices {
            aiWorkerConfigs[i].isDefault = aiWorkerConfigs[i].id == id
        }
        saveWorkerConfigs()
    }

    private func deleteWorker(_ id: UUID) {
        aiWorkerConfigs.removeAll { $0.id == id }
        if selectedWorkerID == id {
            selectedWorkerID = aiWorkerConfigs.first?.id
        }
        saveWorkerConfigs()
    }

    private func testWorkerConnection(_ config: AIWorkerConfig) {
        workerTestResult = "测试中..."
        Task {
            do {
                _ = try await AIWorkerService.shared.testConnection(config: config)
                await MainActor.run { workerTestResult = "成功 ✓" }
            } catch {
                await MainActor.run { workerTestResult = "失败: \(error.localizedDescription)" }
            }
        }
    }

    private func getSelectedWorkerConfig() -> AIWorkerConfig? {
        if let id = selectedWorkerID {
            return aiWorkerConfigs.first { $0.id == id }
        }
        return aiWorkerConfigs.first { $0.isDefault } ?? aiWorkerConfigs.first
    }

    private func getDefaultWorkerConfig() -> AIWorkerConfig? {
        return aiWorkerConfigs.first { $0.isDefault } ?? aiWorkerConfigs.first
    }

    // MARK: - Multi-Role Test Section

    private var multiRoleTestSection: some View {
        Section {
            ForEach(multiRoleTestScenes) { scene in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scene.characterName)
                            .font(.subheadline.weight(.medium))
                        Text(scene.voice)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("语速 \(Int(scene.rate))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("音调 \(Int(scene.pitch))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 全局语速叠加滑块
            VStack(spacing: 8) {
                HStack {
                    Text("语速").foregroundColor(.secondary).frame(width: 60, alignment: .leading)
                    Slider(value: $multiRoleGlobalRate, in: -10...10, step: 1)
                    Text("\(Int(multiRoleGlobalRate))").font(.caption.monospaced()).frame(width: 24)
                }
                Text("此值将叠加到每个角色自带语速上（例：角色 +3，全局 +2 → 实际 +5）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

            Button {
                runMultiRoleTest()
            } label: {
                HStack {
                    if isTestingMultiRole {
                        ProgressView().scaleEffect(0.7)
                    }
                    Label("播放全部角色", systemImage: "play.circle.fill")
                }
            }
            .disabled(isTestingMultiRole || selectedServerID == nil)

            if !multiRoleTestResult.isEmpty {
                let isSuccess = multiRoleTestResult.contains("/")
                HStack {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isSuccess ? .green : .red)
                    Text(multiRoleTestResult)
                        .font(.caption)
                    Spacer()
                    
                    // 暂停/继续按钮 - 仅在有播放内容时显示
                    if store.audioController.isPlaying {
                        Button {
                            store.audioController.pause()
                        } label: {
                            Image(systemName: "pause.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                    } else if !multiRoleTestResult.contains("失败") && !multiRoleTestResult.isEmpty {
                        Button {
                            store.audioController.resume()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Label("多角色测试", systemImage: "person.2.fill")
        }
    }

    private struct MultiRoleScene: Identifiable {
        let id = UUID()
        let characterName: String
        let voice: String
        let rate: Double
        let pitch: Double
        let text: String
    }

    private let multiRoleTestScenes: [MultiRoleScene] = [
        MultiRoleScene(characterName: "旁白 · 开场", voice: "zh-CN-XiaoxiaoNeural", rate: 0, pitch: 0,
                       text: "雨越下越大。谈判桌前的空气仿佛凝固了，五个各怀鬼胎的人，正在进行最后的博弈。就在这时，云希猛地一拍桌子，"),
        MultiRoleScene(characterName: "云希 · 愤怒", voice: "zh-CN-YunxiNeural", rate: 6, pitch: 3,
                       text: "够了！别再用那些冠冕堂皇的理由来骗我了！这根本就不是什么合作！你们明明就是想要吃掉我所有的股份！"),
        MultiRoleScene(characterName: "旁白 · 穿插", voice: "zh-CN-XiaoxiaoNeural", rate: 0, pitch: -1,
                       text: "他红着眼眶怒吼道。坐在一旁的云健却只是慢条斯理地端起茶杯，冷笑了一声说："),
        MultiRoleScene(characterName: "云健 · 沉稳", voice: "zh-CN-YunjianNeural", rate: -4, pitch: -3,
                       text: "年轻人，注意你的态度。在绝对的力量面前，你的愤怒……毫无意义。"),
        MultiRoleScene(characterName: "旁白 · 突变", voice: "zh-CN-XiaoxiaoNeural", rate: 4, pitch: -2,
                       text: "云健说完，现场陷入了一阵可怕的沉默。突然，房间里的灯光剧烈闪烁。就在大伙心惊肉跳的时候，晓北突然噗嗤一声笑了出来，打破了僵局："),
        MultiRoleScene(characterName: "晓北 · 调侃", voice: "zh-CN-XiaoyiNeural", rate: 3, pitch: 4,
                       text: "哎呀妈呀，大伙都消消火呗，这咋还整得跟拍电影似的呢？命要是折里头了，留着那几个破钱给谁花啊？"),
        MultiRoleScene(characterName: "旁白 · 过渡", voice: "zh-CN-XiaoxiaoNeural", rate: 0, pitch: 0,
                       text: "晓北笑着拍了拍手。然而，角落里的陕兵却吓得面色苍白，浑身直哆嗦。他缩了缩脖子，带着哭腔说："),
        MultiRoleScene(characterName: "陕兵 · 恐惧", voice: "zh-CN-YunzeNeural", rate: 5, pitch: 5,
                       text: "你、你们别说了……外、外面的保安好像把门锁上了……咱、咱今天是不是出不去了呀……"),
        MultiRoleScene(characterName: "旁白 · 收尾", voice: "zh-CN-XiaoxiaoNeural", rate: -4, pitch: -4,
                       text: "陕兵说完，全场再次陷入了一阵死一般的寂静。无边的黑暗，将这五个人的秘密彻底吞噬。"),
    ]

    // MARK: - Custom Multi-Role Section

private var customMultiRoleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                TextField("粘贴或输入小说文本（AI Worker 解析角色、情绪、语气、流水合成播放）", text: $customMultiRoleText, axis: .vertical)
                    .font(.body)
                    .lineLimit(4...8)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                // 处理状态
                if isProcessingWorker {
                    VStack(spacing: 8) {
                        ProgressView(value: workerProgress) {
                            Text(workerProgressMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                } else if !customWorkerSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("解析到 \(customWorkerSegments.count) 个片段，\(Set(customWorkerSegments.map { $0.speaker }).count) 个角色")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)

                        let speakers = Array(Set(customWorkerSegments.map { $0.speaker })).sorted()
                        ForEach(speakers.prefix(10), id: \.self) { speaker in
                            HStack {
                                Text(speaker)
                                    .font(.subheadline)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { customCharacterVoices[speaker] ?? "" },
                                    set: { customCharacterVoices[speaker] = $0 }
                                )) {
                                    Text("自动分配").tag("")
                                    ForEach(availableVoices.filter { $0.locale.hasPrefix("zh-CN") }) { v in
                                        Text(v.displayName).tag(v.id)
}
    // MARK: - Worker Edit Sheet

    private struct WorkerEditView: View {
        @Environment(\.dismiss) private var dismiss

        let existingID: UUID?
        @State private var name: String
        @State private var baseURL: String
        @State private var authKey: String
        @State private var model: String
        @State private var sliceCharLimit: Int
        @State private var timeout: Double
        let onSave: (AIWorkerConfig) -> Void

        init(config: AIWorkerConfig? = nil, onSave: @escaping (AIWorkerConfig) -> Void) {
            self.existingID = config?.id
            _name = State(initialValue: config?.name ?? "")
            _baseURL = State(initialValue: config?.baseURL ?? "")
            _authKey = State(initialValue: config?.authKey ?? "")
            _model = State(initialValue: config?.model ?? "qwen-plus")
            _sliceCharLimit = State(initialValue: config?.sliceCharLimit ?? 1000)
            _timeout = State(initialValue: config?.timeout ?? 30)
            self.onSave = onSave
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        LabeledContent("名称") {
                            TextField("例如：我的 Qwen Worker", text: $name)
                        }
                        LabeledContent("Base URL") {
                            TextField("https://your-worker.workers.dev", text: $baseURL)
                                .font(.caption.monospaced())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        LabeledContent("Auth Key") {
                            TextField("X-Auth-Key 密钥", text: $authKey)
                                .font(.caption.monospaced())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        LabeledContent("模型") {
                            TextField("qwen-plus", text: $model)
                                .font(.caption.monospaced())
                        }
                        LabeledContent("单片字符限制") {
                            TextField("1000", value: $sliceCharLimit, format: .number)
                                .keyboardType(.numberPad)
                        }
                        LabeledContent("超时 (秒)") {
                            TextField("30", value: $timeout, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    } header: {
                        Label("Worker 配置", systemImage: "brain.head.profile")
                    }
                }
                .navigationTitle(existingID != nil ? "编辑 Worker" : "添加 Worker")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let config = AIWorkerConfig(
                                id: existingID ?? UUID(),
                                name: name,
                                baseURL: baseURL,
                                authKey: authKey,
                                model: model,
                                sliceCharLimit: sliceCharLimit,
                                timeout: timeout
                            )
                            onSave(config)
                            dismiss()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || baseURL.isEmpty || authKey.isEmpty)
                    }
                }
            }
        }
    }
}
                                .pickerStyle(.menu)
                                .frame(width: 140)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                // 说话人分析与发送配置预览
                if !customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customSpeakerAnalysisSection
                }

                // 控制按钮
                VStack(spacing: 8) {
                    Button {
                        processCustomWithWorker()
                    } label: {
                        Label("AI 解析并匹配音色", systemImage: "brain.head.profile")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessingWorker || customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || getSelectedWorkerConfig() == nil)

                    Button {
                        synthesizeAndPlayCustom()
                    } label: {
                        HStack {
                            if isSynthesizingCustom {
                                ProgressView().scaleEffect(0.7)
                            }
                            Label("流水合成并播放", systemImage: "play.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSynthesizingCustom || customScanResult == nil || customScanResult?.characters.isEmpty == true || selectedServerID == nil)

                    if !customSynthesisResult.isEmpty {
                        let isSuccess = customSynthesisResult.hasPrefix("已入队") || customSynthesisResult.contains("播放")
                        HStack {
                            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isSuccess ? .green : .red)
                            Text(customSynthesisResult)
                                .font(.caption)
                            Spacer()
                        }
                    }

                    // 暂停/继续按钮（仅在播放时显示）
                    if store.audioController.isPlaying && !isSynthesizingCustom {
                        HStack {
                            Button {
                                store.audioController.pause()
                            } label: {
                                Label("暂停", systemImage: "pause.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                store.audioController.resume()
                            } label: {
                                Label("继续", systemImage: "play.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        } header: {
            Label("自定义多角色测试", systemImage: "text.bubble.fill")
        }
    }

    // MARK: - Custom Multi-Role Actions

    private func processCustomWithWorker() {
        let text = customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        guard let workerConfig = getSelectedWorkerConfig() else {
            customSynthesisResult = "请先在设置中配置 AI Worker"
            return
        }

        guard let serverID = selectedServerID else {
            customSynthesisResult = "请先选择 TTS 服务器"
            return
        }

        isProcessingWorker = true
        customWorkerSegments.removeAll()
        customCharacterVoices.removeAll()
        customSynthesisResult = ""
        workerProgress = 0
        workerProgressMessage = "准备中..."

        Task {
            do {
                let segments = try await AIWorkerService.shared.processChapter(
                    text: customMultiRoleText,
                    config: workerConfig,
                    progress: { progress, message in
                        await MainActor.run {
                            workerProgress = progress
                            workerProgressMessage = message
                        }
                    }
                )

                await MainActor.run {
                    customWorkerSegments = segments
                    isProcessingWorker = false
                    workerProgress = 1.0
                    workerProgressMessage = "解析完成，共 \(segments.count) 个片段"

                    // 自动分�配音色（基于 speaker 名称）
                    assignVoicesToSegments(segments)
                    customSynthesisResult = "解析完成，共 \(segments.count) 个片段，可开始合成"
                }
            } catch {
                await MainActor.run {
                    isProcessingWorker = false
                    workerProgress = 0
                    customSynthesisResult = "解析失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func getSelectedWorkerConfig() -> AIWorkerConfig? {
        if let id = selectedWorkerID {
            return aiWorkerConfigs.first { $0.id == id }
        }
        return aiWorkerConfigs.first { $0.isDefault } ?? aiWorkerConfigs.first
    }

    private func assignVoicesToSegments(_ segments: [AISegment]) {
        let speakers = Set(segments.map { $0.speaker })
        var voices: [String: String] = [:]

        for speaker in speakers {
            // 如果已有手动分配，保留
            if let existing = customCharacterVoices[speaker], !existing.isEmpty {
                voices[speaker] = existing
                continue
            }
            // 自动匹配：从可用音色中按性别分配（简单启发式）
            let matchedVoice = availableVoices.first { v in
                v.locale.hasPrefix("zh-CN") &&
                (speaker.contains("女") || speaker.contains("小姐") || speaker.contains("姑娘") || speaker.contains("她")) == (v.gender == "Female")
            } ?? availableVoices.first { $0.locale.hasPrefix("zh-CN") }

            if let v = matchedVoice {
                voices[speaker] = v.id
            }
        }
        customCharacterVoices = voices
    }

    private func synthesizeAndPlayCustom() {
        guard let serverID = selectedServerID,
              !customWorkerSegments.isEmpty else { return }

        isProcessingCustom = true
        customSynthesisResult = "正在合成首段..."

        Task {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let globalRate = multiRoleGlobalRate

            // 首段合成并立即播放
            do {
                let firstSegment = customWorkerSegments[0]
                let voiceID = customCharacterVoices[firstSegment.speaker] ?? ""
                let rate = Int(globalRate)
                let pitch = 0
                let style = firstSegment.emotion.ssmlStyle

                let audioData = try await EdgeTTSService.shared.synthesizeWithSSML(
                    text: firstSegment.text,
                    voice: voiceID,
                    rate: rate,
                    pitch: pitch,
                    style: style,
                    serverID: serverID
                )

                let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                let url = cachesDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                try audioData.write(to: url, options: .atomic)

                let segment = ScriptSegment(
                    id: UUID(),
                    characterName: firstSegment.speaker,
                    voice: voiceID,
                    rate: rate,
                    pitch: pitch,
                    style: style,
                    text: firstSegment.text,
                    emotionTag: firstSegment.emotion.rawValue,
                    paragraphIndex: 0
                )
                let item = TTSQueueItem(
                    segment: segment,
                    audioURL: url,
                    audioData: audioData,
                    chapterTitle: "自定义多角色",
                    bookTitle: "测试",
                    bookID: "custom",
                    chapterIndex: 0,
                    segmentIndex: 0,
                    totalSegments: customWorkerSegments.count,
                    paragraphIndex: 0,
                    sentenceIndex: nil,
                    anchor: nil
                )

                await MainActor.run {
                    store.audioController.appendToQueue([item])
                    customSynthesisResult = "第 1/\(customWorkerSegments.count) 段合成完成，开始播放..."
                }
            } catch {
                await MainActor.run {
                    customSynthesisResult = "首段合成失败: \(error.localizedDescription)"
                    isSynthesizingCustom = false
                }
                return
            }

            // 后台并行合成剩余段落
            await MainActor.run { customSynthesisResult = "首段播放中，后台合成剩余 \(customWorkerSegments.count - 1) 段..." }
            var restItems: [TTSQueueItem] = []

            for (idx, segment) in customWorkerSegments.dropFirst().enumerated() {
                let voiceID = customCharacterVoices[segment.speaker] ?? ""
                let rate = Int(globalRate)
                let pitch = 0
                let style = segment.emotion.ssmlStyle

                do {
                    let audioData = try await EdgeTTSService.shared.synthesizeWithSSML(
                        text: segment.text,
                        voice: voiceID,
                        rate: rate,
                        pitch: pitch,
                        style: style,
                        serverID: serverID
                    )

                    let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                    let url = cachesDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                    try audioData.write(to: url, options: .atomic)

                    let seg = ScriptSegment(
                        id: UUID(),
                        characterName: segment.speaker,
                        voice: voiceID,
                        rate: rate,
                        pitch: pitch,
                        style: style,
                        text: segment.text,
                        emotionTag: segment.emotion.rawValue,
                        paragraphIndex: idx + 1
                    )
                    let item = TTSQueueItem(
                        segment: seg,
                        audioURL: url,
                        audioData: audioData,
                        chapterTitle: "自定义多角色",
                        bookTitle: "测试",
                        bookID: "custom",
                        chapterIndex: 0,
                        segmentIndex: idx + 1,
                        totalSegments: customWorkerSegments.count,
                        paragraphIndex: idx + 1,
                        sentenceIndex: nil,
                        anchor: nil
                    )
                    restItems.append(item)

                    await MainActor.run {
                        customSynthesisResult = "已合成 \(idx + 2)/\(customWorkerSegments.count) 段..."
                    }
                } catch {
                    await MainActor.run {
                        customSynthesisResult = "第 \(idx + 2) 段合成失败: \(error.localizedDescription)"
                    }
                }
            }

            await MainActor.run {
                store.audioController.appendToQueue(restItems)
                customSynthesisResult = "\(customWorkerSegments.count)/\(customWorkerSegments.count) 段全部入队，正在流式播放"
                isSynthesizingCustom = false
            }
        }
    }

        isSynthesizingCustom = true
        customSynthesisResult = "正在分析对话..."
        
        Task {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            
            // Use CharacterAnalyzer to detect dialogues with speakers
            let analyzer = CharacterAnalyzer()
            let dialogues = analyzer.detectDialogues(in: customMultiRoleText)
            
            // Build character name -> voice mapping
            var charVoiceMap: [String: String] = [:]
            for profile in result.characters {
                if let voiceID = customCharacterVoices[profile.name], !voiceID.isEmpty {
                    charVoiceMap[profile.name] = voiceID
                } else if let matched = availableVoices.first(where: { 
                    $0.locale.hasPrefix("zh-CN") && 
                    (profile.gender == "Male" && $0.gender == "Male" || profile.gender == "Female" && $0.gender == "Female")
                }) {
                    charVoiceMap[profile.name] = matched.id
                }
            }
            let defaultVoiceID = charVoiceMap.values.first ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
            
            // Fixed narrator voice - always use female voice for narrator
            let narratorVoiceID = charVoiceMap["旁白"] ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") && $0.gender == "Female" })?.id ?? ""
            
            // Build known characters set for speaker matching
            let knownCharacters = Set(result.characters.map { $0.name })
            
            // For each dialogue, try to infer a better speaker using the known characters
            var dialoguesWithSpeakers: [(speaker: String?, content: String, range: Range<String.Index>)] = []
            for dialogue in dialogues {
                var speaker = dialogue.speaker
                // If no speaker detected, try to infer from context using known characters
                if speaker == nil || speaker?.isEmpty == true {
                    // Get context before the dialogue (200 chars before)
                    let lower = dialogue.range.lowerBound
                    let beforeEnd = customMultiRoleText.index(customMultiRoleText.startIndex, offsetBy: customMultiRoleText.distance(from: customMultiRoleText.startIndex, to: lower))
                    let beforeStart = customMultiRoleText.index(beforeEnd, offsetBy: -min(300, customMultiRoleText.distance(from: customMultiRoleText.startIndex, to: beforeEnd)), limitedBy: customMultiRoleText.startIndex) ?? customMultiRoleText.startIndex
                    let context = String(customMultiRoleText[beforeStart..<beforeEnd])
                    
                    // Try to infer speaker from context using known characters
                    if let inferred = analyzer.inferSpeaker(from: context, knownCharacters: Array(knownCharacters)) {
                        speaker = inferred
                    }
                }
                dialoguesWithSpeakers.append((speaker: speaker, content: dialogue.content, range: dialogue.range))
            }
            
            // Segment text into dialogue and narration using CharacterAnalyzer
            var segments: [(speaker: String?, text: String)] = []
            var lastEnd = customMultiRoleText.startIndex
            
            for dialogue in dialoguesWithSpeakers {
                // Add narration before this dialogue
                if dialogue.range.lowerBound > lastEnd {
                    let narrationText = String(customMultiRoleText[lastEnd..<dialogue.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !narrationText.isEmpty {
                        segments.append((speaker: "旁白", text: narrationText))
                    }
                }
                // Add the dialogue with its speaker
                let speakerName = dialogue.speaker ?? ""
                var matchedSpeaker: String? = nil
                if !speakerName.isEmpty {
                    if knownCharacters.contains(speakerName) {
                        matchedSpeaker = speakerName
                    } else {
                        // Try to find character who has this as alias
                        for profile in result.characters {
                            if profile.aliases.contains(speakerName) || profile.name.contains(speakerName) || speakerName.contains(profile.name) {
                                matchedSpeaker = profile.name
                                break
                            }
                        }
                    }
                }
                segments.append((speaker: matchedSpeaker, text: dialogue.content))
                lastEnd = dialogue.range.upperBound
            }
            // Trailing narration
            if lastEnd < customMultiRoleText.endIndex {
                let trailing = String(customMultiRoleText[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trailing.isEmpty {
                    segments.append((speaker: "旁白", text: trailing))
                }
            }
            
            // If no dialogues detected, fall back to sentence splitting
            if segments.isEmpty {
                let text = customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines)
                let sentences = text.split { "。！？.!?".contains($0) }.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                for sentence in sentences {
                    segments.append((speaker: "旁白", text: sentence))
                }
            }
            
            // Remove empty segments
            let validSegments = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let total = validSegments.count
            guard total > 0 else {
                await MainActor.run {
                    customSynthesisResult = "未检测到可合成内容"
                    isSynthesizingCustom = false
                }
                return
            }
            
            let first = validSegments[0]
            let firstSpeaker = first.speaker ?? "旁白"
            let firstVoiceID: String
            if firstSpeaker == "旁白" {
                firstVoiceID = narratorVoiceID.isEmpty ? (availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") && $0.gender == "Female" })?.id ?? "") : narratorVoiceID
            } else {
                firstVoiceID = charVoiceMap[first.speaker ?? "旁白"] ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
            }
            let rate = multiRoleGlobalRate
            let pitch = 0.0
            
            do {
                let firstText = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !firstText.isEmpty else { throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "空文本"]) }
                
                let audioData = try await EdgeTTSService.shared.synthesize(
                    text: firstText,
                    voice: firstVoiceID,
                    rate: rate,
                    pitch: pitch,
                    style: "",
                    serverID: id
                )
                let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                let url = cachesDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                try audioData.write(to: url, options: .atomic)
                
                let firstSpeakerName = first.speaker ?? "旁白"
                let segment = ScriptSegment(
                    id: UUID(),
                    characterName: firstSpeakerName,
                    voice: firstVoiceID,
                    rate: Int(rate),
                    pitch: Int(pitch),
                    style: "",
                    text: firstText,
                    emotionTag: "",
                    paragraphIndex: 0
                )
                let item = TTSQueueItem(
                    segment: segment,
                    audioURL: url,
                    audioData: audioData,
                    chapterTitle: "自定义多角色",
                    bookTitle: "测试",
                    bookID: "test",
                    chapterIndex: 0,
                    segmentIndex: 0,
                    totalSegments: validSegments.count,
                    paragraphIndex: 0,
                    sentenceIndex: nil,
                    anchor: nil
                )
                await MainActor.run {
                    store.audioController.appendToQueue([item])
                    customSynthesisResult = "第 1/\(validSegments.count) 段合成完成，开始播放..."
                }
            } catch {
                await MainActor.run {
                    customSynthesisResult = "首段合成失败: \(error.localizedDescription)"
                    isSynthesizingCustom = false
                }
                return
            }
            
            // 2. 后台合成剩余段落
            await MainActor.run { customSynthesisResult = "首段播放中，后台合成剩余 \(validSegments.count - 1) 段..." }
            var restItems: [TTSQueueItem] = []
            
            for (idx, segment) in validSegments.dropFirst().enumerated() {
                let speaker = segment.speaker ?? "旁白"
                let voiceID: String
                if speaker == "旁白" {
                    voiceID = narratorVoiceID.isEmpty ? (availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") && $0.gender == "Female" })?.id ?? "") : narratorVoiceID
                } else {
                    voiceID = charVoiceMap[segment.speaker ?? "旁白"] ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
                }
                let rate = multiRoleGlobalRate
                let pitch = 0.0
                
                do {
                    let segText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !segText.isEmpty else { continue }
                    
                    let audioData = try await EdgeTTSService.shared.synthesize(
                        text: segText,
                        voice: voiceID,
                        rate: rate,
                        pitch: pitch,
                        style: "",
                        serverID: id
                    )
                    let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                    let url = cachesDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                    try audioData.write(to: url, options: .atomic)
                    
                    let speakerName = segment.speaker ?? "旁白"
                    let seg = ScriptSegment(
                        id: UUID(),
                        characterName: speakerName,
                        voice: voiceID,
                        rate: Int(rate),
                        pitch: Int(pitch),
                        style: "",
                        text: segText,
                        emotionTag: "",
                        paragraphIndex: idx + 1
                    )
                    let item = TTSQueueItem(
                        segment: seg,
                        audioURL: url,
                        audioData: audioData,
                        chapterTitle: "自定义多角色",
                        bookTitle: "测试",
                        bookID: "test",
                        chapterIndex: 0,
                        segmentIndex: idx + 1,
                        totalSegments: validSegments.count,
                        paragraphIndex: idx + 1,
                        sentenceIndex: nil,
                        anchor: nil
                    )
                    restItems.append(item)
                    
                    await MainActor.run {
                        customSynthesisResult = "已合成 \(idx + 2)/\(validSegments.count) 段..."
                    }
                } catch {
                    await MainActor.run {
                        customSynthesisResult = "第 \(idx + 2) 段合成失败: \(error.localizedDescription)"
                        isSynthesizingCustom = false
                    }
                    return
                }
            }
            
            // 3. 剩余全部入队
            await MainActor.run {
                store.audioController.appendToQueue(restItems)
                customSynthesisResult = "\(validSegments.count)/\(validSegments.count) 段全部入队，正在流式播放"
                isSynthesizingCustom = false
            }
        }
    }

    // MARK: - Speaker Analysis Section

    @ViewBuilder
    private var speakerAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.2.badge.gearshape")
                    .foregroundColor(.secondary)
                Text("说话人分析预览（长按复制）")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            if testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("在上方输入测试文本即可看到说话人识别结果")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .italic()
            } else {
                let analyzer = CharacterAnalyzer()
                let dialogues = analyzer.detectDialogues(in: testText)
                let speakerMap = buildSpeakerMap(from: dialogues)

                if speakerMap.isEmpty {
                    Text("未检测到对话标记，将作为旁白整段朗读")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(speakerMap.keys.sorted()), id: \.self) { speaker in
                        if let info = speakerMap[speaker] {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(info.isNarrator ? Color.gray : Color.accentColor)
                                    .frame(width: 6, height: 6)
                                Text("\(speaker) → \(info.voice)")
                                    .font(.caption2.monospaced())
                                if let rate = info.rate, rate != 0 {
                                    Text("r=\(rate)")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func buildSpeakerMap(from dialogues: [DialogueMatch]) -> [String: (voice: String, rate: Int?, isNarrator: Bool)] {
        var map: [String: (voice: String, rate: Int?, isNarrator: Bool)] = [:]
        let availableVoices = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }
        let femaleVoice = availableVoices.first(where: { $0.gender == "Female" })?.id ?? ""
        let maleVoice = availableVoices.first(where: { $0.gender == "Male" })?.id ?? ""
        let defaultVoice = availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""

        for d in dialogues {
            let speaker = d.speaker ?? "旁白"
            if map[speaker] == nil {
                let isNarrator = speaker == "旁白" || speaker.isEmpty
                var voice: String
                let rate: Int? = Int(testRate)
                if isNarrator {
                    voice = femaleVoice.isEmpty ? defaultVoice : femaleVoice
                } else {
                    // 简单按长度判断性别（演示用），实际应用中有角色性别信息
                    voice = speaker.count % 2 == 0 ? femaleVoice : maleVoice
                    if voice.isEmpty { voice = defaultVoice }
                }
                map[speaker] = (voice: voice.isEmpty ? "默认音色" : voice, rate: rate, isNarrator: isNarrator)
            }
        }
        return map
    }

    // MARK: - Custom Speaker Analysis Section

    @ViewBuilder
    private var customSpeakerAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.2.badge.gearshape")
                    .foregroundColor(.secondary)
                Text("预计 TTS 配置（长按复制）")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            if !customWorkerSegments.isEmpty {
                let config = buildCustomTTSConfig(from: customWorkerSegments)

                if config.isEmpty {
                    Text("未检测到对话，将以旁白身份整段朗读")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(config.keys.sorted()), id: \.self) { speaker in
                        if let info = config[speaker] {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(info.isNarrator ? Color.gray : Color.accentColor)
                                    .frame(width: 6, height: 6)
                                Text("\(speaker)")
                                    .font(.caption2.monospaced())
                                    .fontWeight(.medium)
                                Text("→")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("v=\(info.voice)")
                                    .font(.caption2.monospaced())
                                if info.rate != 0 {
                                    Text("r=\(info.rate)")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                                if info.pitch != 0 {
                                    Text("p=\(info.pitch)")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                                if !info.style.isEmpty {
                                    Text("s=\(info.style)")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }

                    // 显示原文分段预览
                    let segments = buildSegmentsPreview(from: customWorkerSegments)
                    if !segments.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text("原文分段预览")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                        ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(idx + 1).")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, alignment: .trailing)
                                Text("【\(seg.speaker)】\(seg.text)")
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .foregroundColor(seg.speaker == "旁白" ? .secondary : .primary)
                            }
                            .textSelection(.enabled)
                        }
                    }
                }
            } else {
                // 未处理时使用简单正则预览
                let analyzer = CharacterAnalyzer()
                let dialogues = analyzer.detectDialogues(in: customMultiRoleText)
                let simpleMap = buildSimpleSpeakerMap(from: dialogues)

                if simpleMap.isEmpty {
                    Text("未检测到对话标记，将作为旁白整段发送")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(simpleMap.keys.sorted()), id: \.self) { speaker in
                        if let info = simpleMap[speaker] {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(info.isNarrator ? Color.gray : Color.accentColor)
                                    .frame(width: 6, height: 6)
                                Text("\(speaker) → v=\(info.voice)")
                                    .font(.caption2.monospaced())
                            }
                            .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private struct TTSConfigInfo {
        let voice: String
        let rate: Int
        let pitch: Int
        let style: String
        let isNarrator: Bool
    }

    private func buildCustomTTSConfig(from segments: [AISegment]) -> [String: TTSConfigInfo] {
        var map: [String: TTSConfigInfo] = [:]
        let availableVoices = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }
        let defaultVoice = availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
        
        // Collect unique speakers
        let speakers = Set(segments.map { $0.speaker })
        
        // Build character voice map (same logic as synthesizeAndPlayCustom)
        var charVoiceMap: [String: String] = [:]
        for speaker in speakers where speaker != "旁白" {
            if let voiceID = customCharacterVoices[speaker], !voiceID.isEmpty {
                charVoiceMap[speaker] = voiceID
            } else if let matched = availableVoices.first(where: { 
                $0.locale.hasPrefix("zh-CN") 
            }) {
                charVoiceMap[speaker] = matched.id
            }
        }
        let narratorVoice = customCharacterVoices["旁白"] ?? charVoiceMap["旁白"] ?? availableVoices.first(where: { $0.gender == "Female" })?.id ?? defaultVoice

        for speaker in speakers {
            let voice = customCharacterVoices[speaker] ?? charVoiceMap[speaker] ?? {
                if let matched = availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") }) {
                    return matched.id
                }
                return defaultVoice
            }()
            let isNarrator = speaker == "旁白"
            let rate = isNarrator ? 0 + Int(multiRoleGlobalRate) : Int(multiRoleGlobalRate)
            let pitch = 0
            let style = ""
            map[speaker] = TTSConfigInfo(
                voice: voice.isEmpty ? "默认" : voice,
                rate: rate,
                pitch: pitch,
                style: style,
                isNarrator: isNarrator
            )
        }
        // 旁白
        let narratorRate = 0 + Int(multiRoleGlobalRate)
        map["旁白"] = TTSConfigInfo(
            voice: narratorVoice.isEmpty ? "默认" : narratorVoice,
            rate: narratorRate,
            pitch: 0,
            style: "",
            isNarrator: true
        )
        return map
    }

    private struct SegmentPreview {
        let speaker: String
        let text: String
    }

    private func buildSegmentsPreview(from segments: [AISegment]) -> [SegmentPreview] {
        return segments.map { SegmentPreview(speaker: $0.speaker, text: $0.text) }
    }

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

    private func loadWorkerConfigs() async {
        let data = UserDefaults.standard.data(forKey: "aiWorkerConfigs")
        if let data = data,
           let decoded = try? JSONDecoder().decode([AIWorkerConfig].self, from: data) {
            await MainActor.run {
                aiWorkerConfigs = decoded
                if let savedID = UserDefaults.standard.string(forKey: "selectedAIWorkerID"),
                   let id = UUID(uuidString: savedID),
                   aiWorkerConfigs.contains(where: { $0.id == id }) {
                    selectedWorkerID = id
                } else {
                    selectedWorkerID = aiWorkerConfigs.first?.id
                }
            }
        } else if aiWorkerConfigs.isEmpty {
            // Add a default placeholder
            await MainActor.run {
                let defaultConfig = AIWorkerConfig(
                    name: "默认 Worker",
                    baseURL: "https://your-worker.workers.dev",
                    authKey: "your-auth-key-here",
                    model: "qwen-plus",
                    isDefault: true
                )
                aiWorkerConfigs = [defaultConfig]
                selectedWorkerID = defaultConfig.id
                saveWorkerConfigs()
            }
        }
    }

    private func saveWorkerConfigs() {
        if let data = try? JSONEncoder().encode(aiWorkerConfigs) {
            UserDefaults.standard.set(data, forKey: "aiWorkerConfigs")
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

    private func runMultiRoleTest() {
        guard let id = selectedServerID else { return }
        isTestingMultiRole = true
        multiRoleTestResult = ""
        Task {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let total = multiRoleTestScenes.count

            // 1. 合成第 1 段 → 立即入队播放
            let firstScene = multiRoleTestScenes[0]
            do {
                let combinedRate = firstScene.rate + multiRoleGlobalRate
                let combinedPitch = firstScene.pitch
                let audioData = try await EdgeTTSService.shared.synthesize(
                    text: firstScene.text,
                    voice: firstScene.voice,
                    rate: combinedRate,
                    pitch: combinedPitch,
                    style: "",
                    serverID: id
                )
                let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                let url = cachesDir.appendingPathComponent("role-\(firstScene.id.uuidString).\(ext)")
                try audioData.write(to: url, options: .atomic)

                let segment = ScriptSegment(
                    id: firstScene.id,
                    characterName: firstScene.characterName,
                    voice: firstScene.voice,
                    rate: Int(combinedRate),
                    pitch: Int(combinedPitch),
                    style: "",
                    text: firstScene.text,
                    emotionTag: "",
                    paragraphIndex: 0
                )
                let item = TTSQueueItem(
                    segment: segment,
                    audioURL: url,
                    audioData: audioData,
                    chapterTitle: "多角色测试",
                    bookTitle: "测试",
                    bookID: "test",
                    chapterIndex: 0,
                    segmentIndex: 0,
                    totalSegments: total,
                    paragraphIndex: 0,
                    sentenceIndex: nil,
                    anchor: nil
                )
                await MainActor.run {
                    store.audioController.appendToQueue([item])
                    multiRoleTestResult = "第 1 段合成完成，开始播放..."
                }
            } catch {
                await MainActor.run {
                    multiRoleTestResult = "\(firstScene.characterName) 失败: \(error.localizedDescription)"
                    isTestingMultiRole = false
                }
                return
            }

            // 2. 后台合成剩余段 → 一次性入队（播放器会按顺序等待）
            await MainActor.run { multiRoleTestResult = "第 1 段播放中，后续合成中..." }
            var restItems: [TTSQueueItem] = []
            for index in 1..<total {
                let scene = multiRoleTestScenes[index]
                do {
                    let combinedRate = scene.rate + multiRoleGlobalRate
                    let combinedPitch = scene.pitch
                    let audioData = try await EdgeTTSService.shared.synthesize(
                        text: scene.text,
                        voice: scene.voice,
                        rate: combinedRate,
                        pitch: combinedPitch,
                        style: "",
                        serverID: id
                    )
                    let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                    let url = cachesDir.appendingPathComponent("role-\(scene.id.uuidString).\(ext)")
                    try audioData.write(to: url, options: .atomic)

                    let segment = ScriptSegment(
                        id: scene.id,
                        characterName: scene.characterName,
                        voice: scene.voice,
                        rate: Int(combinedRate),
                        pitch: Int(combinedPitch),
                        style: "",
                        text: scene.text,
                        emotionTag: "",
                        paragraphIndex: index
                    )
                    let item = TTSQueueItem(
                        segment: segment,
                        audioURL: url,
                        audioData: audioData,
                        chapterTitle: "多角色测试",
                        bookTitle: "测试",
                        bookID: "test",
                        chapterIndex: 0,
                        segmentIndex: index,
                        totalSegments: total,
                        paragraphIndex: index,
                        sentenceIndex: nil,
                        anchor: nil
                    )
                    restItems.append(item)

                    await MainActor.run {
                        multiRoleTestResult = "已合成 \(index + 1)/\(total) 段，播放中..."
                    }
                } catch {
                    await MainActor.run {
                        multiRoleTestResult = "\(scene.characterName) 失败: \(error.localizedDescription)"
                        isTestingMultiRole = false
                    }
                    return
                }
            }

            // 3. 剩余全部入队
            await MainActor.run {
                store.audioController.appendToQueue(restItems)
                multiRoleTestResult = "\(total)/\(total) 段全部入队，正在流式播放"
                isTestingMultiRole = false
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
