import SwiftUI
import AVFoundation

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var modelStatus = "未加载"
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("CosyVoice 3")
                            .font(.headline)
                        Spacer()
                        Circle()
                            .fill(modelStatus == "就绪" ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(modelStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

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
                                    let urls = [url]
                                    Task { await store.audioController.playFilesAndWait(urls) }
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
                    Label("语音引擎", systemImage: "waveform")
                }

                Section {
                    Text("多角色对话合成")
                        .font(.subheadline)
                    Text("支持情绪标签：开心、悲伤、愤怒等")
                        .font(.caption).foregroundColor(.secondary)
                    Text("声纹克隆：每个角色 10-30 秒参考音频")
                        .font(.caption).foregroundColor(.secondary)
                } header: {
                    Label("功能", systemImage: "gearshape.2")
                }

                Section {
                    Text(store.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Label("状态", systemImage: "info.circle")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("语音")
            .onAppear {
                Task {
                    if await CosyVoiceService.shared.isAvailable {
                        modelStatus = "就绪"
                    } else {
                        modelStatus = "首次使用需下载模型 (~1.5GB)"
                    }
                }
            }
        }
    }
}
