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
    @State private var showManualImport = false
    @State private var importModelURL: URL?
    @State private var selectedVariant = 0
    @State private var importError: String?
    @State private var downloadProgress: Double = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var realProgress: Double? {
        guard downloadPhase == .downloading else { return nil }
        let p = downloadProgress
        return p > 0 ? p : nil
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
                samplesSection
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
            // Variant picker (only when idle)
            if downloadPhase == .idle {
                Picker("模型版本", selection: $selectedVariant) {
                    ForEach(Array(CosyVoiceService.variants.enumerated()), id: \.offset) { i, v in
                        Text(v.name).tag(i)
                    }
                }
                .pickerStyle(.menu)
            }

            switch downloadPhase {
            case .idle:
                VStack(alignment: .leading, spacing: 8) {
                    Text("模型未下载 (~1.2GB)")
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
                    if let progress = realProgress {
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

            Divider()
            HStack {
                Text("手动下载（复制链接到浏览器）")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button {
                    let repo = CosyVoiceService.variants[selectedVariant].repo
                    UIPasteboard.general.string = "https://huggingface.co/\(repo)"
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
                } label: {
                    Label(showCopied ? "已复制" : "复制链接", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }

            HStack {
                Text("从本地文件导入模型")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("导入模型文件夹") {
                    showManualImport = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            if let err = importError {
                Text(err).font(.caption).foregroundColor(.red)
            }
        } header: {
            Label("模型下载", systemImage: "arrow.down.circle")
        }
        .fileImporter(isPresented: $showManualImport, allowedContentTypes: [.folder]) { result in
            handleModelImport(result)
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
            downloadProgress = await svc.downloadProgress
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
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }

    private func handleModelImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    try await CosyVoiceService.shared.importModel(from: url)
                } catch {
                    importError = error.localizedDescription
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
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
                Text("APP内置 \(voiceSamples.count) 个音色样本 (16kHz 单声道 WAV)")
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
