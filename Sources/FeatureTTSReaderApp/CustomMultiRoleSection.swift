import SwiftUI

/// 自定义多角色测试区域 — 从 TTSView 提取以减少类型检查复杂度
struct CustomMultiRoleSection: View {
    @EnvironmentObject private var store: ReaderStore
    
    @Binding var customMultiRoleText: String
    @Binding var customWorkerSegments: [AISegment]
    @Binding var customCharacterVoices: [String: String]
    @Binding var characterAliases: [String: String]
    @Binding var characterResynthesisStates: [String: Bool]
    @Binding var customSynthesisResult: String
    @Binding var isProcessingWorker: Bool
    @Binding var isSynthesizingCustom: Bool
    @Binding var workerProgress: Double
    @Binding var workerProgressMessage: String
    
    @AppStorage("globalRate") var multiRoleGlobalRate: Double = 0
    @AppStorage("globalVolume") var globalVolumeOffset: Double = 0
    @AppStorage("globalOverlap") var globalOverlapMs: Double = 80
    
    let availableVoices: [EdgeVoiceInfo]
    let selectedServerID: UUID?
    let selectedWorkerID: UUID?
    let aiWorkerConfigs: [AIWorkerConfig]
    let onProcessWithWorker: () -> Void
    let onSynthesizeAndPlay: () -> Void
    let onParseOnly: () -> Void
    
    private func getSelectedWorkerConfig() -> AIWorkerConfig? {
        if let id = selectedWorkerID {
            return aiWorkerConfigs.first { $0.id == id }
        }
        return aiWorkerConfigs.first { $0.isDefault } ?? aiWorkerConfigs.first
    }
    
    private func resolveAlias(_ name: String) -> String {
        var current = name
        var visited = Set<String>()
        var depth = 0
        while let next = characterAliases[current], next != current, !visited.contains(current), depth < 5 {
            visited.insert(current)
            current = next
            depth += 1
        }
        return current
    }
    
    private func voiceForSpeaker(_ speaker: String) -> String {
        if let v = customCharacterVoices[speaker], !v.isEmpty { return v }
        if let main = characterAliases[speaker], let v = customCharacterVoices[main], !v.isEmpty { return v }
        return ""
    }
    
