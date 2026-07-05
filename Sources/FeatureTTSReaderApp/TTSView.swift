import SwiftUI
import AVFoundation

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var modelStatus = "检查中…"
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var downloadPhase: CosyVoiceService.DownloadPhase = .idle
    @State private var downloadError: String?
    @State private var downloadStartedAt: Date?
    @State private var downloadElapsed: TimeInterval = 0
    @State private var showCopied = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Estimated download progress (0.0-1.0) based on elapsed time
    private var estimatedProgress: Double? {
        guard let start = downloadStartedAt, downloadPhase == .downloading else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        // Assume ~8 MB/s download speed; estimate total time = size / speed
        let estimatedSecs = Double(CosyVoiceService.estimatedModelSize) / (8 * 1_000_000)
        return min(elapsed / estimatedSecs, 0.99)
    }

    private var elapsedText: String {
        let secs = downloadElapsed
        if secs < 60 {
            return "\(Int(secs))秒"
        }
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return "\(m)分\(s)秒"
    }

    var body: some View {
        NavigationStack {
            List {
                engineSection
                downloadSection
                testSection
                infoSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("语音")
            .onAppear { refreshStatus() }
            .onReceive(timer) { _ in refreshStatus() }
        }
    }

    // MARK: - Engine Status

    private var engineSection: some View {
        Section {
            HStack {
                Text("CosyVoice 3")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(downloadPhase == .ready ? Color.green : .orange)
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

    @ViewBuilder
    private var downloadSection: some View {
        Section {
            switch downloadPhase {
            case .idle:
                VStack(alignment: .leading, spacing: 8) {
                    Text("模型未下载 (~1.7GB)")
                        .foregroundColor(.secondary)
                    Text("需要网络连接，仅首次需下载")
                        .font(.caption).foregroundColor(.secondary)
                    Button("开始下载模型", systemImage: "icloud.and.arrow.down") {
                        startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .downloading:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                        Text("正在下载模型…")
                            .foregroundColor(.secondary)
                    }
                    if let progress = estimatedProgress {
                        ProgressView(value: progress)
                            .tint(.blue)
                        HStack {
                            Text("已用时 \(elapsedText)")
                            Spacer()
                            Text("\(Int(progress * 100))%")
                        }
                        .font(.caption).foregroundColor(.secondary)
                    }
                    Text("约 1.3GB，请保持网络畅通")
                        .font(.caption).foregroundColor(.secondary)
                }

            case .warming:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                        Text("模型预热中…")
                            .foregroundColor(.secondary)
                    }
                }

            case .ready:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("模型已就绪")
                        .foregroundColor(.secondary)
                }

            case .failed:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("下载失败")
                            .foregroundColor(.red)
                    }
                    if let err = downloadError {
                        Text(err).font(.caption).foregroundColor(.secondary)
                    }
                    Button("重试下载", systemImage: "arrow.clockwise") {
                        Task { await CosyVoiceService.shared.resetDownload(); startDownload() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if downloadPhase != .ready {
                Divider()
                HStack {
                    Text("CDN 下载地址（可复制到浏览器）")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = CosyVoiceService.modelDownloadURL
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
                    } label: {
                        Label(showCopied ? "已复制" : "复制", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Label("模型下载", systemImage: "arrow.down.circle")
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
            .disabled(isTesting || downloadPhase != .ready)

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
            Text("声纹克隆：每个角色 10-30 秒参考音频")
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
            let svc = CosyVoiceService.shared
            downloadPhase = await svc.downloadPhase
            downloadError = await svc.downloadError
            downloadStartedAt = await svc.downloadStartedAt
            if let start = downloadStartedAt {
                downloadElapsed = Date().timeIntervalSince(start)
            }
            switch downloadPhase {
            case .idle:     modelStatus = "未下载"
            case .downloading: modelStatus = "下载中…"
            case .warming:  modelStatus = "预热中…"
            case .ready:    modelStatus = "就绪"
            case .failed:   modelStatus = "下载失败"
            }
        }
    }

    private func startDownload() {
        Task {
            do {
                try await CosyVoiceService.shared.ensureModel()
            } catch {}
        }
    }
}
