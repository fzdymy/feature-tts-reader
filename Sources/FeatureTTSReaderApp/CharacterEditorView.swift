import SwiftUI
import AVFoundation

struct CharacterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReaderStore
    @State private var profile: CharacterProfile
    @State private var samplePlayer: AVAudioPlayer?
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
                        // apply recommended voice if available
                        if let rec = store.recommendations.first(where: { $0.profile.id == profile.id }) {
                            if let v = rec.suggestedVoices.first?.id {
                                profile.voice = v
                            }
                        }
                    }) {
                        Text("重置为推荐音色")
                    }
                    Button(action: {
                        // apply first suggested voice to current character only (local edit)
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
                        Text("播放当前音色示例")
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
                }
            }
        }
    }

    private func playSample() {
        guard let url = URL(string: store.apiEndpoint) else {
            debugPrint("试听失败：无效的 TTS 服务地址")
            return
        }
        let request = TTSHttpClient(baseURL: url, apiKey: store.apiKey.isEmpty ? nil : store.apiKey)
        Task {
            do {
                let text = "你好，我是 \(profile.name)，这是我的声音示例。"
                let url = try await request.synthesizeAudio(text: text, voice: profile.voice, rate: profile.rate, pitch: profile.pitch, style: profile.style)
                samplePlayer = try AVAudioPlayer(contentsOf: url)
                samplePlayer?.prepareToPlay()
                samplePlayer?.play()
            } catch {
                debugPrint("试听失败：\(error.localizedDescription)")
            }
        }
    }
}
