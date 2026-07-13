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
                loadVoicesFromCache()
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
                        let allSpeakers = speakers  // 完整的角色列表（用于合并菜单）
                        ForEach(speakers.prefix(10), id: \.self) { speaker in
                            let aliases = aliasesOf(speaker)
                            let speakerSegments = customWorkerSegments.filter { aliases.contains($0.speaker) || $0.speaker == speaker }
                            let segmentCount = speakerSegments.count
                            let emotions = speakerSegments.map { $0.emotion }
                            let emotionSummary = Set(emotions).prefix(3).map { $0.chineseLabel }.joined(separator: "、")
                            let aiGender = speakerSegments.first(where: { $0.gender != .unknown })?.gender
                            let resolvedGender = TTSView.resolveGender(speaker: speaker, aiGender: aiGender)
                            let autoVoiceID = TTSView.autoMatchVoice(for: speaker, gender: resolvedGender, availableVoices: availableVoices)
                            CharacterRoleCard(
                                speaker: speaker,
                                aliases: aliases,
                                segmentCount: segmentCount,
                                emotionSummary: emotionSummary.isEmpty ? nil : emotionSummary,
                                gender: resolvedGender,
                                autoMatchedVoiceID: autoVoiceID,
                                voice: Binding(
                                    get: { voiceForSpeaker(speaker) },
                                    set: { customCharacterVoices[speaker] = $0 }
                                ),
                                isResynthesizing: characterResynthesisStates[speaker] ?? false,
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
            var firstSegmentPlayed = false

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
                        context: nil
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

                    // 逐段合成 → 逐段入队（真正的流式）
                    for (segIdx, segment) in segments.enumerated() {
                        let voiceID = await MainActor.run {
                            voiceForSpeaker(segment.speaker)
                        }
                        let rate = Int(globalRate) + TTSView.rateOffset(for: segment)
                        let pitch = TTSView.pitchOffset(for: segment, speakerName: segment.speaker)
                        let style = segment.emotion.ssmlStyle
                        let volume = TTSView.resolvedVolume(tone: segment.tone, globalOffset: globalVolume)

                        let audioData = try await EdgeTTSService.shared.synthesize(
                            text: segment.text,
                            voice: voiceID,
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
                            voice: voiceID,
                            rate: rate,
                            pitch: pitch,
                            style: style,
                            text: segment.text,
                            emotionTag: segment.emotion.rawValue,
                            paragraphIndex: sliceIdx
                        )
                        let item = TTSQueueItem(
                            segment: seg,
                            audioURL: url,
                            audioData: audioData,
                            chapterTitle: "自定义多角色",
                            bookTitle: "测试",
                            bookID: "custom",
                            chapterIndex: 0,
                            segmentIndex: segIdx,
                            totalSegments: segments.count,
                            paragraphIndex: sliceIdx,
                            sentenceIndex: nil,
                            anchor: nil
                        )

                        // 每段合成后立即入队，不等待同片其他段
                        await MainActor.run {
                            store.audioController.appendToQueue([item])
                            if !firstSegmentPlayed {
                                firstSegmentPlayed = true
                                customSynthesisResult = "第 1 段合成完成，开始播放..."
                            } else {
                                customSynthesisResult = "已合成第 \(segIdx + 1)/\(segments.count) 段(片\(sliceIdx + 1))，持续流式..."
                            }
                        }
                    }
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
                await MainActor.run {
                    isProcessingWorker = false
                    isSynthesizingCustom = false
                    workerProgress = 0
                    if firstSegmentPlayed {
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

                for (sliceIdx, slice) in slices.enumerated() {
                    await MainActor.run {
                        workerProgressMessage = "正在解析第 \(sliceIdx + 1)/\(totalSlices) 片..."
                        workerProgress = Double(sliceIdx) / Double(totalSlices)
                    }

                    let request = AIWorkerRequest(
                        text: slice,
                        sliceIndex: sliceIdx,
                        totalSlices: totalSlices,
                        context: nil
                    )
                    let response = try await AIWorkerService.shared.sendRequest(request, config: workerConfig)
                    let segments = response.segments

                    DebugLogger.log(flow: "custom_multi_role", step: "parseCustomWithWorker_slice", details: [
                        "slice_index": sliceIdx,
                        "total_slices": totalSlices,
                        "segments_in_slice": segments.count,
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

    private func assignVoicesToSegments(_ segments: [AISegment]) {
        let mainSpeakers = Array(Set(segments.map { resolveAlias($0.speaker) })).sorted()
        let zhVoices = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }
        guard !zhVoices.isEmpty else { return }

        let femaleVoices = zhVoices.filter { $0.gender == "Female" }
        let maleVoices = zhVoices.filter { $0.gender == "Male" }
        var femaleIdx = 0, maleIdx = 0, neutralIdx = 0
        let neutralVoices = zhVoices

        // 优先采用 AI 返回的 gender（取该主角色首个非 unknown 的性别）
        var speakerGender: [String: Gender] = [:]
        for seg in segments where seg.gender != .unknown {
            let mainName = resolveAlias(seg.speaker)
            if speakerGender[mainName] == nil {
                speakerGender[mainName] = seg.gender
            }
        }

        // 清除别名的音色映射（别名继承主角色的音色）
        for alias in characterAliases.keys {
            customCharacterVoices.removeValue(forKey: alias)
        }

        var voices = customCharacterVoices

        for speaker in mainSpeakers {
            if let existing = customCharacterVoices[speaker], !existing.isEmpty {
                voices[speaker] = existing
                continue
            }

            let gender = TTSView.resolveGender(speaker: speaker, aiGender: speakerGender[speaker])

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

    /// 默认中文音色（服务器 voices 为空时的兜底）
    private static let defaultChineseVoices: [EdgeVoiceInfo] = [
        EdgeVoiceInfo(id: "zh-CN-XiaoxiaoNeural", name: "zh-CN-XiaoxiaoNeural", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunxiNeural", name: "zh-CN-YunxiNeural", gender: "Male", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunyangNeural", name: "zh-CN-YunyangNeural", gender: "Male", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaochenNeural", name: "zh-CN-XiaochenNeural", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-XiaohanNeural", name: "zh-CN-XiaohanNeural", gender: "Female", locale: "zh-CN"),
        EdgeVoiceInfo(id: "zh-CN-YunyeNeural", name: "zh-CN-YunyeNeural", gender: "Male", locale: "zh-CN"),
    ]

    /// 音色 ID → 中文名称
    static func chineseVoiceName(for voiceID: String) -> String {
        let map: [String: String] = [
            "zh-CN-XiaoxiaoNeural": "小晓", "zh-CN-XiaochenNeural": "晓辰",
            "zh-CN-XiaohanNeural": "晓涵", "zh-CN-XiaomoNeural": "晓墨",
            "zh-CN-XiaoxuanNeural": "晓萱", "zh-CN-XiaoyanNeural": "晓颜",
            "zh-CN-XiaoyiNeural": "晓伊", "zh-CN-XiaomengNeural": "晓萌",
            "zh-CN-YunxiNeural": "云希", "zh-CN-YunyangNeural": "云扬",
            "zh-CN-YunyeNeural": "云野", "zh-CN-YunjianNeural": "云健",
            "zh-CN-YunfengNeural": "云峰",
            "zh-HK-HiuMaanNeural": "晓曼", "zh-HK-WanLungNeural": "云龙",
            "zh-TW-HsiaoChenNeural": "晓臻", "zh-TW-YunJheNeural": "云哲",
        ]
        return map[voiceID] ?? voiceID
    }

    /// 根据说话人自动匹配音色（基于性别，优先从 zh-CN 女声/男声中选择）
    private static func autoMatchVoice(for speaker: String, gender: Gender, availableVoices: [EdgeVoiceInfo]) -> String {
        let zhVoices = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }
        let voices = zhVoices.isEmpty ? defaultChineseVoices : zhVoices
        let resolved: Gender = {
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

    /// 解析别名 → 主名
    private func resolveAlias(_ name: String) -> String {
        characterAliases[name] ?? name
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
        guard source != target else { return }
        // 如果 source 本身是某个角色的别名，先解除
        characterAliases.removeValue(forKey: source)
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
        customWorkerSegments.removeAll { resolveAlias($0.speaker) == speaker }
        customCharacterVoices.removeValue(forKey: speaker)
        // 同时删除以此为别名的映射
        for (alias, main) in characterAliases where main == speaker {
            characterAliases.removeValue(forKey: alias)
        }
    }

    /// 角色操作：重命名角色
    private func renameCharacter(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        // 重命名别名映射中的键
        if characterAliases[oldName] != nil {
            characterAliases[trimmed] = characterAliases.removeValue(forKey: oldName)
        }
        // 重命名别名映射中的值（主角色名）
        for (alias, main) in characterAliases where main == oldName {
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

    /// 综合 AI gender 与名字关键词判定性别（AI 优先，unknown 时回退关键词）
    static func resolveGender(speaker: String, aiGender: Gender?) -> Gender {
        if let g = aiGender, g != .unknown { return g }
        let isFemale = speaker.contains("女") || speaker.contains("小姐") || speaker.contains("姑娘") || speaker.contains("她") || speaker.contains("姐") || speaker.contains("娘") || speaker.contains("妈") || speaker.contains("婆")
        let isMale = speaker.contains("公") || speaker.contains("哥") || speaker.contains("爷") || speaker.contains("兄") || speaker.contains("他") || speaker.contains("叔") || speaker.contains("爸") || speaker.contains("父")
        if isFemale { return .female }
        if isMale { return .male }
        return .unknown
    }

    /// 根据情绪和角色名计算语速偏移
    private static func rateOffset(for segment: AISegment) -> Int {
        switch segment.emotion {
        case .angry, .shouting, .excited: return 4
        case .happy, .cheerful, .surprised: return 2
        case .sad, .fearful, .whispering, .calm, .gentle: return -2
        default: return 0
        }
    }

    /// 从 tone 语气关键词推导基准音量(dB)，叠加全局滑块偏移，输出 SSML 兼容 dB 值
    private static func resolvedVolume(tone: String, globalOffset: Double) -> String {
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
    private static func pitchOffset(for segment: AISegment, speakerName: String) -> Int {
        let gender = resolveGender(speaker: speakerName, aiGender: segment.gender)
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
        return genderOffset + emotionOffset
    }

    private func synthesizeAndPlayCustom() {
        guard let serverID = selectedServerID,
              !customWorkerSegments.isEmpty else { return }

        isSynthesizingCustom = true
        customSynthesisResult = "正在合成首段..."

        DebugLogger.log(flow: "custom_synthesize", step: "start", details: [
            "total_segments": customWorkerSegments.count,
            "segments": customWorkerSegments.map { s in
                ["speaker": s.speaker, "emotion": s.emotion.rawValue, "text_preview": String(s.text.prefix(80))]
            },
            "character_voices": customCharacterVoices.mapValues { $0 },
        ])

        Task {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let globalRate = multiRoleGlobalRate
            let globalVolume = globalVolumeOffset

            // 首段合成并立即播放
            do {
                let firstSegment = customWorkerSegments[0]
                let voiceID = voiceForSpeaker(firstSegment.speaker)
                let rate = Int(globalRate) + Self.rateOffset(for: firstSegment)
                let pitch = Self.pitchOffset(for: firstSegment, speakerName: firstSegment.speaker)
                let style = firstSegment.emotion.ssmlStyle
                let volume = TTSView.resolvedVolume(tone: firstSegment.tone, globalOffset: globalVolume)

                let audioData = try await EdgeTTSService.shared.synthesize(
                    text: firstSegment.text,
                    voice: voiceID,
                    rate: Double(rate),
                    pitch: Double(pitch),
                    style: style,
                    volume: volume,
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
                DebugLogger.log(flow: "custom_synthesize", step: "first_segment_error", details: [
                    "error": error.localizedDescription,
                ])
                await MainActor.run {
                    customSynthesisResult = "首段合成失败: \(error.localizedDescription)"
                    isSynthesizingCustom = false
                }
                return
            }

            // 逐段合成 → 逐段入队（真正的流式）
            await MainActor.run { customSynthesisResult = "第 1/\(customWorkerSegments.count) 段播放中，继续合成后续..." }
            var totalSuccess = 1

            for (idx, segment) in customWorkerSegments.dropFirst().enumerated() {
                let voiceID = voiceForSpeaker(segment.speaker)
                let rate = Int(globalRate) + Self.rateOffset(for: segment)
                let pitch = Self.pitchOffset(for: segment, speakerName: segment.speaker)
                let style = segment.emotion.ssmlStyle
                let volume = TTSView.resolvedVolume(tone: segment.tone, globalOffset: globalVolume)

                do {
                    let audioData = try await EdgeTTSService.shared.synthesize(
                        text: segment.text,
                        voice: voiceID,
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

                    // 立即入队，不等待后续合成
                    await MainActor.run {
                        store.audioController.appendToQueue([item])
                        totalSuccess += 1
                        customSynthesisResult = "已合成 \(totalSuccess)/\(customWorkerSegments.count) 段，持续流式播放..."
                    }
                } catch {
                    DebugLogger.log(flow: "custom_synthesize", step: "remaining_segment_error", details: [
                        "segment_index": idx + 1,
                        "speaker": segment.speaker,
                        "error": error.localizedDescription,
                    ])
                    await MainActor.run {
                        customSynthesisResult = "第 \(idx + 2) 段合成失败: \(error.localizedDescription)"
                    }
                }
            }

            await MainActor.run {
                isSynthesizingCustom = false
                customSynthesisResult = "\(totalSuccess)/\(customWorkerSegments.count) 段全部入队，正在流式播放"
            }
            DebugLogger.log(flow: "custom_synthesize", step: "complete", details: [
                "total_segments": customWorkerSegments.count,
                "successful_items": totalSuccess,
            ])
        }
    }

    private func resynthesizeCharacter(_ speaker: String) {
        guard let serverID = selectedServerID else { return }
        let segments = customWorkerSegments.filter { resolveAlias($0.speaker) == speaker }
        guard !segments.isEmpty else { return }

        characterResynthesisStates[speaker] = true
        // 先自动匹配音色（如果当前为空或为"自动"），再合成
        let currentVoice = voiceForSpeaker(speaker)
        let autoVoice = TTSView.autoMatchVoice(for: speaker, gender: segments.first?.gender ?? .unknown, availableVoices: availableVoices)
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

struct CharacterRoleCard: View {
    let speaker: String
    let aliases: [String]
    let segmentCount: Int
    let emotionSummary: String?
    let gender: Gender
    let autoMatchedVoiceID: String
    @Binding var voice: String
    let isResynthesizing: Bool
    let availableVoices: [EdgeVoiceInfo]
    let onResynthesize: () -> Void
    let onMerge: (String) -> Void
    let onSplit: ((String) -> Void)?
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let otherSpeakers: [String]

    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showMergePicker = false
    @State private var showDeleteConfirm = false

    private var genderLabel: (String, String, Color)? {
        switch gender {
        case .male: return ("♂", "男", .blue)
        case .female: return ("♀", "女", .pink)
        case .unknown: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: speaker == "旁白" ? "person.fill" : "person.2.fill")
                    .font(.caption)
                    .foregroundColor(speaker == "旁白" ? .blue : .orange)
                Text(speaker)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let (symbol, label, color) = genderLabel {
                    Text("\(symbol)\(label)")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.15))
                        .cornerRadius(4)
                }
                Spacer()
                Text("\(segmentCount) 段")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
            }

            // 别名子标签
            if !aliases.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text("别名: ")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    + Text(aliases.joined(separator: "、"))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }

            if let emotionSummary {
                Text(emotionSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Picker("", selection: $voice) {
                    Text("自动").tag("")
                    ForEach(availableVoices) { v in
                        Text(v.displayName).tag(v.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                Button {
                    onResynthesize()
                } label: {
                    if isResynthesizing {
                        ProgressView()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // 自动推荐音色名
            if voice.isEmpty, !autoMatchedVoiceID.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("推荐: ")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    + Text(TTSView.chineseVoiceName(for: autoMatchedVoiceID))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.accentColor)
                }
                HStack(spacing: 4) {
                    Text("")
                    Text(autoMatchedVoiceID)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .contextMenu {
            Button("重命名", systemImage: "pencil") {
                renameText = speaker
                showRenameAlert = true
            }
            if !aliases.isEmpty, let onSplit {
                Menu("分离别名...", systemImage: "arrow.triangle.branch") {
                    ForEach(aliases, id: \.self) { alias in
                        Button("\(alias)") {
                            onSplit(alias)
                        }
                    }
                }
            }
            if !otherSpeakers.isEmpty {
                Menu("合并到...", systemImage: "arrow.triangle.merge") {
                    ForEach(otherSpeakers, id: \.self) { target in
                        Button("\(target)") {
                            onMerge(target)
                        }
                    }
                }
            }
            Divider()
            Button("删除角色", systemImage: "trash", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .alert("重命名角色", isPresented: $showRenameAlert) {
            TextField("新名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("确定") {
                onRename(renameText)
            }
        } message: {
            Text("将「\(speaker)」重命名为：")
        }
        .confirmationDialog("确定删除「\(speaker)」？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { onDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 \(segmentCount) 个相关片段，不可撤销。")
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
