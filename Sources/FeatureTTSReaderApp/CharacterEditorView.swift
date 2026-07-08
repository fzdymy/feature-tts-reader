import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct CharacterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReaderStore
    @State private var profile: CharacterProfile
    @State private var samplePlayer: AVAudioPlayer?
    @State private var sampleError: String?
    @State private var isPlaying = false
    @State private var audioURL: URL?
    @State private var testFileSize: String?
    @State private var showingAudioImporter = false
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var sampleStatus: String = ""
    @State private var isExtractingEmbedding = false
    let voices: [VoiceItem]
    let onSave: (CharacterProfile) -> Void

    init(character: CharacterProfile, voices: [VoiceItem], onSave: @escaping (CharacterProfile) -> Void) {
        self._profile = State(initialValue: character)
        self.voices = voices
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("角色信息")) {
                    TextField("名称", text: $profile.name)
                    Picker("性别", selection: $profile.gender) {
                        Text("未知").tag("未知")
                        Text("男性").tag("男性")
                        Text("女性").tag("女性")
                    }
                    Picker("年龄", selection: $profile.age) {
                        Text("未知").tag("未知")
                        Text("儿童").tag("儿童")
                        Text("少年").tag("少年")
                        Text("青年").tag("青年")
                        Text("中年").tag("中年")
                        Text("老年").tag("老年")
                    }
                    TextField("语气", text: $profile.tone)
                }
                Section(header: Text("音色与声纹")) {
                    HStack {
                        Text("声纹状态")
                        Spacer()
                        if profile.hasVoiceSample {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("已克隆").font(.subheadline).foregroundColor(.secondary)
                        } else {
                            Image(systemName: "circle.dashed").foregroundColor(.orange)
                            Text("未克隆").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("语气敏感度")
                        Slider(value: Binding(get: { Double(profile.sensitivity) }, set: { profile.sensitivity = Int($0) }), in: 0...100)
                        Text("\(profile.sensitivity)")
                    }
                }
                Section(header: Text("声纹样本")) {
                    if isExtractingEmbedding {
                        HStack {
                            ProgressView()
                            Text("正在提取声纹…")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    } else if profile.hasVoiceSample {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("已有参考音频").font(.subheadline)
                        }
                        if !sampleStatus.isEmpty {
                            Text(sampleStatus).font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        Text("提供 10-30 秒角色语音样本以克隆声纹")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button(action: { showingAudioImporter = true }) {
                            Label("导入音频", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(isExtractingEmbedding)
                        Button(action: toggleRecording) {
                            Label(isRecording ? "停止录制" : "录制音频", systemImage: isRecording ? "stop.circle" : "mic.circle")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(isExtractingEmbedding)
                        if profile.hasVoiceSample {
                            Button(role: .destructive, action: clearSample) {
                                Label("清除", systemImage: "trash")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(isExtractingEmbedding)
                        }
                    }
                }
                Section(header: Text("试听")) {
                    Button(action: playSample) {
                        HStack {
                            Text(isPlaying ? "合成中..." : "生成并播放音色示例")
                            Spacer()
                            if isPlaying {
                                ProgressView().progressViewStyle(.circular).scaleEffect(0.7)
                            }
                        }
                    }
                    .disabled(isPlaying)
                    if let url = audioURL, !isPlaying {
                        HStack(spacing: 16) {
                            Button(action: {
                                do {
                                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                                    try AVAudioSession.sharedInstance().setActive(true)
                                } catch {}
                                if let p = try? AVAudioPlayer(contentsOf: url) {
                                    samplePlayer = p
                                    p.prepareToPlay()
                                    p.play()
                                }
                            }) {
                                Label("播放", systemImage: "play.circle")
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            Button(action: {
                                samplePlayer?.stop()
                                samplePlayer = nil
                            }) {
                                Label("停止", systemImage: "stop.circle")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            if let size = testFileSize {
                                Text(size).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    if let error = sampleError {
                        Text(error).font(.caption).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(profile.name.isEmpty ? "编辑角色" : profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(profile)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("保存并试听") {
                        onSave(profile)
                        playSample()
                    }
                    .disabled(isPlaying)
                }
            }
            .fileImporter(isPresented: $showingAudioImporter, allowedContentTypes: [.wav, .mp3, .mpeg4Audio, UTType(filenameExtension: "m4a") ?? .audio]) { result in
                handleAudioImport(result)
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = docs.appendingPathComponent("voice-sample-\(UUID().uuidString).wav")
        recordingURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            sampleError = "录制启动失败: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        guard let url = recordingURL, FileManager.default.fileExists(atPath: url.path) else { return }
        guard audioDuration(at: url) ?? 0 >= 3.0 else {
            sampleError = "录音时长不足3秒，请重新录制"
            try? FileManager.default.removeItem(at: url)
            return
        }
        processSample(at: url)
    }

    private func audioDuration(at url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return TimeInterval(file.length) / file.fileFormat.sampleRate
    }

    private func handleAudioImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let copy = docs.appendingPathComponent("voice-sample-\(UUID().uuidString).wav")
            try? FileManager.default.removeItem(at: copy)
            do {
                let data = try Data(contentsOf: url)
                try data.write(to: copy)
                guard audioDuration(at: copy) ?? 0 >= 3.0 else {
                    sampleError = "音频时长不足3秒，请选择更长的样本"
                    try? FileManager.default.removeItem(at: copy)
                    return
                }
                processSample(at: copy)
            } catch {
                sampleError = "导入失败: \(error.localizedDescription)"
            }
        case .failure(let error):
            sampleError = "导入失败: \(error.localizedDescription)"
        }
    }

    private func processSample(at url: URL) {
        Task {
            await MainActor.run { isExtractingEmbedding = true; sampleError = nil }
            do {
                try await CosyVoiceService.shared.ensureModel()
                let embedding = try await CosyVoiceService.shared.enrollSpeaker(name: profile.name, audioURL: url)
                let embeddingData = try JSONEncoder().encode(embedding)
                await MainActor.run {
                    profile.voiceSampleURL = url
                    profile.voiceSampleEmbedding = embeddingData
                    sampleStatus = "声纹已提取 (192维嵌入)"
                    isExtractingEmbedding = false
                }
            } catch {
                await MainActor.run {
                    sampleError = "声纹提取失败: \(error.localizedDescription)"
                    isExtractingEmbedding = false
                }
            }
        }
    }

    private func clearSample() {
        if let url = profile.voiceSampleURL {
            try? FileManager.default.removeItem(at: url)
        }
        profile.voiceSampleURL = nil
        profile.voiceSampleEmbedding = nil
        sampleStatus = ""
    }

    private func playSample() {
        guard !profile.voice.isEmpty else {
            sampleError = "请先为此角色选择一个音色"
            return
        }
        sampleError = nil
        audioURL = nil
        testFileSize = nil
        isPlaying = true
        Task {
            do {
                let text = "我是\(profile.name)，TTS多角色小说阅读器听《\(store.books.first?.title ?? "未知书籍")》真爽。"
                let embedding: [Float]? = profile.voiceSampleEmbedding.flatMap {
                    try? JSONDecoder().decode([Float].self, from: $0)
                }
                let audioData = try await CosyVoiceService.shared.synthesizeSingle(text: text, embedding: embedding)
                testFileSize = "\(String(format: "%.1f", Double(audioData.count) / 1024)) KB"
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {}
                do {
                    samplePlayer = try AVAudioPlayer(data: audioData)
                } catch {
                    throw NSError(domain: "CharacterEditor", code: -1, userInfo: [NSLocalizedDescriptionKey: "音频格式不支持（AVAudioPlayer 初始化失败），文件大小：\(audioData.count) 字节"])
                }
                samplePlayer?.prepareToPlay()
                samplePlayer?.play()
                isPlaying = false
            } catch {
                sampleError = "试听失败: \(error.localizedDescription)"
                isPlaying = false
            }
        }
    }
}
