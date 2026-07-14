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
    @State private var isLoadingVoices = false

    // MARK: - Multi-Role Test State
    @AppStorage("globalRate") private var multiRoleGlobalRate: Double = 0
    @AppStorage("globalVolume") private var globalVolumeOffset: Double = 0
    @AppStorage("globalOverlap") private var globalOverlapMs: Double = 80

    // MARK: - Custom Multi-Role Test State
    @State private var customMultiRoleText = ""
    @State private var customWorkerSegments: [AISegment] = []
    @State private var customCharacterVoices: [String: String] = [:] // characterName -> voiceID
    @State private var characterAliases: [String: String] = [:] // alias -> mainName (老舅->舅舅)
    @State private var customSynthesisResult = ""
    @State private var isProcessingWorker = false
    @State private var workerProgress: Double = 0
    @State private var workerProgressMessage = ""
    @State private var isSynthesizingCustom = false
    @State private var characterResynthesisStates: [String: Bool] = [:]

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
    @State private var workerStatuses: [UUID: String] = [:]

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
                                Text(serverStatuses[config.id] ?? "未测试")
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

                // 服务器操作按钮
                HStack(spacing: 12) {
                    Button {
                        testAllServers()
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingAll {
                                ProgressView()
                                    .frame(width: 14, height: 14)
                            }
                            Label("全部测试", systemImage: "antenna.radiowaves.left.and.right")
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingAll)

                    Button {
                        Task { await refreshVoices() }
                    } label: {
                        HStack(spacing: 6) {
                            if isLoadingVoices {
                                ProgressView()
                                    .frame(width: 14, height: 14)
                            }
                            Label("语音列表", systemImage: "arrow.clockwise")
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingVoices)
                }
                .padding(.top, 4)
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
                }
                aiWorkerSection
                if selectedServerID != nil {
                    customMultiRoleSection
                }
            }
            .navigationTitle("语音引擎")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                loadVoicesFromCache() // 先显示缓存/兜底
                if let id = selectedServerID {
                    let voices = await EdgeTTSService.shared.fetchVoices(serverID: id)
                    if !voices.isEmpty {
                        await MainActor.run {
                            saveVoicesToCache(voices)
                            loadVoicesFromCache()
                        }
                    }
                }
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
                            HStack {
                                Text(TTSView.shortVoiceLabel(v.id, name: TTSView.chineseVoiceName(for: v.id)))
                                Text(v.gender == "Male" ? "♂" : "♀")
                                    .font(.caption2)
                                    .foregroundColor(v.gender == "Male" ? .blue : .pink)
                            }
                            .tag(v.id)
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
                                ProgressView()
                                    .frame(width: 14, height: 14)
                            }
                            Label("测试连接", systemImage: "antenna.radiowaves.left.and.right")
                                .fixedSize()
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
                                ProgressView()
                                    .frame(width: 14, height: 14)
                            }
                            Label("试听", systemImage: "play.circle")
                                .fixedSize()
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
                        statusDot(workerStatuses[config.id] ?? "未测试")
                            .frame(width: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(config.name)
                                .font(.subheadline.weight(.medium))
                            Text(workerStatuses[config.id] ?? "未测试")
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
                        Button { editingWorkerConfig = config } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button { testWorkerConnection(config) } label: {
                            Label("测试连接", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        Divider()
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
        } header: {
            Label("AI 剧本解析 Worker", systemImage: "brain.head.profile")
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
        workerStatuses.removeValue(forKey: id)
        aiWorkerConfigs.removeAll { $0.id == id }
        if selectedWorkerID == id {
            selectedWorkerID = aiWorkerConfigs.first?.id
        }
        saveWorkerConfigs()
    }

    private func testWorkerConnection(_ config: AIWorkerConfig) {
        workerStatuses[config.id] = "测试中..."
        workerTestResult = "测试中..."
        Task {
            let startTime = Date()
            do {
                _ = try await AIWorkerService.shared.testConnection(config: config)
                let ms = Int(Date().timeIntervalSince(startTime) * 1000)
                await MainActor.run {
                    workerStatuses[config.id] = "就绪 ✓ (\(ms)ms)"
                    workerTestResult = "成功 ✓ (\(ms)ms)"
                }
            } catch {
                let ms = Int(Date().timeIntervalSince(startTime) * 1000)
                await MainActor.run {
                    workerStatuses[config.id] = "失败 (\(ms)ms): \(error.localizedDescription)"
                    workerTestResult = "失败 (\(ms)ms): \(error.localizedDescription)"
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

    private func getDefaultWorkerConfig() -> AIWorkerConfig? {
        return aiWorkerConfigs.first { $0.isDefault } ?? aiWorkerConfigs.first
    }

    // MARK: - Custom Multi-Role Section

    private var customMultiRoleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                TextField("粘贴或输入小说文本（AI Worker 解析角色、情绪、语气、流水合成播放）", text: $customMultiRoleText, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(4...8)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                // 处理状态（不遮盖角色卡）
                if isProcessingWorker || isSynthesizingCustom {
                    VStack(spacing: 8) {
                        ProgressView(value: workerProgress) {
                            Text(workerProgressMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                // 角色卡 — 只要 segments 存在就永远显示，不因合成/播放状态消失
                if !customWorkerSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("解析到 \(customWorkerSegments.count) 个片段，\(Set(customWorkerSegments.map { $0.speaker }).count) 个角色")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)

                        let speakers: [String] = {
                            var freq: [String: Int] = [:]
                            for s in customWorkerSegments {
                                let main = resolveAlias(s.speaker)
                                freq[main, default: 0] += 1
                            }
                            var sorted = freq.keys.sorted { freq[$0, default: 0] > freq[$1, default: 0] }
                            if let idx = sorted.firstIndex(of: "旁白") {
                                sorted.remove(at: idx)
                                sorted.insert("旁白", at: 0)
                            }
                            return sorted
                        }()
                        let allSpeakers = speakers
                        ForEach(speakers.prefix(10), id: \.self) { speaker in
                            let aliases = aliasesOf(speaker)
                            let speakerSegments = customWorkerSegments.filter { aliases.contains($0.speaker) || $0.speaker == speaker }
                            let segmentCount = speakerSegments.count
                            let emotions = speakerSegments.map { $0.emotion }
                            let emotionSummary = Set(emotions).prefix(3).map { $0.chineseLabel }.joined(separator: "、")
let aiGender = speakerSegments.first(where: { $0.gender != .unknown })?.gender
            let resolvedGender = TTSView.resolveGender(speaker: speaker, aiGender: aiGender.map { g in
                switch g {
                case .male: return CharacterGender.male
                case .female: return CharacterGender.female
                case .unknown: return CharacterGender.unknown
                }
            })
            let genderForVoice: Gender = {
                switch resolvedGender {
                case .male: return .male
                case .female: return .female
                case .unknown: return .unknown
                }
            }()
            let autoVoiceID = VoiceMatchUtility.autoMatchVoice(for: speaker, gender: genderForVoice, availableVoices: availableVoices)
                            CharacterRoleCard(
                                speaker: speaker,
                                aliases: aliases,
                                segmentCount: segmentCount,
                                emotionSummary: emotionSummary.isEmpty ? nil : emotionSummary,
                                gender: resolvedGender,
                                autoMatchedVoiceID: autoVoiceID,
                                voiceSelection: Binding(
                                    get: { voiceForSpeaker(speaker) },
                                    set: { customCharacterVoices[speaker] = $0 }
                                ),
                                availableVoices: availableVoices.filter { $0.locale.hasPrefix("zh-CN") },
                                onResynthesize: { resynthesizeCharacter(speaker) },
                                onMerge: { target in mergeCharacter(speaker, into: target) },
                                onSplit: { alias in splitCharacter(alias) },
                                onDelete: { deleteCharacter(speaker) },
                                onRename: { newName in renameCharacter(speaker, to: newName) },
                                otherSpeakers: allSpeakers.filter { $0 != speaker }
                            )
                        }
                    }
                }

                // 说话人分析与发送配置预览
                if !customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customSpeakerAnalysisSection
                }

                // 全局语速、音量滑块
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("语速")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(multiRoleGlobalRate))")
                            .font(.caption.monospaced())
                            .frame(width: 24)
                    }
                    Slider(value: $multiRoleGlobalRate, in: -10...10, step: 1)
                }
                .padding(.vertical, 4)

                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("音量")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(globalVolumeOffset))")
                            .font(.caption.monospaced())
                            .frame(width: 24)
                    }
                    Slider(value: $globalVolumeOffset, in: -10...10, step: 1)
                }
                .padding(.vertical, 4)

                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("重叠(ms)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(globalOverlapMs))")
                            .font(.caption.monospaced())
                            .frame(width: 48)
                    }
                    Slider(value: $globalOverlapMs, in: 0...500, step: 10)
                }
                .padding(.vertical, 4)

                // 控制按钮
                VStack(spacing: 8) {
                    // ① 仅解析
                    Button {
                        parseCustomWithWorker()
                    } label: {
                        HStack {
                            if isProcessingWorker {
                                ProgressView()
                                    .frame(width: 14, height: 14)
                            }
                            Label("解析", systemImage: "brain.head.profile")
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessingWorker || isSynthesizingCustom || customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || getSelectedWorkerConfig() == nil)

                    // ② 流式播放（使用已解析片段 + 角色卡当前音色）
                    Button {
                        synthesizeAndPlayCustom()
                    } label: {
                        HStack {
                            if isSynthesizingCustom {
                                ProgressView()
                                    .frame(width: 14, height: 14)
                            }
                            Label("流式播放", systemImage: "play.circle.fill")
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessingWorker || isSynthesizingCustom || customWorkerSegments.isEmpty || selectedServerID == nil)

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

                    // 播放控制（队列有内容时稳定显示，不闪烁）
                    if store.audioController.queueCount > 0 || store.audioController.isPlaying {
                        HStack {
                            Button {
                                store.audioController.pause()
                            } label: {
                                HStack(spacing: 6) {
                                    Label("暂停", systemImage: "pause.circle.fill")
                                        .fixedSize()
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                store.audioController.resume()
                            } label: {
                                HStack(spacing: 6) {
                                    Label("继续", systemImage: "play.circle.fill")
                                        .fixedSize()
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                store.audioController.stop()
                            } label: {
                                HStack(spacing: 6) {
                                    Label("停止", systemImage: "stop.circle.fill")
                                        .fixedSize()
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // ③ 一站式：AI 解析并流式播放（原合并按钮）
                    Button {
                        processCustomWithWorker()
                    } label: {
                        HStack(spacing: 6) {
                            Label("AI 解析并流式播放", systemImage: "wand.and.stars")
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessingWorker || isSynthesizingCustom || customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || getSelectedWorkerConfig() == nil || selectedServerID == nil)
                }
            }
        } header: {
            Label("自定义多角色测试", systemImage: "text.bubble.fill")
        }
    }

    // MARK: - Actor 并发保序合成缓冲

    private final class SendableStoreRef: @unchecked Sendable {
        weak var controller: AdvancedAudioPlaybackController?
        init(_ controller: AdvancedAudioPlaybackController?) { self.controller = controller }
    }

private actor StatusTracker {
        var isFirst = true
        var hasMarked = false
        func markFirst() -> Bool {
            let wasFirst = isFirst
            isFirst = false
            hasMarked = true
            return wasFirst
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
        isSynthesizingCustom = true
        customWorkerSegments.removeAll()
        customCharacterVoices.removeAll()
        customSynthesisResult = ""
        workerProgress = 0
        workerProgressMessage = "准备中..."

        DebugLogger.log(flow: "custom_multi_role", step: "processCustomWithWorker", details: [
            "original_text_length": text.count,
            "original_text_preview": String(text.prefix(200)),
        ])

        let globalRate = multiRoleGlobalRate
        let globalVolume = globalVolumeOffset
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory

        Task {
            let statusTracker = StatusTracker()

            do {
                let slices = AIWorkerService.shared.sliceText(text, maxChars: workerConfig.sliceCharLimit)
                let totalSlices = slices.count
                var hasVoiceAssignments = false

                for (sliceIdx, slice) in slices.enumerated() {
                    await MainActor.run {
                        workerProgressMessage = "正在解析第 \(sliceIdx + 1)/\(totalSlices) 片..."
                        workerProgress = Double(sliceIdx) / Double(totalSlices)
                    }

                    let request = AIWorkerRequest(
                        text: slice,
                        sliceIndex: sliceIdx,
                        totalSlices: totalSlices,
                        context: nil,
                        focusFromParagraph: nil
                    )
                    let response = try await AIWorkerService.shared.sendRequest(request, config: workerConfig)
                    let segments = response.segments

                    DebugLogger.log(flow: "custom_multi_role", step: "processCustomWithWorker_slice", details: [
                        "slice_index": sliceIdx,
                        "total_slices": totalSlices,
                        "segments_in_slice": segments.count,
                    ])

                    // 合并到全部 segments（用于 UI 展示）
                    await MainActor.run {
                        customWorkerSegments.append(contentsOf: segments)
                    }

                    // 首片时分配音色
                    if !hasVoiceAssignments {
                        await MainActor.run {
                            assignVoicesToSegments(segments)
                        }
                        hasVoiceAssignments = true
                    }

                    // 并发合成 → 流式保序入队（完成一段立刻入队，消除等待停顿）
                    let voices = availableVoices
                    let sRate = globalRate
                    let sVol = globalVolume
                    let sID = serverID
                    let sDir = cachesDir
                    let sIdx = sliceIdx
                    let sCount = segments.count
                    let voiceIDs: [String] = segments.map { seg in
                        let raw = voiceForSpeaker(seg.speaker)
                        return raw.isEmpty ? VoiceMatchUtility.autoMatchVoice(for: seg.speaker, gender: seg.gender, availableVoices: voices) : raw
                    }
                    let audioRef = SendableStoreRef(store.audioController)

                    let buf = SynthesisBuffer { [audioRef] items in
                        await MainActor.run {
                            audioRef.controller?.appendToQueue(items)
                        }
                    }
                    try await withThrowingTaskGroup(of: (Int, TTSQueueItem).self) { group in
                        for (segIdx, segment) in segments.enumerated() {
                            let vID = voiceIDs[segIdx]
                            let segRate = Int(sRate) + Self.rateOffset(for: segment)
                            let segPitch = Self.pitchOffset(for: segment, speakerName: segment.speaker)
                            let segStyle = segment.emotion.ssmlStyle
                            let segVol = Self.resolvedVolume(tone: segment.tone, globalOffset: sVol)
                            group.addTask { [segIdx, segment, vID, segRate, segPitch, segStyle, segVol] in
                                let audioData = try await EdgeTTSService.shared.synthesize(
                                    text: segment.text, voice: vID,
                                    rate: Double(segRate), pitch: Double(segPitch),
                                    style: segStyle, volume: segVol, serverID: sID
                                )
                                let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                                let url = sDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                                try audioData.write(to: url, options: .atomic)

                                let seg = ScriptSegment(
                                    id: UUID(), characterName: segment.speaker,
                                    voice: vID, rate: segRate, pitch: segPitch,
                                    style: segStyle, text: segment.text,
                                    emotionTag: segment.emotion.rawValue, paragraphIndex: sIdx
                                )
                                return (segIdx, TTSQueueItem(
                                    segment: seg, audioURL: url, audioData: audioData,
                                    chapterTitle: "自定义多角色", bookTitle: "测试", bookID: "custom",
                                    chapterIndex: 0, segmentIndex: segIdx,
                                    totalSegments: sCount, paragraphIndex: sIdx,
                                    sentenceIndex: nil, anchor: nil
                                ))
                            }
                        }
                        for try await (idx, item) in group {
                            await buf.insert(idx, item)
                        }
                    }
                    // 流式已在 insert 中完成，此处仅处理剩余（异常情况兜底）
                    await buf.flushRemaining()
                }

                await MainActor.run {
                    customSynthesisResult = "全部入队，正在流式播放"
                    isProcessingWorker = false
                    isSynthesizingCustom = false
                }
            } catch {
                DebugLogger.log(flow: "custom_multi_role", step: "processCustomWithWorker_error", details: [
                    "error": error.localizedDescription,
                ])
                let hadAny = await statusTracker.hasMarked
                await MainActor.run {
                    isProcessingWorker = false
                    isSynthesizingCustom = false
                    workerProgress = 0
                    if hadAny {
                        customSynthesisResult = "部分完成（后续段解析失败）: \(error.localizedDescription)"
                    } else {
                        customSynthesisResult = "解析失败: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    /// 仅解析：调用 AI Worker 逐片解析，填充 customWorkerSegments 并分配音色，不合成不播放
    private func parseCustomWithWorker() {
        let text = customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let workerConfig = getSelectedWorkerConfig() else {
            customSynthesisResult = "请先在设置中配置 AI Worker"
            return
        }

        isProcessingWorker = true
        customWorkerSegments.removeAll()
        customCharacterVoices.removeAll()
        customSynthesisResult = ""
        workerProgress = 0
        workerProgressMessage = "准备解析..."

        DebugLogger.log(flow: "custom_multi_role", step: "parseCustomWithWorker_start", details: [
            "original_text_length": text.count,
            "original_text_preview": String(text.prefix(200)),
        ])

        Task {
            do {
                let slices = AIWorkerService.shared.sliceText(text, maxChars: workerConfig.sliceCharLimit)
                let totalSlices = slices.count
                var hasVoiceAssignments = false
                var remainingText = text
                var context: String? = nil

                for (sliceIdx, slice) in slices.enumerated() {
                    await MainActor.run {
                        workerProgressMessage = "正在解析第 \(sliceIdx + 1)/\(totalSlices) 片..."
                        workerProgress = Double(sliceIdx) / Double(totalSlices)
                    }

                    var retryCount = 0
                    let maxRetries = 2
                    var segments: [AISegment] = []

                    while retryCount <= maxRetries {
                        let request = AIWorkerRequest(
                            text: slice,
                            sliceIndex: sliceIdx,
                            totalSlices: totalSlices,
                            context: context,
                            focusFromParagraph: nil
                        )
                        let response = try await AIWorkerService.shared.sendRequest(request, config: workerConfig)
                        segments = response.segments

                        // 检查结果是否完整：最后一段以标点结尾，且段落数合理
                        let isComplete = isResultComplete(segments, originalText: slice)
                        if isComplete || retryCount == maxRetries {
                            break
                        }

                        // 不完整：用剩余文本重试
                        if let lastSeg = segments.last,
                           let range = slice.range(of: lastSeg.text) {
                            let consumed = slice[..<range.upperBound]
                            remainingText = String(slice[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            context = "已解析：\(consumed.prefix(200))"
                            DebugLogger.log(flow: "custom_multi_role", step: "parse_retry", details: [
                                "slice_index": sliceIdx,
                                "retry": retryCount + 1,
                                "remaining_length": remainingText.count,
                            ])
                        }
                        retryCount += 1
                    }

                    DebugLogger.log(flow: "custom_multi_role", step: "parseCustomWithWorker_slice", details: [
                        "slice_index": sliceIdx,
                        "total_slices": totalSlices,
                        "segments_in_slice": segments.count,
                        "retries": retryCount,
                    ])

                    await MainActor.run {
                        customWorkerSegments.append(contentsOf: segments)
                        if !hasVoiceAssignments {
                            assignVoicesToSegments(segments)
                            hasVoiceAssignments = true
                        } else {
                            assignVoicesToSegments(segments)
                        }
                        customSynthesisResult = "已解析 \(customWorkerSegments.count) 段，\(Set(customWorkerSegments.map { $0.speaker }).count) 个角色"
                    }
                }

                await MainActor.run {
                    workerProgress = 1
                    isProcessingWorker = false
                    customSynthesisResult = "解析完成：\(customWorkerSegments.count) 段，\(Set(customWorkerSegments.map { $0.speaker }).count) 个角色，可调整音色后播放"
                }
                DebugLogger.log(flow: "custom_multi_role", step: "parseCustomWithWorker_complete", details: [
                    "total_segments": customWorkerSegments.count,
                ])
            } catch {
                DebugLogger.log(flow: "custom_multi_role", step: "parseCustomWithWorker_error", details: [
                    "error": error.localizedDescription,
                ])
                await MainActor.run {
                    isProcessingWorker = false
                    workerProgress = 0
                    customSynthesisResult = "解析失败: \(error.localizedDescription)"
                }
            }
        }
    }

    /// 判断 AI Worker 返回结果是否完整
    private func isResultComplete(_ segments: [AISegment], originalText: String) -> Bool {
        guard let last = segments.last else { return false }
        let lastText = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 以中文/英文标点结尾视为完整
        let endsWithPunct = lastText.last.map { "。！？.!?".contains($0) } ?? false
        // 段落数过少也可能不完整（简单启发式）
        return endsWithPunct && segments.count >= 2
    }

    private func assignVoicesToSegments(_ segments: [AISegment]) {
        let mainSpeakers = Array(Set(segments.map { resolveAlias($0.speaker) })).sorted()
        let zhVoices = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }
        let voicesPool = zhVoices.isEmpty ? Self.defaultChineseVoices : zhVoices

        let femaleVoices = voicesPool.filter { $0.gender == "Female" }
        let maleVoices = voicesPool.filter { $0.gender == "Male" }
        var femaleIdx = 0, maleIdx = 0, neutralIdx = 0
        let neutralVoices = voicesPool

        // 优先采用 AI 返回的 gender（取该主角色首个非 unknown 的性别）
        var speakerGender: [String: Gender] = [:]
        for seg in segments where seg.gender != .unknown {
            let mainName = resolveAlias(seg.speaker)
            if speakerGender[mainName] == nil {
                speakerGender[mainName] = seg.gender
            }
        }

        // 清除别名的音色映射（别名继承主角色的音色）
        var voices = customCharacterVoices
        for alias in characterAliases.keys {
            voices.removeValue(forKey: alias)
        }

        for speaker in mainSpeakers {
            if let existing = customCharacterVoices[speaker], !existing.isEmpty {
                voices[speaker] = existing
                continue
            }

            let gender = TTSView.resolveGender(speaker: speaker, aiGender: speakerGender[speaker].map { (g: Gender) -> CharacterGender in
                switch g {
                case .male: return CharacterGender.male
                case .female: return CharacterGender.female
                case .unknown: return CharacterGender.unknown
                }
            })

            switch gender {
            case .female where !femaleVoices.isEmpty:
                voices[speaker] = femaleVoices[femaleIdx % femaleVoices.count].id
                femaleIdx += 1
            case .male where !maleVoices.isEmpty:
                voices[speaker] = maleVoices[maleIdx % maleVoices.count].id
                maleIdx += 1
            default:
                voices[speaker] = neutralVoices[neutralIdx % neutralVoices.count].id
                neutralIdx += 1
            }
        }
        customCharacterVoices = voices
    }

    /// 默认中文音色（服务器 voices 为空时的兜底，覆盖全部 Azure zh-CN 音色）
    private nonisolated(unsafe) static let defaultChineseVoices: [EdgeVoiceInfo] = [
        EdgeVoiceInfo(id: "zh-CN-XiaoxiaoNeural", name: "小晓", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaochenNeural", name: "晓辰", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaohanNeural", name: "晓涵", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaomengNeural", name: "晓萌", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaomoNeural", name: "晓墨", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaoruiNeural", name: "晓睿", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaoshuangNeural", name: "晓双", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaoxuanNeural", name: "晓萱", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaoyanNeural", name: "晓颜", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaoyiNeural", name: "晓伊", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaozhenNeural", name: "晓臻", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunxiNeural", name: "云希", gender: "Male", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunyangNeural", name: "云扬", gender: "Male", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunyeNeural", name: "云野", gender: "Male", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunfengNeural", name: "云峰", gender: "Male", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunjianNeural", name: "云健", gender: "Male", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunxiaNeural", name: "云夏", gender: "Male", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunzeNeural", name: "云泽", gender: "Male", locale: "zh-CN"),
    ]

    /// 去除服务器追加的后缀（zh-CN-Yunfan:DragonHDLatestNeural → zh-CN-Yunfan）
    /// 标准化音色 ID 基名（剥离服务器后缀 :DragonHD... 及 Neural 尾缀）
    static nonisolated func baseVoiceID(_ id: String) -> String {
        var base = id
        if let colon = id.firstIndex(of: ":") { base = String(id[..<colon]) }
        if base.hasSuffix("Neural") { base = String(base.dropLast(6)) }
        return base
    }

    /// 提取服务器模型后缀（如 :DragonHDFlashLatestNeural → :DragonHD）
    static nonisolated func shortModelSuffix(_ id: String) -> String {
        guard let colon = id.firstIndex(of: ":") else { return "" }
        var suffix = String(id[id.index(after: colon)...])
        for strip in ["FlashLatestNeural", "LatestNeural", "FlashLatest", "Latest", "Neural"] {
            guard suffix.hasSuffix(strip) else { continue }
            suffix = String(suffix.dropLast(strip.count))
            break
        }
        return ":\(suffix)"
    }

    /// 音色显示标签：中文名/英文短名:模型后缀（如 晓晓/Xiaoxiao:DragonHD）
    static nonisolated func shortVoiceLabel(_ id: String, name: String) -> String {
        let base = baseVoiceID(id)
        let engName = base
            .replacingOccurrences(of: "zh-CN-", with: "")
            .replacingOccurrences(of: "zh-HK-", with: "")
            .replacingOccurrences(of: "zh-TW-", with: "")
        let suffix = shortModelSuffix(id)
        return "\(name)/\(engName)\(suffix)"
    }

    /// 拼音 → 中文名映射（不含 Neural 尾缀，baseVoiceID 已自动剥离）
    static nonisolated func chineseVoiceName(for voiceID: String) -> String {
        let base = baseVoiceID(voiceID)
        let map: [String: String] = [
            // zh-CN 女声
            "zh-CN-Xiaoxiao": "小晓", "zh-CN-Xiaochen": "晓辰",
            "zh-CN-Xiaohan": "晓涵", "zh-CN-Xiaomo": "晓墨",
            "zh-CN-Xiaomeng": "晓萌", "zh-CN-Xiaorui": "晓睿",
            "zh-CN-Xiaoshuang": "晓双", "zh-CN-Xiaoxuan": "晓萱",
            "zh-CN-Xiaoyan": "晓颜", "zh-CN-Xiaoyi": "晓伊",
            "zh-CN-Xiaozhen": "晓臻", "zh-CN-Xiaoyu": "晓雨",
            // zh-CN 男声
            "zh-CN-Yunxi": "云希", "zh-CN-Yunyang": "云扬",
            "zh-CN-Yunye": "云野", "zh-CN-Yunjian": "云健",
            "zh-CN-Yunfeng": "云峰", "zh-CN-Yunxia": "云夏",
            "zh-CN-Yunze": "云泽", "zh-CN-Yunhao": "云皓",
            "zh-CN-Yunqi": "云奇", "zh-CN-Yunyi": "云逸",
            "zh-CN-Yunxiao": "云霄", "zh-CN-Yunjia": "云嘉",
            // 方言
            "zh-CN-henan-Yundeng": "云登",
            "zh-CN-shaanxi-Xiaoni": "晓妮",
            "zh-CN-sichuan-Xiaomo": "晓墨",
            "zh-CN-sichuan-Yunxi": "云希",
            // 粤语
            "zh-HK-HiuGaai": "晓佳", "zh-HK-HiuMaan": "晓曼",
            "zh-HK-WanLung": "云龙",
            // 台语
            "zh-TW-HsiaoChen": "晓臻", "zh-TW-HsiaoYu": "晓雨",
            "zh-TW-YunJhe": "云哲",
        ]
        return map[base] ?? base
    }

    /// 根据说话人自动匹配音色（基于性别，优先从 zh-CN 女声/男声中选择）
    /// - Note: Deprecated — use `VoiceMatchUtility.autoMatchVoice` instead.
    static nonisolated func autoMatchVoice(for speaker: String, gender: CharacterGender, availableVoices: [EdgeVoiceInfo]) -> String {
        let zhVoices = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }
        let voices = zhVoices.isEmpty ? defaultChineseVoices : zhVoices
        let resolved: CharacterGender = {
            if gender != .unknown { return gender }
            return TTSView.resolveGender(speaker: speaker, aiGender: nil)
        }()
        switch resolved {
        case .female:
            let f = voices.filter { $0.gender == "Female" }
            return f.first?.id ?? voices.first?.id ?? "zh-CN-XiaoxiaoNeural"
        case .male:
            let m = voices.filter { $0.gender == "Male" }
            return m.first?.id ?? voices.first?.id ?? "zh-CN-YunxiNeural"
        case .unknown:
            return voices.first?.id ?? "zh-CN-XiaoxiaoNeural"
        }
    }

    /// 解析别名 → 主名（最多 5 层，防循环）
    private func resolveAlias(_ name: String) -> String {
        var current = name
        var visited = Set<String>()
        var depth = 0
        while let next = characterAliases[current], next != current, !visited.contains(current), depth < 5 {
            visited.insert(current)
            current = next
            depth += 1
        }
        return current
    }

    /// 获取说话人的音色（别名自动继承主角色的音色）
    private func voiceForSpeaker(_ speaker: String) -> String {
        if let v = customCharacterVoices[speaker], !v.isEmpty { return v }
        if let main = characterAliases[speaker], let v = customCharacterVoices[main], !v.isEmpty { return v }
        return ""
    }

    /// 获取某主角色下的所有别名
    private func aliasesOf(_ mainName: String) -> [String] {
        characterAliases.filter { $0.value == mainName }.map(\.key).sorted()
    }

    /// 角色操作：合并（将 source 标记为 target 的别名）
    private func mergeCharacter(_ source: String, into target: String) {
        guard source != target, !source.isEmpty, !target.isEmpty else { return }
        guard characterAliases[target] == nil else { return } // target 不能是别名
        // 如果 source 本身是某个角色的别名，先解除
        characterAliases.removeValue(forKey: source)
        // source 已有的别名也转向 target
        let sourceAliases = characterAliases.filter { $0.value == source }.map(\.key)
        for alias in sourceAliases {
            characterAliases[alias] = target
        }
        // 设置别名映射
        characterAliases[source] = target
        // 音色：如果 source 有自定义音色而 target 没有，继承
        if let sv = customCharacterVoices[source], !sv.isEmpty {
            if customCharacterVoices[target] == nil || customCharacterVoices[target]?.isEmpty == true {
                customCharacterVoices[target] = sv
            }
            customCharacterVoices.removeValue(forKey: source)
        }
    }

    /// 角色操作：分离别名（恢复为独立角色）
    private func splitCharacter(_ alias: String) {
        characterAliases.removeValue(forKey: alias)
    }

    /// 角色操作：删除角色及其所有片段
    private func deleteCharacter(_ speaker: String) {
        // 如果 speaker 本身是别名，先移除别名映射
        if characterAliases[speaker] != nil {
            characterAliases.removeValue(forKey: speaker)
        }
        customWorkerSegments.removeAll { resolveAlias($0.speaker) == speaker }
        customCharacterVoices.removeValue(forKey: speaker)
        // 收集映射到 speaker 的别名键，避免枚举时突变
        let aliasesToRemove = characterAliases.filter { $0.value == speaker }.map(\.key)
        for alias in aliasesToRemove {
            characterAliases.removeValue(forKey: alias)
        }
    }

    /// 角色操作：重命名角色
    private func renameCharacter(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName, characterAliases[trimmed] == nil else { return }
        // 重命名别名映射中的键
        if characterAliases[oldName] != nil {
            characterAliases[trimmed] = characterAliases.removeValue(forKey: oldName)
        }
        // 重命名别名映射中的值（主角色名）—— 先收集再赋值
        let aliasesToUpdate = characterAliases.filter { $0.value == oldName }.map(\.key)
        for alias in aliasesToUpdate {
            characterAliases[alias] = trimmed
        }
        // 重命名片段中的说话人
        for i in customWorkerSegments.indices where customWorkerSegments[i].speaker == oldName {
            let seg = customWorkerSegments[i]
            customWorkerSegments[i] = AISegment(speaker: trimmed, emotion: seg.emotion, tone: seg.tone, text: seg.text, gender: seg.gender)
        }
        if let voice = customCharacterVoices[oldName] {
            customCharacterVoices[trimmed] = voice
            customCharacterVoices.removeValue(forKey: oldName)
        }
    }

    /// 合并同一角色连续段落（相同 speaker、emotion、tone 视为可合并）
    private func mergeConsecutiveSegments(_ segments: [AISegment]) -> [AISegment] {
        guard !segments.isEmpty else { return segments }
        var merged: [AISegment] = []
        var current = segments[0]
        for seg in segments.dropFirst() {
            if seg.speaker == current.speaker &&
               seg.emotion == current.emotion &&
               seg.tone == current.tone {
                // 合并文本（用句号连接，避免粘连）
                let sep = current.text.hasSuffix("。") || current.text.hasSuffix("。") || current.text.hasSuffix("？") || current.text.hasSuffix("！") ? "" : "。"
                current = AISegment(
                    speaker: current.speaker,
                    emotion: current.emotion,
                    tone: current.tone,
                    text: current.text + sep + seg.text,
                    gender: current.gender
                )
            } else {
                merged.append(current)
                current = seg
            }
        }
        merged.append(current)
        return merged
    }

    /// 综合 AI gender 与名字关键词判定性别（AI 优先，unknown 时回退关键词）
    static nonisolated func resolveGender(speaker: String, aiGender: CharacterGender?) -> CharacterGender {
        if let g = aiGender, g != .unknown { return g }
        let isFemale = speaker.contains("女") || speaker.contains("小姐") || speaker.contains("姑娘") || speaker.contains("她") || speaker.contains("姐") || speaker.contains("娘") || speaker.contains("妈") || speaker.contains("婆") || speaker.contains("奶") || speaker.contains("妹") || speaker.contains("嫂") || speaker.contains("婶") || speaker.contains("女士") || speaker.contains("太太") || speaker.contains("夫人")
        let isMale = speaker.contains("公") || speaker.contains("哥") || speaker.contains("爷") || speaker.contains("兄") || speaker.contains("他") || speaker.contains("叔") || speaker.contains("爸") || speaker.contains("父") || speaker.contains("先生") || speaker.contains("少爷") || speaker.contains("公子") || speaker.contains("郎") || speaker.contains("伯") || speaker.contains("舅")
        if isFemale { return .female }
        if isMale { return .male }
        return .unknown
    }

    /// 根据情绪和角色名计算语速偏移
    static nonisolated func rateOffset(for segment: AISegment, preferredRate: Double? = nil) -> Int {
        var offset = 0
        switch segment.emotion {
        case .angry, .shouting, .excited: offset += 4
        case .happy, .cheerful, .surprised: offset += 2
        case .sad, .fearful, .whispering, .calm, .gentle: offset -= 2
        default: break
        }
        if let pr = preferredRate { offset += Int(pr.rounded()) }
        return offset
    }

    /// 根据 tone 关键词推导基准音量(dB)，叠加全局滑块偏移，输出 SSML 兼容 dB 值
    static nonisolated func resolvedVolume(tone: String, globalOffset: Double) -> String {
        let t = tone
        let baseDb: Double
        if t.contains("大喊") || t.contains("怒吼") || t.contains("咆哮") || t.contains("吼叫") || t.contains("大喝") || t.contains("厉喝") || t.contains("怒喝") || t.contains("厉声") || t.contains("怒声") || t.contains("高喝") {
            baseDb = 8
        } else if t.contains("喊") || t.contains("叫") || t.contains("嚷") || t.contains("喝令") {
            baseDb = 4
        } else if t.contains("低语") || t.contains("轻声") || t.contains("悄悄") || t.contains("小声") || t.contains("窃窃") || t.contains("低喃") || t.contains("低声道") || t.contains("低声") || t.contains("沉吟") {
            baseDb = -4
        } else if t.contains("耳语") || t.contains("气声") || t.contains("呢喃") || t.contains("默念") || t.contains("无声") {
            baseDb = -8
        } else {
            baseDb = 0
        }
        // 全局滑块每步 0.5dB，叠加到基准音量上
        let total = baseDb + globalOffset * 0.5
        return String(format: "%+.1fdB", total)
    }

    /// 根据情绪和角色名计算音调偏移
    static nonisolated func pitchOffset(for segment: AISegment, speakerName: String, preferredPitch: Double? = nil) -> Int {
        let gender = resolveGender(speaker: speakerName, aiGender: Optional(segment.gender).map { g in
            switch g {
            case .male: return CharacterGender.male
            case .female: return CharacterGender.female
            case .unknown: return CharacterGender.unknown
            }
        })
        let genderOffset: Int = {
            switch gender {
            case .female: return 4
            case .male: return -2
            case .unknown: return speakerName == "旁白" ? 0 : -2
            }
        }()
        let emotionOffset: Int = {
            switch segment.emotion {
            case .excited, .happy, .cheerful: return 3
            case .surprised: return 5
            case .sad, .fearful, .whispering, .calm: return -2
            case .angry, .shouting: return 2
            default: return 0
            }
        }()
        var offset = genderOffset + emotionOffset
        if let pp = preferredPitch { offset += Int(pp.rounded()) }
        return offset
    }

    private func synthesizeAndPlayCustom() {
        guard let serverID = selectedServerID,
              !customWorkerSegments.isEmpty else {
            isSynthesizingCustom = false
            return
        }

        isSynthesizingCustom = true
        customSynthesisResult = "正在并发合成..."

        // 合并同一角色连续段落（相同 speaker、emotion、tone 视为可合并）
        let mergedSegments = mergeConsecutiveSegments(customWorkerSegments)

        DebugLogger.log(flow: "custom_synthesize", step: "start", details: [
            "original_segments": customWorkerSegments.count,
            "merged_segments": mergedSegments.count,
            "reduction": customWorkerSegments.count - mergedSegments.count,
            "segments": mergedSegments.map { s in
                ["speaker": s.speaker, "emotion": s.emotion.rawValue, "tone": s.tone, "text_preview": String(s.text.prefix(80))]
            },
            "character_voices": customCharacterVoices.mapValues { $0 },
        ])

        Task {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let globalRate = multiRoleGlobalRate
            let globalVolume = globalVolumeOffset

            let allSegments = mergedSegments
            let voices = availableVoices
            let sID = serverID
            let sDir = cachesDir
            let totalCount = allSegments.count
            let voiceIDs: [String] = allSegments.map { seg in
                let raw = voiceForSpeaker(seg.speaker)
                let cg: CharacterGender = {
                    switch seg.gender {
                    case .male: return CharacterGender.male
                    case .female: return CharacterGender.female
                    case .unknown: return CharacterGender.unknown
                    }
                }()
                return raw.isEmpty ? Self.autoMatchVoice(for: seg.speaker, gender: cg, availableVoices: voices) : raw
            }
            let audioRef = SendableStoreRef(store.audioController)

            let synthBuf = SynthesisBuffer { [audioRef] items in
                await MainActor.run {
                    audioRef.controller?.appendToQueue(items)
                }
            }

            do {
                try await withThrowingTaskGroup(of: (Int, Result<TTSQueueItem, Error>).self) { group in
                    for (idx, segment) in allSegments.enumerated() {
                        let vID = voiceIDs[idx]
                        let segRate = Int(globalRate) + Self.rateOffset(for: segment)
                        let segPitch = Self.pitchOffset(for: segment, speakerName: segment.speaker)
                        let segStyle = segment.emotion.ssmlStyle
                        let segVol = TTSView.resolvedVolume(tone: segment.tone, globalOffset: globalVolume)
                        group.addTask { [idx, segment, vID, segRate, segPitch, segStyle, segVol] in
                            do {
                                let audioData = try await EdgeTTSService.shared.synthesize(
                                    text: segment.text, voice: vID,
                                    rate: Double(segRate), pitch: Double(segPitch),
                                    style: segStyle, volume: segVol, serverID: sID
                                )
                                let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                                let url = sDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                                try audioData.write(to: url, options: .atomic)
                                let seg = ScriptSegment(
                                    id: UUID(), characterName: segment.speaker,
                                    voice: vID, rate: segRate, pitch: segPitch,
                                    style: segStyle, text: segment.text,
                                    emotionTag: segment.emotion.rawValue, paragraphIndex: idx
                                )
                                return (idx, .success(TTSQueueItem(
                                    segment: seg, audioURL: url, audioData: audioData,
                                    chapterTitle: "自定义多角色", bookTitle: "测试", bookID: "custom",
                                    chapterIndex: 0, segmentIndex: idx,
                                    totalSegments: totalCount,
                                    paragraphIndex: idx, sentenceIndex: nil, anchor: nil
                                )))
                            } catch {
                                return (idx, .failure(error))
                            }
                        }
                    }
                    for try await (idx, result) in group {
                        switch result {
                        case .success(let item):
                            await synthBuf.insert(idx, item)
                        case .failure(let error):
                            DebugLogger.log(flow: "custom_synthesize", step: "segment_error", details: [
                                "segment_index": idx, "error": error.localizedDescription,
                            ])
                        }
                    }
                }

                await synthBuf.flushRemaining()
                let totalSuccess = await synthBuf.flushedCount

                await MainActor.run {
                    isSynthesizingCustom = false
                    customSynthesisResult = "\(totalSuccess)/\(totalCount) 段全部入队，正在流式播放"
                }
                DebugLogger.log(flow: "custom_synthesize", step: "complete", details: [
                    "total_segments": totalCount,
                    "successful_items": totalSuccess,
                ])
            } catch {
                DebugLogger.log(flow: "custom_synthesize", step: "error", details: [
                    "error": error.localizedDescription,
                ])
                await MainActor.run {
                    isSynthesizingCustom = false
                    customSynthesisResult = "合成失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func resynthesizeCharacter(_ speaker: String) {
        guard let serverID = selectedServerID else { return }
        let segments = customWorkerSegments.filter { resolveAlias($0.speaker) == speaker }
        guard !segments.isEmpty else { return }

        characterResynthesisStates[speaker] = true
        // 先自动匹配音色（如果当前为空或为"自动"），再合成
        let currentVoice = voiceForSpeaker(speaker)
        let autoVoice = VoiceMatchUtility.autoMatchVoice(for: speaker, gender: segments.first?.gender ?? .unknown, availableVoices: availableVoices)
        let resolvedVoice = currentVoice.isEmpty ? autoVoice : currentVoice
        if resolvedVoice != currentVoice {
            customCharacterVoices[speaker] = resolvedVoice
        }
        let globalRate = multiRoleGlobalRate
        let globalVolume = globalVolumeOffset

        DebugLogger.log(flow: "custom_synthesize", step: "character_resynthesis_start", details: [
                        "speaker": speaker,
                        "segments": segments.count,
                        "voice": resolvedVoice,
                        "auto_matched": resolvedVoice != currentVoice,
                    ])

        Task {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            var items: [TTSQueueItem] = []

            for (idx, segment) in segments.enumerated() {
                let rate = Int(globalRate) + Self.rateOffset(for: segment)
                let pitch = Self.pitchOffset(for: segment, speakerName: speaker)
                let style = segment.emotion.ssmlStyle
                let volume = TTSView.resolvedVolume(tone: segment.tone, globalOffset: globalVolume)

                do {
                    let audioData = try await EdgeTTSService.shared.synthesize(
                        text: segment.text,
                        voice: resolvedVoice,
                        rate: Double(rate),
                        pitch: Double(pitch),
                        style: style,
                        volume: volume,
                        serverID: serverID
                    )
                    let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                    let url = cachesDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                    try audioData.write(to: url, options: .atomic)

                    let seg = ScriptSegment(
                        id: UUID(),
                        characterName: segment.speaker,
                        voice: resolvedVoice,
                        rate: rate,
                        pitch: pitch,
                        style: style,
                        text: segment.text,
                        emotionTag: segment.emotion.rawValue,
                        paragraphIndex: 0
                    )
                    items.append(TTSQueueItem(
                        segment: seg,
                        audioURL: url,
                        audioData: audioData,
                        chapterTitle: "重新适配",
                        bookTitle: "测试",
                        bookID: "custom",
                        chapterIndex: 0,
                        segmentIndex: idx,
                        totalSegments: segments.count,
                        paragraphIndex: idx,
                        sentenceIndex: nil,
                        anchor: nil
                    ))
                } catch {
                    await MainActor.run {
                        customSynthesisResult = "「\(speaker)」重新适配失败: \(error.localizedDescription)"
                    }
                }
            }

            await MainActor.run {
                store.audioController.appendToQueue(items)
                customSynthesisResult = "「\(speaker)」\(items.count) 段已入队"
                characterResynthesisStates[speaker] = false
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

    private func buildSimpleSpeakerMap(from dialogues: [DialogueMatch]) -> [String: TTSConfigInfo] {
        var map: [String: TTSConfigInfo] = [:]
        for dialogue in dialogues {
            let speaker = dialogue.speaker ?? "旁白"
            guard map[speaker] == nil else { continue }
            let isNarrator = speaker == "旁白"
            let hasFemaleIndicators = speaker.contains("女") || speaker.contains("小姐") || speaker.contains("姑娘")
            let voice = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }.first?.id ?? ""
            map[speaker] = TTSConfigInfo(
                voice: voice,
                rate: isNarrator ? 0 : 2,
                pitch: hasFemaleIndicators ? 3 : 0,
                style: "neutral",
                isNarrator: isNarrator
            )
        }
        return map
    }

    private func buildCustomTTSConfig(from segments: [AISegment]) -> [String: TTSConfigInfo] {
        var map: [String: TTSConfigInfo] = [:]
        let availableVoices = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }
        let defaultVoice = availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""

        // 通过 resolveAlias 合并别名到主角色
        let speakers = Set(segments.map { resolveAlias($0.speaker) })

        // Build character voice map
        var charVoiceMap: [String: String] = [:]
        for speaker in speakers where speaker != "旁白" {
            let v = voiceForSpeaker(speaker)
            if !v.isEmpty {
                charVoiceMap[speaker] = v
            } else if let matched = availableVoices.first(where: {
                $0.locale.hasPrefix("zh-CN")
            }) {
                charVoiceMap[speaker] = matched.id
            }
        }
        let narratorVoice = voiceForSpeaker("旁白").isEmpty
            ? (charVoiceMap["旁白"] ?? availableVoices.first(where: { $0.gender == "Female" })?.id ?? defaultVoice)
            : voiceForSpeaker("旁白")

        for speaker in speakers {
            let voice: String = {
                let v = voiceForSpeaker(speaker)
                if !v.isEmpty { return v }
                if let cm = charVoiceMap[speaker], !cm.isEmpty { return cm }
                if let matched = availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") }) { return matched.id }
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
                for w in aiWorkerConfigs {
                    workerStatuses[w.id] = "未测试"
                }
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
                workerStatuses[defaultConfig.id] = "未测试"
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

    private func loadVoicesFromCache() {
        let cacheKey = "cachedVoices"
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? decoder.decode([EdgeVoiceInfo].self, from: data), !cached.isEmpty {
            availableVoices = cached
        } else {
            // 服务器 voices 为空时使用默认中文音色兜底
            availableVoices = Self.defaultChineseVoices
        }
        if testVoice.isEmpty || !availableVoices.contains(where: { $0.id == testVoice }) {
            testVoice = availableVoices.first?.id ?? ""
        }
    }

    private func saveVoicesToCache(_ voices: [EdgeVoiceInfo]) {
        let cacheKey = "cachedVoices"
        let zhVoices = voices.filter { $0.locale.hasPrefix("zh-CN") }
        if let data = try? JSONEncoder().encode(zhVoices) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func refreshVoices() async {
        guard let id = selectedServerID else { return }
        isLoadingVoices = true
        let voices = await EdgeTTSService.shared.fetchVoices(serverID: id)
        await MainActor.run {
            saveVoicesToCache(voices)
            loadVoicesFromCache()
            isLoadingVoices = false
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

// MARK: - Worker Edit Sheet

struct WorkerEditView: View {
    @Environment(\.dismiss) private var dismiss

    let existingID: UUID?
    @State private var name: String
    @State private var baseURL: String
    @State private var authKey: String
    @State private var sliceCharLimit: Int
    @State private var timeout: Double
    let onSave: (AIWorkerConfig) -> Void

    init(config: AIWorkerConfig? = nil, onSave: @escaping (AIWorkerConfig) -> Void) {
        self.existingID = config?.id
        _name = State(initialValue: config?.name ?? "")
        _baseURL = State(initialValue: config?.baseURL ?? "")
        _authKey = State(initialValue: config?.authKey ?? "")
        _sliceCharLimit = State(initialValue: config?.sliceCharLimit ?? 1000)
        _timeout = State(initialValue: config?.timeout ?? 30)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("名称") {
                        TextField("例如：我的 AI Worker", text: $name)
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
                    HStack {
                        Text("模型").foregroundColor(.secondary)
                        Spacer()
                        Text("qwen-2.5-7b-instruct (在 Worker 中固定)")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                            model: "qwen-2.5-7b-instruct",
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

private extension CharacterSet {
    static let urlQueryParameterAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove("&")
        allowed.remove("+")
        return allowed
    }()
}
