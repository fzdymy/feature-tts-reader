import SwiftUI

struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var serverConfigs: [EdgeTTSServerConfig] = []
    @State private var connectionStatus = "未测试"
    @State private var isTesting = false
    @State private var testText = "你好，欢迎使用语音合成。这是一个测试。"
    @State private var testResult = ""
    @State private var isTestingSynthesis = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(serverConfigs.indices, id: \.self) { i in
                        VStack(spacing: 6) {
                            HStack {
                                TextField("服务器地址", text: Binding(
                                    get: { serverConfigs[i].url },
                                    set: { serverConfigs[i].url = $0 }
                                ))
                                .font(.body.monospaced())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                                Button(role: .destructive) {
                                    serverConfigs.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            TextField("API Key（可选）", text: Binding(
                                get: { serverConfigs[i].apiKey },
                                set: { serverConfigs[i].apiKey = $0 }
                            ))
                            .font(.caption.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        serverConfigs.append(EdgeTTSServerConfig(url: "", apiKey: ""))
                    } label: {
                        Label("添加服务器", systemImage: "plus.circle")
                    }
                } header: {
                    Label("Edge TTS 服务器", systemImage: "server.rack")
                } footer: {
                    Text("每行一个服务器地址和对应的 API Key。多个服务器自动轮询。")
                        .font(.caption)
                }

                Section {
                    Button {
                        saveAndTest()
                    } label: {
                        if isTesting {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("测试中...")
                            }
                        } else {
                            Text("保存并测试连接")
                        }
                    }
                    .disabled(isTesting)
                }

                Section {
                    TextField("测试文本", text: $testText, axis: .vertical)
                        .font(.body)
                        .lineLimit(3...6)
                    Button {
                        testSynthesis()
                    } label: {
                        if isTestingSynthesis {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("合成中...")
                            }
                        } else {
                            Label("试听", systemImage: "play.circle")
                        }
                    }
                    .disabled(isTestingSynthesis || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !testResult.isEmpty {
                        StatusRow(label: "结果", value: testResult)
                            .foregroundColor(testResult.contains("成功") ? .green : .red)
                    }
                } header: {
                    Label("语音测试", systemImage: "waveform")
                }

                Section {
                    StatusRow(label: "连接状态", value: connectionStatus)
                    StatusRow(label: "朗读模式", value: "流式实时合成")
                } header: {
                    Label("状态", systemImage: "info.circle")
                }
            }
            .navigationTitle("语音设置")
            .onAppear {
                Task {
                    serverConfigs = await EdgeTTSService.shared.configuredServers
                    if serverConfigs.isEmpty {
                        serverConfigs = [EdgeTTSServerConfig(url: EdgeTTSService.defaultServerURL, apiKey: "")]
                    }
                    connectionStatus = store.edgeTTSLastHealth.isEmpty ? "未测试" : store.edgeTTSLastHealth
                }
            }
        }
    }

    private func saveAndTest() {
        guard !isTesting else { return }
        isTesting = true
        connectionStatus = "测试中..."
        Task {
            let valid = serverConfigs.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if valid.isEmpty {
                await MainActor.run {
                    connectionStatus = "错误：请填写至少一个服务器地址"
                    isTesting = false
                }
                return
            }
            await EdgeTTSService.shared.setServers(valid)
            let result = await EdgeTTSService.shared.healthCheck()
            await MainActor.run {
                connectionStatus = result
                store.edgeTTSLastHealth = result
                isTesting = false
            }
        }
    }

    private func testSynthesis() {
        guard !isTestingSynthesis else { return }
        isTestingSynthesis = true
        testResult = ""
        Task {
            let result = await store.testTTSSynthesize()
            await MainActor.run {
                testResult = result
                isTestingSynthesis = false
            }
        }
    }
}
