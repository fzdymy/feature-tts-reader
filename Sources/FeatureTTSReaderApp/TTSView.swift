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
    @State private var isScanningCharacters = false
    @State private var customScanResult: CharacterScanner.Result?
    @State private var customCharacterVoices: [String: String] = [:] // characterName -> voiceID
    @State private var isSynthesizingCustom = false
    @State private var customSynthesisResult = ""

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
                TextField("粘贴或输入小说文本（自动识别角色、匹配音色、流水合成播放）", text: $customMultiRoleText, axis: .vertical)
                    .font(.body)
                    .lineLimit(4...8)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                // 角色扫描与结果
                if isScanningCharacters {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("正在识别角色...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                } else if let result = customScanResult, !result.characters.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("识别到 \(result.characters.count) 个角色")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)

                        ForEach(result.characters.prefix(10)) { profile in
                            HStack {
                                Text(profile.name)
                                    .font(.subheadline)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { customCharacterVoices[profile.name] ?? "" },
                                    set: { customCharacterVoices[profile.name] = $0 }
                                )) {
                                    Text("自动分配").tag("")
                                    ForEach(availableVoices.filter { $0.locale.hasPrefix("zh-CN") }) { v in
                                        Text(v.displayName).tag(v.id)
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

                // 控制按钮
                VStack(spacing: 8) {
                    Button {
                        scanCustomCharacters()
                    } label: {
                        Label("识别角色并匹配音色", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isScanningCharacters || customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedServerID == nil)

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

    private func scanCustomCharacters() {
        let text = customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isScanningCharacters = true
        customScanResult = nil
        customCharacterVoices.removeAll()
        customSynthesisResult = ""

        Task {
            let config = CharacterScanner.Config(maxResults: 12)
            let result = await CharacterScanner.scan(
                text: text,
                config: config,
                voices: [], // 稍后自动匹配
                defaultSensitivity: 50
            )
            await MainActor.run {
                customScanResult = result
                isScanningCharacters = false
                // 自动为每个角色匹配音色（性别优先）
                var voices: [String: String] = [:]
                for profile in result.characters.prefix(10) {
                    let matchedVoice = availableVoices.first { v in
                        v.locale.hasPrefix("zh-CN") &&
                        (profile.gender == "Male" && v.gender == "Male" || profile.gender == "Female" && v.gender == "Female")
                    } ?? availableVoices.first { $0.locale.hasPrefix("zh-CN") }
                    if let v = matchedVoice {
                        voices[profile.name] = v.id
                    }
                }
                customCharacterVoices = voices
            }
        }
    }

    private func synthesizeAndPlayCustom() {
        guard let id = selectedServerID,
              let result = customScanResult,
              !result.characters.isEmpty else { return }

        isSynthesizingCustom = true
        customSynthesisResult = "正在合成首段..."

        Task {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let text = customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines)
            let characters = result.characters.prefix(10).map { $0.name }

            // 简单分段：按标点分句，按角色名分配
            let sentences = text.split(separator: "。").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let total = sentences.count
            var restItems: [TTSQueueItem] = []

            // 1. 首句立即合成 + 入队
            if let firstSentence = sentences.first {
                let firstChar = characters.first ?? "旁白"
                let voiceID = customCharacterVoices[firstChar] ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
                let rate = multiRoleGlobalRate
                let pitch = 0.0

                do {
                    let audioData = try await EdgeTTSService.shared.synthesize(
                        text: firstSentence + "。",
                        voice: voiceID,
                        rate: rate,
                        pitch: pitch,
                        style: "",
                        serverID: id
                    )
                    let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                    let url = cachesDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                    try audioData.write(to: url, options: .atomic)

                    let segment = ScriptSegment(
                        id: UUID(),
                        characterName: firstChar,
                        voice: voiceID,
                        rate: Int(rate),
                        pitch: Int(pitch),
                        style: "",
                        text: firstSentence + "。",
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
                        totalSegments: total,
                        paragraphIndex: 0,
                        sentenceIndex: nil,
                        anchor: nil
                    )
                    await MainActor.run {
                        store.audioController.appendToQueue([item])
                        customSynthesisResult = "第 1/\(total) 段合成完成，开始播放..."
                    }
                } catch {
                    await MainActor.run {
                        customSynthesisResult = "首段合成失败: \(error.localizedDescription)"
                        isSynthesizingCustom = false
                    }
                    return
                }
            }

            // 2. 后台合成剩余句子
            await MainActor.run { customSynthesisResult = "首句播放中，后台合成剩余 \(total - 1) 段..." }
            for (idx, sentence) in sentences.dropFirst().enumerated() {
                let char = characters[idx % characters.count]
                let voiceID = customCharacterVoices[char] ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
                let rate = multiRoleGlobalRate
                let pitch = 0.0

                do {
                    let audioData = try await EdgeTTSService.shared.synthesize(
                        text: sentence + "。",
                        voice: voiceID,
                        rate: rate,
                        pitch: pitch,
                        style: "",
                        serverID: id
                    )
                    let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                    let url = cachesDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                    try audioData.write(to: url, options: .atomic)

                    let segment = ScriptSegment(
                        id: UUID(),
                        characterName: char,
                        voice: voiceID,
                        rate: Int(rate),
                        pitch: Int(pitch),
                        style: "",
                        text: sentence + "。",
                        emotionTag: "",
                        paragraphIndex: idx + 1
                    )
                    let item = TTSQueueItem(
                        segment: segment,
                        audioURL: url,
                        audioData: audioData,
                        chapterTitle: "自定义多角色",
                        bookTitle: "测试",
                        bookID: "test",
                        chapterIndex: 0,
                        segmentIndex: idx + 1,
                        totalSegments: total,
                        paragraphIndex: idx + 1,
                        sentenceIndex: nil,
                        anchor: nil
                    )
                    restItems.append(item)

                    await MainActor.run {
                        customSynthesisResult = "已合成 \(idx + 2)/\(total) 段..."
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
                customSynthesisResult = "\(total)/\(total) 段全部入队，正在流式播放"
                isSynthesizingCustom = false
            }
        }
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
