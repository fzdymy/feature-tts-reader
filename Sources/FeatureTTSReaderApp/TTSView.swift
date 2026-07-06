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
    @State private var downloadSpeed: Double = 0
    @State private var selectedProxy: DownloadProxy = .direct
    @State private var customProxyURL = ""

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

            // Proxy selector (only when idle or failed)
            if downloadPhase == .idle || downloadPhase == .failed {
                Picker("加速代理", selection: $selectedProxy) {
                    ForEach(DownloadProxy.allCases, id: \.self) { proxy in
                        Text(proxy.displayName).tag(proxy)
                    }
                }
                .onChange(of: selectedProxy) { _, newValue in
                    DownloadProxy.active = newValue
                    if newValue != .custom { customProxyURL = "" }
                }

                if selectedProxy == .custom {
                    HStack {
                        TextField("例如 https://gh-proxy.org", text: $customProxyURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption)
                        Button("应用") {
                            DownloadProxy.customPrefix = customProxyURL
                                .trimmingCharacters(in: .whitespaces)
                                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }

            switch downloadPhase {
            case .idle:
                VStack(alignment: .leading, spacing: 8) {
                    Text("模型未下载 (~1.0GB)")
                        .foregroundColor(.secondary)
                    if selectedProxy != .direct {
                        Text("代理: \(selectedProxy.displayName)")
                            .font(.caption).foregroundColor(.green)
                    }
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
                        // Download speed + ETA
                        if downloadSpeed > 0 {
                            let speedText: String = {
                                let bps = downloadSpeed
                                if bps >= 1_000_000 {
                                    return String(format: "%.1f MB/s", bps / 1_000_000)
                                } else {
                                    return String(format: "%.0f KB/s", bps / 1_000)
                                }
                            }()
                            let remaining = max(0, (1 - progress) * Double(CosyVoiceService.estimatedModelSize))
                            let etaSecs = remaining / downloadSpeed
                            let etaText: String = {
                                guard etaSecs.isFinite, etaSecs > 0 else { return "计算中…" }
                                if etaSecs < 60 {
                                    return "剩余 \(Int(etaSecs))秒"
                                }
                                let m = Int(etaSecs) / 60
                                let s = Int(etaSecs) % 60
                                return "剩余 \(m)分\(s)秒"
                            }()
                            HStack {
                                Text("速度 \(speedText)")
                                Spacer()
                                Text(etaText)
                            }
                            .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Text("约 1.0GB，请保持网络畅通")
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
                    Spacer()
                    Button("删除模型", systemImage: "trash", role: .destructive) {
                        Task { await CosyVoiceService.shared.resetDownload() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.red)
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
            VStack(spacing: 4) {
                HStack {
                    Text("手动下载（复制到浏览器）")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        let tag = CosyVoiceService.variants[selectedVariant].tag
                        let raw = "https://github.com/fzdymy/feature-tts-reader/releases/download/\(tag)/cosyvoice-\(tag).tar.gz"
                        UIPasteboard.general.string = raw
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
                    } label: {
                        Label(showCopied ? "已复制" : "复制链接", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                if selectedProxy != .direct {
                    Text("当前使用代理: \(selectedProxy.displayName)")
                        .font(.caption2).foregroundColor(.green)
                } else {
                    Text("国内用户建议选择加速代理")
                        .font(.caption2).foregroundColor(.orange)
                }
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
        .fileImporter(
            isPresented: $showManualImport,
            allowedContentTypes: [.folder, .data]
        ) { result in
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
        // Sync proxy selector with current setting
        selectedProxy = DownloadProxy.active
        if selectedProxy == .custom { customProxyURL = DownloadProxy.customPrefix }
        Task {
            let svc = CosyVoiceService.shared
            let actorPhase = await svc.downloadPhase
            // Only override local phase if no user-initiated download is in flight.
            // This prevents the timer from reverting startDownload()'s immediate .downloading back to .idle.
            switch (actorPhase, downloadPhase) {
            case (.idle, .downloading):
                break // keep local .downloading until actor catches up
            default:
                downloadPhase = actorPhase
            }
            downloadError = await svc.downloadError
            downloadStartedAt = await svc.downloadStartedAt
            downloadProgress = await svc.downloadProgress
            downloadSpeed = await svc.downloadSpeed
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
        downloadPhase = .downloading
        downloadError = nil
        downloadProgress = 0
        downloadSpeed = 0
        downloadStartedAt = Date()
        downloadElapsed = 0
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
            let bookmarkData = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            Task {
                do {
                    var isStale = false
                    let resolvedURL: URL
                    if let bookmarkData = bookmarkData {
                        resolvedURL = try URL(
                            resolvingBookmarkData: bookmarkData,
                            options: [.withoutUI],
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale
                        )
                        guard resolvedURL.startAccessingSecurityScopedResource() else {
                            importError = "无法访问文件权限"
                            return
                        }
                        defer { resolvedURL.stopAccessingSecurityScopedResource() }
                    } else {
                        resolvedURL = url
                    }
                    try await CosyVoiceService.shared.importModel(from: resolvedURL)
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
