import SwiftUI
import AVFoundation

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var modelStatus = "检查中…"
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var serverListText = EdgeTTSService.shared.serverListText
    @State private var apiKey = EdgeTTSService.shared.apiKey
    @State private var healthMessage = ""
    @State private var showCopied = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                engineSection
                downloadSection
                testSection
                samplesSection
                infoSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("语音")
            .onAppear {
                serverListText = EdgeTTSService.shared.serverListText
                apiKey = EdgeTTSService.shared.apiKey
                refreshStatus()
            }
            .onReceive(timer) { _ in refreshStatus() }
        }
    }

    // MARK: - Engine Status

    private var engineSection: some View {
        Section {
            HStack {
                Text("Edge TTS")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(healthMessage.contains("就绪") || healthMessage.contains("服务") ? Color.green : .orange)
                    .frame(width: 8, height: 8)
                Text(modelStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Label("语音引擎", systemImage: "waveform")
        }
    }

    // MARK: - Download Section

    private var downloadSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("服务地址列表")
                    .font(.subheadline)
                TextEditor(text: $serverListText)
                    .frame(minHeight: 100)
                    .font(.body.monospaced())
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                TextField("API Key（可选）", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        saveServerURL()
                    }
                HStack {
                    Button("保存") {
                        saveServerURL()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("复制") {
                        UIPasteboard.general.string = serverListText
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
                    }
                    .buttonStyle(.bordered)
                }
                Text("当前默认服务：\(EdgeTTSService.defaultServerURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("每行一个地址；可填多个备用服务器。当前本地服务使用 /tts?text=... 的查询接口返回音频。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !healthMessage.isEmpty {
                    Text(healthMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Label("服务配置", systemImage: "server.rack")
        }
    }

    // MARK: - Test Section

    private var testSection: some View {
        Section {
            Button("测试语音合成") {
                Task {
                    isTesting = true
                    testResult = nil
                    let result = await store.testTTSSynthesize()
                    testResult = result
                    isTesting = false
                }
            }
            .disabled(isTesting)

            if let result = testResult {
                Text(result).font(.caption).foregroundColor(.secondary)
                if result.hasPrefix("合成成功"), let url = store.ttsTestAudioURL {
                    HStack(spacing: 16) {
                        Button("播放") {
                            Task { await store.audioController.playFilesAndWait([url]) }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("取消") {
                            testResult = nil
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        } header: {
            Label("测试", systemImage: "hammer")
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            Text("多角色对话合成").font(.subheadline)
            Text("支持情绪标签：开心、悲伤、愤怒等")
                .font(.caption).foregroundColor(.secondary)
            Text("可直接使用 Edge TTS relay 服务进行实时合成与播放")
                .font(.caption).foregroundColor(.secondary)
            Text(store.statusMessage)
                .font(.subheadline).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Label("功能", systemImage: "gearshape.2")
        }
    }

    // MARK: - Helpers

    private func refreshStatus() {
        Task {
            let status = await EdgeTTSService.shared.healthCheck()
            await MainActor.run {
                healthMessage = status
                modelStatus = status.contains("就绪") || status.contains("服务") ? "已配置" : "未连接"
            }
        }
    }

    private func saveServerURL() {
        EdgeTTSService.shared.setServerList(serverListText)
        EdgeTTSService.shared.setAPIKey(apiKey)
        refreshStatus()
    }

    private var voiceSamples: [URL] {
        guard let resourceURL = Bundle.module.resourceURL else { return [] }
        let samplesDir = resourceURL.appendingPathComponent("Models/default_samples")
        guard FileManager.default.fileExists(atPath: samplesDir.path) else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(at: samplesDir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @ViewBuilder
    private var samplesSection: some View {
        Section {
            if voiceSamples.isEmpty {
                Text("暂无内置音色样本").foregroundColor(.secondary)
            } else {
                Text("APP内置 \(voiceSamples.count) 个音色样本 (16kHz 单声道 WAV，供本地试听使用)")
                    .font(.caption).foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(voiceSamples, id: \.path) { url in
                            VStack(spacing: 4) {
                                Image(systemName: "waveform.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.center)
                                Button("播放") {
                                    Task { await store.audioController.playFilesAndWait([url]) }
                                }
                                .font(.caption2)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                            }
                            .padding(6)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 120)
            }
        } header: {
            Label("音色样本库", systemImage: "waveform.circle")
        }
    }
}
