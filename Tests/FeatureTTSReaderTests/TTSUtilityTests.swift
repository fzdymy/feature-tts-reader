import Foundation
import Testing
@testable import FeatureTTSReaderApp

struct TTSUtilityTests {

    // MARK: - splitBlockIntoSentences

    @Test("分割中文句子：基本标点")
    func splitChineseSentences() {
        let text = "你好世界。今天天气真好！你好吗？"
        let sentences = TTSUtility.splitBlockIntoSentences(text)
        #expect(sentences == ["你好世界。", "今天天气真好！", "你好吗？"])
    }

    @Test("分割混合中英文标点")
    func splitMixedPunctuation() {
        let text = "Hello world. 你好世界！How are you? 你好吗？"
        let sentences = TTSUtility.splitBlockIntoSentences(text)
        #expect(sentences == ["Hello world.", "你好世界！", "How are you?", "你好吗？"])
    }

    @Test("分割无标点文本")
    func splitNoPunctuation() {
        let text = "这是一段没有标点的文本"
        let sentences = TTSUtility.splitBlockIntoSentences(text)
        #expect(sentences == ["这是一段没有标点的文本"])
    }

    @Test("分割空字符串")
    func splitEmptyString() {
        let sentences = TTSUtility.splitBlockIntoSentences("")
        #expect(sentences == [""])
    }

    @Test("分割包含全角空格缩进")
    func splitWithIndent() {
        let text = "\u{3000}\u{3000}第一章。\u{3000}内容开始。"
        let sentences = TTSUtility.splitBlockIntoSentences(text)
        #expect(sentences.count == 2)
        #expect(sentences[0].hasPrefix("\u{3000}\u{3000}"))
    }

    @Test("分割连续标点")
    func splitConsecutivePunctuation() {
        let text = "你好。。。世界！！！"
        let sentences = TTSUtility.splitBlockIntoSentences(text)
        #expect(sentences == ["你好。。。", "世界！！！"])
    }

    // MARK: - rateOffset

    @Test("语速偏移：愤怒情绪加速")
    func rateOffsetAngry() {
        let segment = makeSegment(emotion: .angry)
        #expect(TTSUtility.rateOffset(for: segment) == 4)
    }

    @Test("语速偏移：开心情绪加速")
    func rateOffsetHappy() {
        let segment = makeSegment(emotion: .happy)
        #expect(TTSUtility.rateOffset(for: segment) == 2)
    }

    @Test("语速偏移：悲伤情绪减速")
    func rateOffsetSad() {
        let segment = makeSegment(emotion: .sad)
        #expect(TTSUtility.rateOffset(for: segment) == -2)
    }

    @Test("语速偏移：叠加 preferredRate")
    func rateOffsetWithPreferredRate() {
        let segment = makeSegment(emotion: .neutral)
        #expect(TTSUtility.rateOffset(for: segment, preferredRate: 5) == 5)
        #expect(TTSUtility.rateOffset(for: segment, preferredRate: -3) == -3)
    }

    // MARK: - pitchOffset

    @Test("音调偏移：女性角色基础 +4")
    func pitchOffsetFemale() {
        let segment = makeSegment(emotion: .neutral, gender: .female)
        #expect(TTSUtility.pitchOffset(for: segment, speakerName: "小红") == 4)
    }

    @Test("音调偏移：男性角色基础 -2")
    func pitchOffsetMale() {
        let segment = makeSegment(emotion: .neutral, gender: .male)
        #expect(TTSUtility.pitchOffset(for: segment, speakerName: "小明") == -2)
    }

    @Test("音调偏移：旁白基础 0")
    func pitchOffsetNarrator() {
        let segment = makeSegment(emotion: .neutral, gender: .unknown)
        #expect(TTSUtility.pitchOffset(for: segment, speakerName: "旁白") == 0)
    }

    @Test("音调偏移：激动情绪 +3")
    func pitchOffsetExcited() {
        let segment = makeSegment(emotion: .excited, gender: .female)
        // female(+4) + excited(+3) = 7
        #expect(TTSUtility.pitchOffset(for: segment, speakerName: "小红") == 7)
    }