    private func aliasesOf(_ mainName: String) -> [String] {
        characterAliases.filter { $0.value == mainName }.map(\.key).sorted()
    }
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                TextField("粘贴或输入小说文本（AI Worker 解析角色、情绪、语气、流水合成播放）", text: $customMultiRoleText, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(4...8)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                if isProcessingWorker || isSynthesizingCustom {
                    VStack(spacing: 8) {
                        ProgressView(value: workerProgress) {
                            Text(workerProgressMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                
                if !customWorkerSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("解析到 \(customWorkerSegments.count) 个片段，\(Set(customWorkerSegments.map { $0.speaker }).count) 个角色")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                        
                        let speakers: [String] = {
                            var freq: [String: Int] = [:]
                            for s in customWorkerSegments {
                                let main = resolveAlias(s.speaker)
                                freq[main, default: 0] += 1
                            }
                            var sorted = freq.keys.sorted { freq[$0, default: 0] > freq[$1, default: 0] }
                            if let idx = sorted.firstIndex(of: "旁白") {
                                sorted.remove(at: idx)
                                sorted.insert("旁白", at: 0)
                            }
                            return sorted
                        }()
                        let allSpeakers = speakers
                        ForEach(speakers.prefix(10), id: \.self) { speaker in
                            let aliases = aliasesOf(speaker)
                            let speakerSegments = customWorkerSegments.filter { aliases.contains($0.speaker) || $0.speaker == speaker }
                            let segmentCount = speakerSegments.count
                            let emotions = speakerSegments.map { $0.emotion }
                            let emotionSummary = Set(emotions).prefix(3).map { $0.chineseLabel }.joined(separator: "、")
                            let aiGender = speakerSegments.first(where: { $0.gender != .unknown })?.gender
                            let resolvedGender = TTSView.resolveGender(speaker: speaker, aiGender: aiGender)
                            let autoVoiceID = TTSView.autoMatchVoice(for: speaker, gender: resolvedGender, availableVoices: availableVoices)
                            CharacterRoleCard(
                                speaker: speaker,
                                aliases: aliases,
                                segmentCount: segmentCount,
                                emotionSummary: emotionSummary.isEmpty ? nil : emotionSummary,
                                gender: resolvedGender,
                                autoMatchedVoiceID: autoVoiceID,
                                voice: Binding(
                                    get: { voiceForSpeaker(speaker) },
                                    set: { customCharacterVoices[speaker] = $0 }
                                ),
                                isResynthesizing: characterResynthesisStates[speaker] ?? false,
                                availableVoices: availableVoices.filter { $0.locale.hasPrefix("zh-CN") },
                                onResynthesize: { resynthesizeCharacter(speaker) },
                                onMerge: { target in mergeCharacter(speaker, into: target) },
                                onSplit: { alias in splitCharacter(alias) },
                                onDelete: { deleteCharacter(speaker) },
                                onRename: { newName in renameCharacter(speaker, to: newName) },
                                otherSpeakers: allSpeakers.filter { $0 != speaker }
                            )
                        }
                    }
                }
                
                if !customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customSpeakerAnalysisSection
                }
                
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("语速")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(multiRoleGlobalRate))")
                            .font(.caption.monospaced())
                            .frame(width: 24)
                    }
                    Slider(value: $multiRoleGlobalRate, in: -10...10, step: 1)
                }
                .padding(.vertical, 4)
                
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("音量")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(globalVolumeOffset))")
                            .font(.caption.monospaced())
                            .frame(width: 24)
                    }
                    Slider(value: $globalVolumeOffset, in: -10...10, step: 1)
                }
                .padding(.vertical, 4)
                
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("重叠(ms)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(globalOverlapMs))")
                            .font(.caption.monospaced())
                            .frame(width: 48)
                    }
                    Slider(value: $globalOverlapMs, in: 0...500, step: 10)
                }
                .padding(.vertical, 4)
                
                VStack(spacing: 8) {
                    Button {
                        onParseOnly()
                    } label: {
                        HStack {
                            if isProcessingWorker {
                                ProgressView().frame(width: 14, height: 14)
                            }
                            Label("解析", systemImage: "brain.head.profile").fixedSize()
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessingWorker || isSynthesizingCustom || customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || getSelectedWorkerConfig() == nil)
                    
                    Button {
                        onSynthesizeAndPlay()
                    } label: {
                        HStack {
                            if isSynthesizingCustom {
                                ProgressView().frame(width: 14, height: 14)
                            }
                            Label("流式播放", systemImage: "play.circle.fill").fixedSize()
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessingWorker || isSynthesizingCustom || customWorkerSegments.isEmpty || selectedServerID == nil)
                    
                    if !customSynthesisResult.isEmpty {
                        let isSuccess = customSynthesisResult.hasPrefix("已入队") || customSynthesisResult.contains("播放")
                        HStack {
                            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isSuccess ? .green : .red)
                            Text(customSynthesisResult).font(.caption)
                            Spacer()
                        }
                    }
                    
                    if store.audioController.queueCount > 0 || store.audioController.isPlaying {
                        HStack {
                            Button { store.audioController.pause() } label: {
                                HStack(spacing: 6) { Label("暂停", systemImage: "pause.circle.fill").fixedSize() }
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered)
                            Button { store.audioController.resume() } label: {
                                HStack(spacing: 6) { Label("继续", systemImage: "play.circle.fill").fixedSize() }
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered)
                            Button { store.audioController.stop() } label: {
                                HStack(spacing: 6) { Label("停止", systemImage: "stop.circle.fill").fixedSize() }
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered)
                        }
                    }
                    
                    Divider().padding(.vertical, 2)
                    
                    Button {
                        onProcessWithWorker()
                    } label: {
                        HStack(spacing: 6) {
                            Label("AI 解析并流式播放", systemImage: "wand.and.stars").fixedSize()
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessingWorker || isSynthesizingCustom || customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || getSelectedWorkerConfig() == nil || selectedServerID == nil)
                }
            }
        } header: {
            Label("自定义多角色测试", systemImage: "text.bubble.fill")
        }
    }
    
    // MARK: - Speaker Analysis Section
    @ViewBuilder
    private var customSpeakerAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.2.badge.gearshape")
                    .foregroundColor(.secondary)
                Text("预计 TTS 配置（长按复制）")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            
            if !customWorkerSegments.isEmpty {
                let config = buildCustomTTSConfig(from: customWorkerSegments)
                
                if config.isEmpty {
                    Text("未检测到对话，将以旁白身份整段朗读")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(config.keys.sorted()), id: \.self) { speaker in
                        if let info = config[speaker] {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(info.isNarrator ? Color.gray : Color.accentColor)
                                    .frame(width: 6, height: 6)
                                Text("\(speaker)")
                                    .font(.caption2.monospaced())
                                    .fontWeight(.medium)
                                Text("→").font(.caption2).foregroundColor(.secondary)
                                Text("v=\(info.voice)").font(.caption2.monospaced())
                                if info.rate != 0 {
                                    Text("r=\(info.rate)").font(.caption2.monospaced()).foregroundColor(.secondary)
                                }
                                if info.pitch != 0 {
                                    Text("p=\(info.pitch)").font(.caption2.monospaced()).foregroundColor(.secondary)
                                }
                                if !info.style.isEmpty {
                                    Text("s=\(info.style)").font(.caption2.monospaced()).foregroundColor(.secondary)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }
                    
                    let segments = buildSegmentsPreview(from: customWorkerSegments)
                    if !customWorkerSegments.isEmpty {
                        if !segments.isEmpty {
                            Divider().padding(.vertical, 4)
                            Text("原文分段预览")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("\(idx + 1).")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                        .frame(width: 20, alignment: .trailing)
                                    Text("【\(seg.speaker)】\(seg.text)")
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .foregroundColor(seg.speaker == "旁白" ? .secondary : .primary)
                                }
                                .textSelection(.enabled)
                            }
                        }
                    } else {
                    let analyzer = CharacterAnalyzer()
                    let dialogues = analyzer.detectDialogues(in: customMultiRoleText)
                    let simpleMap = buildSimpleSpeakerMap(from: dialogues)
                    
                    if simpleMap.isEmpty {
                        Text("未检测到对话标记，将作为旁白整段发送")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(simpleMap.keys.sorted()), id: \.self) { speaker in
                            if let info = simpleMap[speaker] {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(info.isNarrator ? Color.gray : Color.accentColor)
                                        .frame(width: 6, height: 6)
                                    Text("\(speaker) → v=\(info.voice)")
                                        .font(.caption2.monospaced())
                                }
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Helper Functions (moved from TTSView)
    private struct TTSConfigInfo {
        let voice: String
        let rate: Int
        let pitch: Int
        let style: String
        let isNarrator: Bool
    }
    
    private func buildSimpleSpeakerMap(from dialogues: [DialogueMatch]) -> [String: TTSConfigInfo] {
        var map: [String: TTSConfigInfo] = [:]
        for dialogue in dialogues {
            let speaker = dialogue.speaker ?? "旁白"
            guard map[speaker] == nil else { continue }
            let isNarrator = speaker == "旁白" || speaker.isEmpty
            let hasFemaleIndicators = speaker.contains("女") || speaker.contains("小姐") || speaker.contains("姑娘")
            let voice = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }.first?.id ?? ""
            map[speaker] = TTSConfigInfo(
                voice: voice,
                rate: isNarrator ? 0 : 2,
                pitch: hasFemaleIndicators ? 3 : 0,
                style: "neutral",
                isNarrator: isNarrator
            )
        }
        return map
    }
    
    private func buildCustomTTSConfig(from segments: [AISegment]) -> [String: TTSConfigInfo] {
        var map: [String: TTSConfigInfo] = [:]
        let availableVoices = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }
        let defaultVoice = availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
        
        var charVoiceMap: [String: String] = [:]
        for speaker in Set(segments.map { resolveAlias($0.speaker) }) where speaker != "旁白" {
            let v = voiceForSpeaker(speaker)
            if !v.isEmpty {
                charVoiceMap[speaker] = v
            } else if let matched = availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") }) {
                charVoiceMap[speaker] = matched.id
            }
        }
        let narratorVoice = voiceForSpeaker("旁白").isEmpty
            ? (charVoiceMap["旁白"] ?? availableVoices.first(where: { $0.gender == "Female" })?.id ?? defaultVoice)
            : voiceForSpeaker("旁白")
        
        for speaker in Set(segments.map { resolveAlias($0.speaker) }) {
            let voice: String = {
                let v = voiceForSpeaker(speaker)
                if !v.isEmpty { return v }
                if let cm = charVoiceMap[speaker], !cm.isEmpty { return cm }
                if let matched = availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") }) { return matched.id }
                return defaultVoice
            }()
            let isNarrator = speaker == "旁白"
            let rate = isNarrator ? 0 + Int(multiRoleGlobalRate) : Int(multiRoleGlobalRate)
            let pitch = 0
            let style = ""
            map[speaker] = TTSConfigInfo(
                voice: voice.isEmpty ? "默认" : voice,
                rate: rate,
                pitch: pitch,
                style: style,
                isNarrator: isNarrator
            )
        }
        let narratorRate = 0 + Int(multiRoleGlobalRate)
        map["旁白"] = TTSConfigInfo(
            voice: narratorVoice.isEmpty ? "默认" : narratorVoice,
            rate: narratorRate,
            pitch: 0,
            style: "",
            isNarrator: true
        )
        return map
    }
    
    private struct SegmentPreview {
        let speaker: String
        let text: String
    }
    
    private func buildSegmentsPreview(from segments: [AISegment]) -> [SegmentPreview] {
        return segments.map { SegmentPreview(speaker: $0.speaker, text: $0.text) }
    }
    
    private func resynthesizeCharacter(_ speaker: String) {
        // Implementation in TTSView
    }
    
    private func mergeCharacter(_ source: String, into target: String) {
        guard source != target, !source.isEmpty, !target.isEmpty else { return }
        guard characterAliases[target] == nil else { return }
        characterAliases.removeValue(forKey: source)
        let sourceAliases = characterAliases.filter { $0.value == source }.map(\.key)
        for alias in sourceAliases {
            characterAliases[alias] = target
        }
        characterAliases[source] = target
        if let sv = customCharacterVoices[source], !sv.isEmpty {
            if customCharacterVoices[target] == nil || customCharacterVoices[target]?.isEmpty == true {
                customCharacterVoices[target] = sv
            }
            customCharacterVoices.removeValue(forKey: source)
        }
    }
    
    private func splitCharacter(_ alias: String) {
        characterAliases.removeValue(forKey: alias)
    }
    
    private func deleteCharacter(_ speaker: String) {
        if characterAliases[speaker] != nil {
            characterAliases.removeValue(forKey: speaker)
        }
        customWorkerSegments.removeAll { resolveAlias($0.speaker) == speaker }
        customCharacterVoices.removeValue(forKey: speaker)
        let aliasesToRemove = characterAliases.filter { $0.value == speaker }.map(\.key)
        for alias in aliasesToRemove {
            characterAliases.removeValue(forKey: alias)
        }
    }
    
    private func renameCharacter(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName, characterAliases[trimmed] == nil else { return }
        if characterAliases[oldName] != nil {
            characterAliases[trimmed] = characterAliases.removeValue(forKey: oldName)
        }
        let aliasesToUpdate = characterAliases.filter { $0.value == oldName }.map(\.key)
        for alias in aliasesToUpdate {
            characterAliases[alias] = trimmed
        }
        for i in customWorkerSegments.indices where customWorkerSegments[i].speaker == oldName {
            let seg = customWorkerSegments[i]
            customWorkerSegments[i] = AISegment(speaker: trimmed, emotion: seg.emotion, tone: seg.tone, text: seg.text, gender: seg.gender)
        }
        if let voice = customCharacterVoices[oldName] {
            customCharacterVoices[trimmed] = voice
            customCharacterVoices.removeValue(forKey: oldName)
        }
    }
}