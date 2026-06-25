import SwiftUI
import AVFoundation

struct CharacterEditorView: View {
    @Environment(\.dismiss) private var dismiss
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
            }
        }
    }

    private func playSample() {
        let request = TTSHttpClient(baseURL: URL(string: UserDefaults.standard.string(forKey: "ReaderStore.apiEndpoint") ?? "http://127.0.0.1:8080")!, apiKey: UserDefaults.standard.string(forKey: "ReaderStore.apiKey") ?? nil)
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
