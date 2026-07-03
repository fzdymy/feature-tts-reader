import SwiftUI
import AVFoundation

struct CharacterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReaderStore
    @State private var profile: CharacterProfile
    @State private var samplePlayer: AVAudioPlayer?
    @State private var sampleError: String?
    @State private var isPlaying = false
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
                    TextField("性别", text: $profile.gender)
                    TextField("年龄", text: $profile.age)
                    TextField("语气", text: $profile.tone)
                }
                Section(header: Text("音色与参数")) {
                    Picker("音色", selection: $profile.voice) {
                        ForEach(voices) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    Stepper("语速：\(profile.rate)", value: $profile.rate, in: -100...100, step: 5)
                    Stepper("音调：\(profile.pitch)", value: $profile.pitch, in: -100...100, step: 5)
                    Picker("风格", selection: $profile.style) {
                        ForEach(["neutral", "cheerful", "sad", "angry"], id: \.self) { style in
                            Text(style).tag(style)
                        }
                    }
                    HStack {
                        Text("语气敏感度")
                        Slider(value: Binding(get: { Double(profile.sensitivity) }, set: { profile.sensitivity = Int($0) }), in: 0...100)
                        Text("\(profile.sensitivity)")
                    }
                    Button(action: {
                        if let rec = store.recommendations.first(where: { $0.profile.id == profile.id }) {
                            if let v = rec.suggestedVoices.first?.id {
                                profile.voice = v
                            }
                        }
                    }) {
                        Text("应用推荐音色")
                    }
                }
                Section(header: Text("试听")) {
                    Button(action: playSample) {
                        HStack {
                            Text(isPlaying ? "播放中..." : "播放当前音色示例")
                            Spacer()
                            if isPlaying {
                                ProgressView().progressViewStyle(.circular).scaleEffect(0.7)
                            }
                        }
                    }
                    .disabled(isPlaying)
                    if let error = sampleError {
                        Text(error).font(.caption).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(profile.name.isEmpty ? "编辑角色" : profile.name)
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
        }
    }

    private func playSample() {
        guard let url = URL(string: store.apiEndpoint) else {
            sampleError = "无效的 TTS 服务地址，请在「TTS」标签页配置服务器"
            return
        }
        guard !profile.voice.isEmpty else {
            sampleError = "请先为此角色选择一个音色"
            return
        }
        sampleError = nil
        isPlaying = true
        let request = TTSHttpClient(baseURL: url, apiKey: store.apiKey.isEmpty ? nil : store.apiKey)
        Task {
            do {
                let text = "我是\(profile.name)，TTS多角色小说阅读器听《\(store.books.first?.title ?? "未知书籍")》真爽。"
                let audioURL = try await request.synthesizeAudio(text: text, voice: profile.voice, rate: profile.rate, pitch: profile.pitch, style: profile.style)
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {}
                do {
                    samplePlayer = try AVAudioPlayer(contentsOf: audioURL)
                } catch {
                    if let data = try? Data(contentsOf: audioURL) {
                        do {
                            samplePlayer = try AVAudioPlayer(data: data)
                        } catch {
                            let contentType = (try? Data(contentsOf: audioURL))?.prefix(20).map { String(format: "%02x", $0) }.joined() ?? "?"
                            throw NSError(domain: "CharacterEditor", code: -1, userInfo: [NSLocalizedDescriptionKey: "音频格式不支持（AVAudioPlayer 初始化失败），文件大小：\((try? Data(contentsOf: audioURL).count ?? 0) ?? 0) 字节，数据头部：\(contentType)"])
                        }
                    } else {
                        throw NSError(domain: "CharacterEditor", code: -1, userInfo: [NSLocalizedDescriptionKey: "音频文件读取失败: \(error.localizedDescription)"])
                    }
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
