private func synthesizeAndPlayCustom() {
        guard let id = selectedServerID,
              let result = customScanResult,
              !result.characters.isEmpty else { return }

        isSynthesizingCustom = true
        customSynthesisResult = "正在分析对话..."
        
        Task {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            
            // Use CharacterAnalyzer to detect dialogues with speakers
            let analyzer = CharacterAnalyzer()
            let dialogues = analyzer.detectDialogues(in: customMultiRoleText)
            
            // Build character name -> voice mapping
            var charVoiceMap: [String: String] = [:]
            for profile in result.characters {
                if let voiceID = customCharacterVoices[profile.name], !voiceID.isEmpty {
                    charVoiceMap[profile.name] = voiceID
                } else if let matched = availableVoices.first(where: { 
                    $0.locale.hasPrefix("zh-CN") && 
                    (profile.gender == "Male" && $0.gender == "Male" || profile.gender == "Female" && $0.gender == "Female")
                }) {
                    charVoiceMap[profile.name] = matched.id
                }
            }
            
            // Fixed narrator voice - always use female voice for narrator
            let narratorVoiceID = charVoiceMap["旁白"] ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") && $0.gender == "Female" })?.id ?? ""
            let defaultVoiceID = charVoiceMap.values.first ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
            
            // Build known characters set for speaker matching
            let knownCharacters = Set(result.characters.map { $0.name })
            
            // First, use detectDialogues to get dialogue positions
            let dialogues = analyzer.detectDialogues(in: customMultiRoleText)
            
            // For each dialogue, try to infer a better speaker using the known characters
            var dialoguesWithSpeakers: [(speaker: String?, content: String, range: Range<String.Index>)] = []
            for dialogue in dialogues {
                var speaker = dialogue.speaker
                // If no speaker detected, try to infer from context using known characters
                if speaker == nil || speaker?.isEmpty == true {
                    // Get context before the dialogue (300 chars before)
                    let lower = dialogue.range.lowerBound
                    let beforeEnd = customMultiRoleText.index(customMultiRoleText.startIndex, offsetBy: customMultiRoleText.distance(from: customMultiRoleText.startIndex, to: lower))
                    let beforeStart = customMultiRoleText.index(beforeEnd, offsetBy: -min(300, customMultiRoleText.distance(from: customMultiRoleText.startIndex, to: beforeEnd)), limitedBy: customMultiRoleText.startIndex) ?? customMultiRoleText.startIndex
                    let context = String(customMultiRoleText[beforeStart..<beforeEnd])
                    
                    // Try to infer speaker from context using known characters
                    if let inferred = analyzer.inferSpeaker(from: context, knownCharacters: Array(knownCharacters)) {
                        speaker = inferred
                    }
                }
                dialoguesWithSpeakers.append((speaker: speaker, content: dialogue.content, range: dialogue.range))
            }
            
            // Segment text into dialogue and narration using CharacterAnalyzer
            var segments: [(speaker: String?, text: String)] = []
            var lastEnd = customMultiRoleText.startIndex
            
            for dialogue in dialoguesWithSpeakers {
                // Add narration before this dialogue
                if dialogue.range.lowerBound > lastEnd {
                    let narrationText = String(customMultiRoleText[lastEnd..<dialogue.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !narrationText.isEmpty {
                        segments.append((speaker: "旁白", text: narrationText))
                    }
                }
                // Add the dialogue with its speaker
                let speakerName = dialogue.speaker ?? ""
                var matchedSpeaker: String? = nil
                if !speakerName.isEmpty {
                    if knownCharacters.contains(speakerName) {
                        matchedSpeaker = speakerName
                    } else {
                        // Try to find character who has this as alias
                        for profile in result.characters {
                            if profile.aliases.contains(speakerName) || profile.name.contains(speakerName) || speakerName.contains(profile.name) {
                                matchedSpeaker = profile.name
                                break
                            }
                        }
                    }
                }
                segments.append((speaker: matchedSpeaker, text: dialogue.content))
                lastEnd = dialogue.range.upperBound
            }
            // Trailing narration
            if lastEnd < customMultiRoleText.endIndex {
                let trailing = String(customMultiRoleText[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trailing.isEmpty {
                    segments.append((speaker: "旁白", text: trailing))
                }
            }
            
            // If no dialogues detected, fall back to sentence splitting
            if segments.isEmpty {
                let text = customMultiRoleText.trimmingCharacters(in: .whitespacesAndNewlines)
                let sentences = text.split { "。！？.!?".contains($0) }.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                for sentence in sentences {
                    segments.append((speaker: "旁白", text: sentence))
                }
            }
            
            // Remove empty segments
            let validSegments = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let total = validSegments.count
            guard total > 0 else {
                await MainActor.run {
                    customSynthesisResult = "未检测到可合成内容"
                    isSynthesizingCustom = false
                }
                return
            }
            
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            
            // Build character name -> voice mapping
            var charVoiceMap: [String: String] = [:]
            for profile in result.characters {
                if let voiceID = customCharacterVoices[profile.name], !voiceID.isEmpty {
                    charVoiceMap[profile.name] = voiceID
                } else if let matched = availableVoices.first(where: { 
                    $0.locale.hasPrefix("zh-CN") && 
                    (profile.gender == "Male" && $0.gender == "Male" || profile.gender == "Female" && $0.gender == "Female")
                }) {
                    charVoiceMap[profile.name] = matched.id
                }
            }
            // Fixed narrator voice - always use female voice for narrator
            let narratorVoiceID = charVoiceMap["旁白"] ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") && $0.gender == "Female" })?.id ?? ""
            let defaultVoiceID = charVoiceMap.values.first ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
            
            let rate = multiRoleGlobalRate
            let pitch = 0.0
            
            // PRE-SYNTHESIZE FIRST 3 SEGMENTS BEFORE STARTING PLAYBACK
            let preSynthesizeCount = min(3, validSegments.count)
            var preSynthesizedItems: [TTSQueueItem] = []
            
            for i in 0..<preSynthesizeCount {
                let segment = validSegments[i]
                let speaker = segment.speaker ?? "旁白"
                let voiceID: String
                if speaker == "旁白" {
                    voiceID = narratorVoiceID.isEmpty ? (availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") && $0.gender == "Female" })?.id ?? "") : narratorVoiceID
                } else {
                    voiceID = charVoiceMap[segment.speaker ?? "旁白"] ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
                }
                let rate = multiRoleGlobalRate
                let pitch = 0.0
                
                do {
                    let segText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !segText.isEmpty else { continue }
                    
                    let audioData = try await EdgeTTSService.shared.synthesize(
                        text: segment.text,
                        voice: voiceID,
                        rate: rate,
                        pitch: pitch,
                        style: "",
                        serverID: id
                    )
                    let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                    let url = cachesDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                    try audioData.write(to: url, options: .atomic)
                    
                    let speakerName = segment.speaker ?? "旁白"
                    let segmentItem = ScriptSegment(
                        id: UUID(),
                        characterName: speakerName,
                        voice: voiceID,
                        rate: Int(rate),
                        pitch: Int(pitch),
                        style: "",
                        text: segment.text,
                        emotionTag: "",
                        paragraphIndex: idx
                    )
                    let item = TTSQueueItem(
                        segment: segment,
                        audioURL: url,
                        audioData: audioData,
                        chapterTitle: "自定义多角色",
                        bookTitle: "测试",
                        bookID: "test",
                        chapterIndex: 0,
                        segmentIndex: idx,
                        totalSegments: validSegments.count,
                        paragraphIndex: idx,
                        sentenceIndex: nil,
                        anchor: nil
                    )
                    preSynthesizedItems.append(item)
                    
                    await MainActor.run {
                        customSynthesisResult = "已预合成 \(idx + 1)/\(preSynthesizeCount) 段..."
                    }
                } catch {
                    await MainActor.run {
                        customSynthesisResult = "预合成失败: \(error.localizedDescription)"
                        isSynthesizingCustom = false
                    }
                    return
                }
            }
            
            // Start playback with pre-synthesized items
            await MainActor.run {
                store.audioController.appendToQueue(preSynthesizedItems)
                customSynthesisResult = "第 1/\(validSegments.count) 段合成完成，开始播放..."
            }
            
            // 2. Synthesize remaining segments in background
            await MainActor.run { customSynthesisResult = "第 1 段播放中，后台合成剩余 \(validSegments.count - preSynthesizedItems.count) 段..." }
            var restItems: [TTSQueueItem] = []
            
            for (idx, segment) in validSegments.dropFirst(preSynthesizeCount).enumerated() {
                let speaker = segment.speaker ?? "旁白"
                let voiceID: String
                if speaker == "旁白" {
                    voiceID = narratorVoiceID.isEmpty ? (availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") && $0.gender == "Female" })?.id ?? "") : narratorVoiceID
                } else {
                    voiceID = charVoiceMap[segment.speaker ?? "旁白"] ?? availableVoices.first(where: { $0.locale.hasPrefix("zh-CN") })?.id ?? ""
                }
                let rate = multiRoleGlobalRate
                let pitch = 0.0
                
                do {
                    let segText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !segText.isEmpty else { continue }
                    
                    let audioData = try await EdgeTTSService.shared.synthesize(
                        text: segment.text,
                        voice: voiceID,
                        rate: rate,
                        pitch: pitch,
                        style: "",
                        serverID: id
                    )
                    let ext = EdgeTTSService.isMP3Data(audioData) ? "mp3" : "wav"
                    let url = cachesDir.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
                    try audioData.write(to: url, options: .atomic)
                    
                    let speakerName = segment.speaker ?? "旁白"
                    let seg = ScriptSegment(
                        id: UUID(),
                        characterName: speakerName,
                        voice: voiceID,
                        rate: Int(rate),
                        pitch: Int(pitch),
                        style: "",
                        text: segment.text,
                        emotionTag: "",
                        paragraphIndex: idx + 1
                    )
                    let item = TTSQueueItem(
                        segment: seg,
                        audioURL: url,
                        audioData: audioData,
                        chapterTitle: "自定义多角色",
                        bookTitle: "测试",
                        bookID: "test",
                        chapterIndex: 0,
                        segmentIndex: idx + 1,
                        totalSegments: validSegments.count,
                        paragraphIndex: idx + 1,
                        sentenceIndex: nil,
                        anchor: nil
                    )
                    restItems.append(item)
                    
                    await MainActor.run {
                        customSynthesisResult = "已合成 \(idx + 1 + preSynthesizeCount)/\(validSegments.count) 段..."
                    }
                } catch {
                    // Log error but continue with remaining segments
                    await MainActor.run {
                        customSynthesisResult = "第 \(idx + 2) 段合成失败: \(error.localizedDescription)，继续下一段..."
                    }
                    // Continue with next segment instead of returning
                }
            }
            
            // 3. Enqueue all remaining segments
            await MainActor.run {
                store.audioController.appendToQueue(restItems)
                customSynthesisResult = "\(validSegments.count)/\(validSegments.count) 段全部入队，正在流式播放"
                isSynthesizingCustom = false
            }
        }
    }
}