import Foundation
import Testing
@testable import FeatureTTSReaderApp

struct StoreAlgorithmTests {

    // MARK: - mergeConsecutiveAISegments

    @Test("合并：相同 speaker/emotion/tone 直接拼接无分隔符")
    func mergeSameSpeakerEmotionTone() {
        let segments = [
            makeSegment(speaker: "A", emotion: .happy, tone: "开心", text: "你好"),
            makeSegment(speaker: "A", emotion: .happy, tone: "开心", text: "世界"),
            makeSegment(speaker: "B", emotion: .sad, tone: "难过", text: "再见")
        ]
        let merged = mergeConsecutiveAISegments(segments)
        #expect(merged.count == 2)
        #expect(merged[0].text == "你好世界")
        #expect(merged[1].text == "再见")
    }

    @Test("不合并：不同 speaker")
    func mergeDifferentSpeaker() {
        let segments = [
            makeSegment(speaker: "A", text: "你好"),
            makeSegment(speaker: "B", text: "世界")
        ]
        let merged = mergeConsecutiveAISegments(segments)
        #expect(merged.count == 2)
    }

    @Test("不合并：不同 emotion")
    func mergeDifferentEmotion() {
        let segments = [
            makeSegment(speaker: "A", emotion: .happy, text: "你好"),
            makeSegment(speaker: "A", emotion: .sad, text: "世界")
        ]
        let merged = mergeConsecutiveAISegments(segments)
        #expect(merged.count == 2)
    }

    @Test("不合并：不同 tone")
    func mergeDifferentTone() {
        let segments = [
            makeSegment(speaker: "A", tone: "开心", text: "你好"),
            makeSegment(speaker: "A", tone: "平静", text: "世界")
        ]
        let merged = mergeConsecutiveAISegments(segments)
        #expect(merged.count == 2)
    }

    @Test("合并保持 gender 取第一段")
    func mergePreservesFirstGender() {
        let segments = [
            makeSegment(speaker: "A", gender: .male, text: "你好"),
            makeSegment(speaker: "A", gender: .female, text: "世界")
        ]
        let merged = mergeConsecutiveAISegments(segments)
        #expect(merged.count == 1)
        #expect(merged[0].gender == .male)
    }

    @Test("空数组返回空")
    func mergeEmpty() {
        let merged = mergeConsecutiveAISegments([])
        #expect(merged.isEmpty)
    }

    @Test("单元素返回自身")
    func mergeSingle() {
        let segments = [makeSegment(text: "单个")]
        let merged = mergeConsecutiveAISegments(segments)
        #expect(merged.count == 1)
        #expect(merged[0].text == "单个")
    }

    // MARK: - VoiceMatchUtility.autoMatchVoice

    @Test("音色匹配：女性优先 Female")
    func voiceMatchFemale() {
        let voices = [
            EdgeVoiceInfo(id: "v1", name: "女声1", gender: "Female", locale: "zh-CN"),
            EdgeVoiceInfo(id: "v2", name: "男声1", gender: "Male", locale: "zh-CN")
        ]
        let voiceID = VoiceMatchUtility.autoMatchVoice(for: "小红", gender: .female, availableVoices: voices)
        #expect(voiceID == "v1")
    }

    @Test("音色匹配：男性优先 Male")
    func voiceMatchMale() {
        let voices = [
            EdgeVoiceInfo(id: "v1", name: "女声1", gender: "Female", locale: "zh-CN"),
            EdgeVoiceInfo(id: "v2", name: "男声1", gender: "Male", locale: "zh-CN")
        ]
        let voiceID = VoiceMatchUtility.autoMatchVoice(for: "小明", gender: .male, availableVoices: voices)
        #expect(voiceID == "v2")
    }

    @Test("音色匹配：unknown 回退首个可用")
    func voiceMatchUnknownFallback() {
        let voices = [
            EdgeVoiceInfo(id: "v1", name: "女声1", gender: "Female", locale: "zh-CN")
        ]
        let voiceID = VoiceMatchUtility.autoMatchVoice(for: "路人", gender: .unknown, availableVoices: voices)
        #expect(voiceID == "v1")
    }

    @Test("音色匹配：空列表回退硬编码")
    func voiceMatchEmptyFallback() {
        let voiceID = VoiceMatchUtility.autoMatchVoice(for: "测试", gender: .female, availableVoices: [])
        #expect(voiceID == "zh-CN-XiaoxiaoNeural")
    }

    @Test("音色匹配：同性别多个取第一个")
    func voiceMatchMultipleSameGender() {
        let voices = [
            EdgeVoiceInfo(id: "v1", name: "女声1", gender: "Female", locale: "zh-CN"),
            EdgeVoiceInfo(id: "v2", name: "女声2", gender: "Female", locale: "zh-CN")
        ]
        let voiceID = VoiceMatchUtility.autoMatchVoice(for: "测试", gender: .female, availableVoices: voices)
        #expect(voiceID == "v1")
    }

    // MARK: - Helpers

    private func makeSegment(
        speaker: String = "A",
        emotion: Emotion = .neutral,
        tone: String = "",
        text: String = "测试",
        gender: Gender = .unknown
    ) -> AISegment {
        AISegment(speaker: speaker, emotion: emotion, tone: tone, text: text, gender: gender)
    }

    // 复制 Store.private 的 mergeConsecutiveAISegments 逻辑用于测试
    private func mergeConsecutiveAISegments(_ segments: [AISegment]) -> [AISegment] {
        guard !segments.isEmpty else { return segments }
        var merged: [AISegment] = []
        var current = segments[0]
        for seg in segments.dropFirst() {
            if seg.speaker == current.speaker && seg.emotion == current.emotion && seg.tone == current.tone {
                current = AISegment(
                    speaker: current.speaker,
                    emotion: current.emotion,
                    tone: current.tone,
                    text: current.text + seg.text,
                    gender: current.gender
                )
            } else {
                merged.append(current)
                current = seg
            }
        }
        merged.append(current)
        return merged
    }
}