import Foundation

enum TTSUtility {
    /// 根据情绪和偏好计算语速偏移
    static nonisolated func rateOffset(for segment: AISegment, preferredRate: Double? = nil) -> Int {
        var offset = 0
        switch segment.emotion {
        case .angry, .shouting, .excited: offset += 4
        case .happy, .cheerful, .surprised: offset += 2
        case .sad, .fearful, .whispering, .calm, .gentle: offset -= 2
        default: break
        }
        if let pr = preferredRate { offset += Int(pr.rounded()) }
        return offset
    }

    /// 根据说话人名称猜测性别
    static nonisolated func resolveGender(speaker: String, aiGender: Gender?) -> CharacterGender {
        if let g = aiGender, g != .unknown {
            switch g {
            case .male: return .male
            case .female: return .female
            case .unknown: return .unknown
            }
        }
        let isFemale = speaker.contains("女") || speaker.contains("小姐") || speaker.contains("姑娘") || speaker.contains("她") || speaker.contains("姐") || speaker.contains("娘") || speaker.contains("妈") || speaker.contains("婆") || speaker.contains("奶") || speaker.contains("妹") || speaker.contains("嫂") || speaker.contains("婶") || speaker.contains("女士") || speaker.contains("太太") || speaker.contains("夫人")
        let isMale = speaker.contains("公") || speaker.contains("哥") || speaker.contains("爷") || speaker.contains("兄") || speaker.contains("他") || speaker.contains("叔") || speaker.contains("爸") || speaker.contains("父") || speaker.contains("先生") || speaker.contains("少爷") || speaker.contains("公子") || speaker.contains("郎") || speaker.contains("伯") || speaker.contains("舅")
        if isFemale { return .female }
        if isMale { return .male }
        return .unknown
    }

    /// 根据情绪、角色性别和偏好计算音调偏移
    static nonisolated func pitchOffset(for segment: AISegment, speakerName: String, preferredPitch: Double? = nil) -> Int {
        let gender = resolveGender(speaker: speakerName, aiGender: segment.gender)
        let genderOffset: Int = {
            switch gender {
            case .female: return 4
            case .male: return -2
            case .unknown: return speakerName == "旁白" ? 0 : -2
            }
        }()
        let emotionOffset: Int = {
            switch segment.emotion {
            case .excited, .happy, .cheerful: return 3
            case .surprised: return 5
            case .sad, .fearful, .whispering, .calm: return -2
            case .angry, .shouting: return 2
            default: return 0
            }
        }()
        var offset = genderOffset + emotionOffset
        if let pp = preferredPitch { offset += Int(pp.rounded()) }
        return offset
    }

    /// 根据 tone 关键词推导基准音量(dB)，叠加全局滑块偏移，输出 SSML 兼容 dB 值
    static nonisolated func resolvedVolume(tone: String, globalOffset: Double) -> String {
        let t = tone
        let baseDb: Double
        if t.contains("大喊") || t.contains("怒吼") || t.contains("咆哮") || t.contains("吼叫") || t.contains("大喝") || t.contains("厉喝") || t.contains("怒喝") || t.contains("厉声") || t.contains("怒声") || t.contains("高喝") {
            baseDb = 8
        } else if t.contains("喊") || t.contains("叫") || t.contains("嚷") || t.contains("喝令") {
            baseDb = 4
        } else if t.contains("低语") || t.contains("轻声") || t.contains("悄悄") || t.contains("小声") || t.contains("窃窃") || t.contains("低喃") || t.contains("低声道") || t.contains("低声") || t.contains("沉吟") {
            baseDb = -4
        } else if t.contains("耳语") || t.contains("气声") || t.contains("呢喃") || t.contains("默念") || t.contains("无声") {
            baseDb = -8
        } else {
            baseDb = 0
        }
        let total = baseDb + globalOffset * 0.5
        return String(format: "%+.1fdB", total)
    }

    /// 检查 AI Worker 返回结果是否完整
    static nonisolated func isResultComplete(_ segments: [AISegment], originalText: String) -> Bool {
        guard let last = segments.last else { return false }
        guard segments.count >= 2 else {
            return last.text.trimmingCharacters(in: .whitespaces).hasSuffix("。")
                || last.text.hasSuffix("？") || last.text.hasSuffix("！")
                || last.text.hasSuffix("”") || last.text.hasSuffix("』")
        }
        let endsWithPunct = last.text.hasSuffix("。") || last.text.hasSuffix("？")
            || last.text.hasSuffix("！") || last.text.hasSuffix("”") || last.text.hasSuffix("』")
        if endsWithPunct { return true }
        let lastTextRange = originalText.range(of: last.text, options: .backwards)
        guard let range = lastTextRange else { return false }
        let afterText = originalText[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return afterText.isEmpty
    }
}
