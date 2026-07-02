import SwiftUI

struct TTSServerListView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAddSheet = false
    @State private var editingServer: TTSServer?
    @State private var testResults: [UUID: String] = [:]

    var body: some View {
        List {
            if store.ttsServers.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text("尚无 TTS 服务器")
                            .foregroundColor(.secondary)
                        Text("请添加一台 TTS 服务器以开始使用朗读功能。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }

            ForEach(store.ttsServers) { server in
                Section {
                    Button(action: { store.setActiveServer(server.id) }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(server.name)
                                        .font(.headline)
                                    if server.isActive {
                                        Text("当前")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    }
                                }
                                Text(server.baseURL)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if server.apiKey.isEmpty {
                                    Text("无 API Key")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                Text("最大文本: \(server.maxTextLength) 字符")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if let result = testResults[server.id] {
                                    Text(result)
                                        .font(.caption2)
                                        .foregroundColor(result.contains("ms") ? .green : .red)
                                }
                            }
                            Spacer()
                            if server.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .foregroundColor(.primary)

                    HStack {
                        Button("测试连接") {
                            Task { await testServer(server) }
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.isBusy)

                        Spacer()

                        Button("编辑") {
                            editingServer = server
                        }
                        .buttonStyle(.borderless)

                        Button("删除", role: .destructive) {
                            store.removeServer(server.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("TTS 服务器")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            TTSServerEditView(server: nil) { newServer in
                store.addServer(newServer)
                if store.ttsServers.count == 1 {
                    store.setActiveServer(newServer.id)
                }
            }
        }
        .sheet(item: $editingServer) { server in
            TTSServerEditView(server: server) { updated in
                store.updateServer(updated)
            }
        }
    }

    private func testServer(_ server: TTSServer) async {
        testResults[server.id] = "测试中..."
        let client = TTSHttpClient(baseURL: URL(string: server.baseURL) ?? URL(string: "http://127.0.0.1:8080")!,
                                   apiKey: server.apiKey.isEmpty ? nil : server.apiKey)
        let start = Date()
        do {
            _ = try await client.synthesizeAudio(text: "测试", voice: "zh-CN-XiaoxiaoNeural",
                                                  rate: 0, pitch: 0, style: "neutral")
            let elapsed = Int((Date().timeIntervalSince(start) * 1000))
            testResults[server.id] = "\(elapsed)ms ✓"
        } catch {
            testResults[server.id] = "失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 服务器编辑

struct TTSServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    let server: TTSServer?
    let onSave: (TTSServer) -> Void

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var maxTextLength: Int = 1024

    private let isEditing: Bool

    init(server: TTSServer?, onSave: @escaping (TTSServer) -> Void) {
        self.server = server
        self.onSave = onSave
        self.isEditing = server != nil
        _name = State(initialValue: server?.name ?? "")
        _baseURL = State(initialValue: server?.baseURL ?? "")
        _apiKey = State(initialValue: server?.apiKey ?? "")
        _maxTextLength = State(initialValue: server?.maxTextLength ?? 1024)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("服务器信息")) {
                    TextField("名称", text: $name)
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("API Key（选填）", text: $apiKey)
                        .textContentType(.password)
                }

                Section(header: Text("高级")) {
                    HStack {
                        Text("最大字符数")
                        Spacer()
                        TextField("1024", value: $maxTextLength, format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑服务器" : "添加服务器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let updated = TTSServer(
                            id: server?.id ?? UUID(),
                            name: name,
                            baseURL: baseURL,
                            apiKey: apiKey,
                            isActive: server?.isActive ?? false,
                            maxTextLength: maxTextLength
                        )
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.isEmpty || baseURL.isEmpty)
                }
            }
        }
    }
}