    @Test("音调偏移：叠加 preferredPitch")
    func pitchOffsetWithPreferredPitch() {
        let segment = makeSegment(emotion: .neutral, gender: .female)
        #expect(TTSUtility.pitchOffset(for: segment, speakerName: "小红", preferredPitch: 5) == 9) // 4+5
    }

    // MARK: - resolvedVolume

    @Test("音量解析：大喊关键词 8dB")
    func volumeShout() {
        let volume = TTSUtility.resolvedVolume(tone: "大喊一声", globalOffset: 0)
        #expect(volume == "+8.0dB")
    }

    @Test("音量解析：低语关键词 -4dB")
    func volumeWhisper() {
        let volume = TTSUtility.resolvedVolume(tone: "低语", globalOffset: 0)
        #expect(volume == "-4.0dB")
    }

    @Test("音量解析：耳语关键词 -8dB")
    func volumeWhispering() {
        let volume = TTSUtility.resolvedVolume(tone: "耳语", globalOffset: 0)
        #expect(volume == "-8.0dB")
    }

    @Test("音量解析：全局偏移叠加")
    func volumeGlobalOffset() {
        let volume = TTSUtility.resolvedVolume(tone: "大喊", globalOffset: 4) // 8 + 4*0.5 = 10
        #expect(volume == "+10.0dB")
    }

    @Test("音量解析：普通语气 0dB")
    func volumeNormal() {
        let volume = TTSUtility.resolvedVolume(tone: "平静", globalOffset: 0)
        #expect(volume == "+0.0dB")
    }

    // MARK: - resolveGender

    @Test("性别推断：AI 提供 female")
    func genderAIFemale() {
        let gender = TTSUtility.resolveGender(speaker: "未知", aiGender: .female)
        #expect(gender == .female)
    }

    @Test("性别推断：AI unknown 回退名字关键词")
    func genderFallbackFemale() {
        let gender = TTSUtility.resolveGender(speaker: "小姐姐", aiGender: .unknown)
        #expect(gender == .female)
    }

    @Test("性别推断：AI unknown 回退名字关键词男性")
    func genderFallbackMale() {
        let gender = TTSUtility.resolveGender(speaker: "先生", aiGender: .unknown)
        #expect(gender == .male)
    }

    @Test("性别推断：完全未知返回 unknown")
    func genderUnknown() {
        let gender = TTSUtility.resolveGender(speaker: "路人甲", aiGender: .unknown)
        #expect(gender == .unknown)
    }

    // MARK: - isResultComplete

    @Test("结果完整：末尾句号且段数>=2")
    func resultCompleteWithPeriod() {
        let segments = [
            makeSegment(speaker: "A", text: "你好。"),
            makeSegment(speaker: "B", text: "你好。")
        ]
        #expect(TTSUtility.isResultComplete(segments, originalText: "你好。你好。") == true)
    }

    @Test("结果不完整：单段且无标点")
    func resultIncompleteSingleNoPunct() {
        let segments = [makeSegment(speaker: "A", text: "你好")]
        #expect(TTSUtility.isResultComplete(segments, originalText: "你好") == false)
    }

    @Test("结果完整：单段但有结束标点")
    func resultCompleteSingleWithPunct() {
        let segments = [makeSegment(speaker: "A", text: "你好。")]
        #expect(TTSUtility.isResultComplete(segments, originalText: "你好。") == true)
    }

    @Test("结果不完整：最后一段无标点且原文有剩余")
    func resultIncompleteRemainingText() {
        let segments = [makeSegment(speaker: "A", text: "你好")]
        #expect(TTSUtility.isResultComplete(segments, originalText: "你好世界") == false)
    }

    @Test("结果完整：引号结尾")
    func resultCompleteWithQuote() {
        let segments = [
            makeSegment(speaker: "A", text: "他说：\"你好\""),
            makeSegment(speaker: "B", text: "\"好的\"")
        ]
        #expect(TTSUtility.isResultComplete(segments, originalText: "他说：\"你好\"\"好的\"") == true)
    }

    // MARK: - Helpers

    private func makeSegment(speaker: String = "测试", emotion: Emotion = .neutral, gender: Gender = .unknown, text: String = "测试文本") -> AISegment {
        AISegment(speaker: speaker, emotion: emotion, tone: "", text: text, gender: gender)
    }
}