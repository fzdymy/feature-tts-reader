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
    @State private var serverListText = ""
    @State private var apiKey = ""
    @State private var connectionStatus = "未测试"
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务地址（每行一个）", text: $serverListText, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                    TextField("API Key（可选）", text: $apiKey)
                        .autocorrectionDisabled()
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
                } header: {
                    Label("Edge TTS 服务器", systemImage: "server.rack")
                } footer: {
                    Text("默认：\(EdgeTTSService.defaultServerURL)　|　每行一个地址，多个备用")
                        .font(.caption)
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
                    serverListText = await EdgeTTSService.shared.serverListText
                    apiKey = await EdgeTTSService.shared.apiKey
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
            await EdgeTTSService.shared.setServerList(serverListText)
            await EdgeTTSService.shared.setAPIKey(apiKey)
            let result = await EdgeTTSService.shared.healthCheck()
            await MainActor.run {
                connectionStatus = result
                store.edgeTTSLastHealth = result
                isTesting = false
            }
        }
    }
}
