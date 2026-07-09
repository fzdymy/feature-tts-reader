import SwiftUI
import AVFoundation

struct CharacterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReaderStore
    @State private var profile: CharacterProfile
    @State private var samplePlayer: AVAudioPlayer?
    @State private var sampleError: String?
    @State private var isPlaying = false
    @State private var testFileSize: String?
    let onSave: (CharacterProfile) -> Void

    init(character: CharacterProfile, onSave: @escaping (CharacterProfile) -> Void) {
        self._profile = State(initialValue: character)
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
                    if let size = testFileSize, !isPlaying {
                        Text("文件大小: \(size)").font(.caption2).foregroundColor(.secondary)
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
        }
    }

    private func playSample() {
        sampleError = nil
        testFileSize = nil
        isPlaying = true
        Task {
            do {
                let text = "我是\(profile.name)，TTS多角色小说阅读器听《\(store.books.first?.title ?? "未知书籍")》真爽。"
                let audioData = try await EdgeTTSService.shared.synthesize(text: text, voice: profile.voice.isEmpty ? nil : profile.voice)
                testFileSize = "\(String(format: "%.1f", Double(audioData.count) / 1024)) KB"
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {}
                do {
                    samplePlayer = try AVAudioPlayer(data: audioData)
                    samplePlayer?.prepareToPlay()
                    samplePlayer?.play()
                } catch {
                    throw NSError(domain: "CharacterEditor", code: -1, userInfo: [NSLocalizedDescriptionKey: "音频格式不支持，文件大小：\(audioData.count) 字节"])
                }
                isPlaying = false
            } catch {
                sampleError = "试听失败: \(error.localizedDescription)"
                isPlaying = false
            }
        }
    }
}
