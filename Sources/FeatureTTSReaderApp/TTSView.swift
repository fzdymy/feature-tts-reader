import SwiftUI

private let edgeVoices: [(id: String, label: String)] = [
    ("zh-CN-XiaoxiaoNeural", "晓晓（女）"),
    ("zh-CN-XiaoyiNeural", "晓伊（女）"),
    ("zh-CN-YunxiNeural", "云希（男）"),
    ("zh-CN-YunyangNeural", "云扬（男）"),
    ("zh-CN-YunyeNeural", "云野（男）"),
    ("zh-CN-XiaochenNeural", "晓辰（女）"),
    ("zh-CN-XiaohanNeural", "晓涵（女）"),
    ("zh-CN-XiaomengNeural", "晓梦（女）"),
    ("zh-CN-XiaomoNeural", "晓墨（女）"),
    ("zh-CN-XiaoqiuNeural", "晓秋（女）"),
    ("zh-CN-XiaoruiNeural", "晓睿（女）"),
    ("zh-CN-XiaoshuangNeural", "晓双（女）"),
    ("zh-CN-XiaoxuanNeural", "晓萱（女）"),
    ("zh-CN-XiaoyanNeural", "晓颜（女）"),
    ("zh-CN-XiaozhenNeural", "晓甄（女）"),
    ("zh-CN-YunfengNeural", "云枫（男）"),
    ("zh-CN-YunhaoNeural", "云皓（男）"),
    ("zh-CN-YunjianNeural", "云健（男）"),
    ("zh-CN-YunxiaNeural", "云夏（男）"),
    ("zh-CN-YunzeNeural", "云泽（男）"),
]

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var serverConfigs: [EdgeTTSServerConfig] = []
    @State private var selectedServerID: UUID?
    @State private var connectionStatus = "未测试"
    @State private var isTesting = false
    @State private var testText = "你好，欢迎使用语音合成。这是一个测试。"
    @State private var testResult = ""
    @State private var isTestingSynthesis = false
    @State private var showPreview = false
    @State private var testVoice = "zh-CN-YunyangNeural"

    private var selectedServer: Binding<EdgeTTSServerConfig>? {
        guard let id = selectedServerID,
              let idx = serverConfigs.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { serverConfigs[idx] },
            set: { serverConfigs[idx] = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Server List
                Section {
                    ForEach(serverConfigs) { config in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(config.name.isEmpty ? (config.url.isEmpty ? "新服务器" : config.url) : config.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(config.url.isEmpty ? "未配置" : config.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if config.id == selectedServerID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedServerID = config.id
                        }
                        .swipeActions(edge: .trailing) {
                            if serverConfigs.count > 1 {
                                Button(role: .destructive) {
                                    serverConfigs.removeAll { $0.id == config.id }
                                    if selectedServerID == config.id {
                                        selectedServerID = serverConfigs.first?.id
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    Button {
                        var newConfig = EdgeTTSServerConfig(url: "", apiKey: "")
                        let count = serverConfigs.count + 1
                        newConfig.name = "服务器 \(count)"
                        serverConfigs.append(newConfig)
                        selectedServerID = newConfig.id
                    } label: {
                        Label("添加服务器", systemImage: "plus.circle")
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

                // MARK: - Selected Server Config
                if let binding = selectedServer {
                    Section {
                        VStack(spacing: 12) {
                            HStack {
                                Text("名称")
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                TextField("服务器名称", text: binding.name)
                                    .autocorrectionDisabled()
                            }
                            Divider()
                            HStack(alignment: .top) {
                                Text("地址")
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                TextField("http://192.168.1.100:37788", text: binding.url)
                                    .font(.caption.monospaced())
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            Divider()
                            HStack(alignment: .top) {
                                Text("密钥")
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                TextField("API Key（可选）", text: binding.apiKey)
                                    .font(.caption.monospaced())
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Label(binding.wrappedValue.name.isEmpty ? "服务器配置" : binding.wrappedValue.name, systemImage: "slider.horizontal.3")
                    }
                }

                // MARK: - Test
                Section {
                    VStack(spacing: 10) {
                        TextField("测试文本", text: $testText, axis: .vertical)
                            .font(.body)
                            .lineLimit(3...6)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        Picker("发音人", selection: $testVoice) {
                            ForEach(edgeVoices, id: \.id) { v in
                                Text(v.label).tag(v.id)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack(spacing: 12) {
                            Button {
                                saveAndTest()
                            } label: {
                                if isTesting {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.7)
                                        Text("测试连接...")
                                    }
                                    .frame(maxWidth: .infinity)
                                } else {
                                    Label("测试连接", systemImage: "antenna.radiowaves.left.and.right")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTesting || selectedServerID == nil)

                            Button {
                                testSynthesis()
                            } label: {
                                if isTestingSynthesis {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.7)
                                        Text("合成中...")
                                    }
                                    .frame(maxWidth: .infinity)
                                } else {
                                    Label("试听", systemImage: "play.circle")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isTestingSynthesis || selectedServerID == nil || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    // Preview toggle
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
                } footer: {
                    if !testResult.isEmpty {
                        Text(testResult)
                            .foregroundColor(testResult.contains("成功") || testResult.contains("就绪") ? .green : .red)
                    }
                }

                // MARK: - Status
                Section {
                    HStack {
                        Label("连接状态", systemImage: "info.circle")
                        Spacer()
                        Circle()
                            .fill(connectionStatus.contains("就绪") || connectionStatus.contains("200") || connectionStatus.contains("服务")
                                  ? Color.green : connectionStatus == "未测试" ? Color.gray : Color.red)
                            .frame(width: 8, height: 8)
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("朗读模式", systemImage: "waveform")
                        Spacer()
                        Text("流式实时合成")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("状态", systemImage: "gauge.with.dots.needle.33percent")
                }
            }
            .navigationTitle("语音设置")
            .onAppear {
                Task {
                    let servers = await EdgeTTSService.shared.configuredServers
                    serverConfigs = servers
                    if serverConfigs.isEmpty {
                        var config = EdgeTTSServerConfig(url: EdgeTTSService.defaultServerURL, apiKey: "")
                        config.name = "默认服务器"
                        serverConfigs = [config]
                    }
                    if selectedServerID == nil {
                        selectedServerID = serverConfigs.first?.id
                    }
                    connectionStatus = store.edgeTTSLastHealth.isEmpty ? "未测试" : store.edgeTTSLastHealth
                }
            }
        }
    }

    @ViewBuilder
    private var requestPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.secondary)
                Text("预发送内容（单击收起，长按复制内容）")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            if let config = serverConfigs.first(where: { $0.id == selectedServerID }) {
                let ssml = EdgeTTSService.buildSSML(text: testText, voice: testVoice, rate: 0, pitch: 0, emotionTag: nil)

                // URL
                VStack(alignment: .leading, spacing: 2) {
                    Text("URL")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                    let base = config.url.hasSuffix("/tts") ? config.url : config.url + "/tts"
                    let encoded = ssml.addingPercentEncoding(withAllowedCharacters: .urlQueryParameterAllowed) ?? ssml
                    let fullURL = "\(base)?t=\(encoded)" + (config.apiKey.isEmpty ? "" : "&api_key=\(config.apiKey)")
                    Text(fullURL)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(4)
                }

                // SSML
                VStack(alignment: .leading, spacing: 2) {
                    Text("SSML 内容（voice = \(testVoice)）")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                    Text(ssml)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(6)
                }

                // Headers
                VStack(alignment: .leading, spacing: 2) {
                    Text("Headers")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                    Text("Accept: audio/mp3")
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                    if !config.apiKey.isEmpty {
                        Text("X-API-Key: \(config.apiKey)")
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func saveAndTest() {
        guard !isTesting, let id = selectedServerID else { return }
        isTesting = true
        connectionStatus = "测试中..."
        Task {
            let valid = serverConfigs.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            await EdgeTTSService.shared.setServers(valid)
            let result = await EdgeTTSService.shared.healthCheck(serverID: id)
            await MainActor.run {
                connectionStatus = result
                store.edgeTTSLastHealth = result
                isTesting = false
            }
        }
    }

    private func testSynthesis() {
        guard !isTestingSynthesis, let id = selectedServerID else { return }
        isTestingSynthesis = true
        testResult = ""
        Task {
            let result = await store.testTTSSynthesize(serverID: id, text: testText, voice: testVoice)
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

private extension CharacterSet {
    static let urlQueryParameterAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove("&")
        allowed.remove("+")
        return allowed
    }()
}
