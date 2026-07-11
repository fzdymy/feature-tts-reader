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

// MARK: - Multi-Role Test State
    @State private var isTestingMultiRole = false
    @State private var multiRoleTestResult = ""
    @State private var multiRoleGlobalRate: Double = 0

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
                }
                statusSection
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
            .task {
                await loadServers()
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
                    Text("全局语速").foregroundColor(.secondary).frame(width: 60, alignment: .leading)
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

    private func runMultiRoleTest() {
        guard let id = selectedServerID else { return }
        isTestingMultiRole = true
        multiRoleTestResult = ""
        Task {
            var items: [TTSQueueItem] = []
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let total = multiRoleTestScenes.count

            for (index, scene) in multiRoleTestScenes.enumerated() {
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
                    items.append(item)

                    await MainActor.run {
                        multiRoleTestResult = "已合成 \(index + 1)/\(total) 段，准备播放..."
                    }
                } catch {
                    await MainActor.run {
                        multiRoleTestResult = "\(scene.characterName) 失败: \(error.localizedDescription)"
                        isTestingMultiRole = false
                    }
                    return
                }
            }

            // 批量一次性入队，避免逐个 appendToQueue 竞态
            await MainActor.run {
                store.audioController.appendToQueue(items)
                multiRoleTestResult = "\(items.count)/\(total) 段全部入队，正在流式播放"
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
