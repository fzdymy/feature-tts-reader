import Foundation

/// Standalone utility for matching character voices based on gender and availability.
enum VoiceMatchUtility {
    /// Automatically match a voice for a speaker based on gender.
    static func autoMatchVoice(for speaker: String, gender: CharacterGender, availableVoices: [EdgeVoiceInfo]) -> String {
        let zhVoices = availableVoices.filter { $0.locale.hasPrefix("zh-CN") }
        let defaultVoices: [EdgeVoiceInfo] = [
            EdgeVoiceInfo(id: "zh-CN-XiaoxiaoNeural", name: "小晓", gender: "Female", locale: "zh-CN"),
            EdgeVoiceInfo(id: "zh-CN-YunxiNeural", name: "云希", gender: "Male", locale: "zh-CN"),
        ]
        let voices = zhVoices.isEmpty ? defaultVoices : zhVoices

        let resolved: CharacterGender = {
            if gender != .unknown { return gender }
            // Fallback: resolve gender from speaker name
            return resolveGenderFromName(speaker)
        }()

        switch resolved {
        case .female:
            let f = voices.filter { $0.gender == "Female" }
            return f.first?.id ?? voices.first?.id ?? "zh-CN-XiaoxiaoNeural"
        case .male:
            let m = voices.filter { $0.gender == "Male" }
            return m.first?.id ?? voices.first?.id ?? "zh-CN-YunxiNeural"
        case .unknown:
            return voices.first?.id ?? "zh-CN-XiaoxiaoNeural"
        }
    }

    /// Resolve gender from speaker name using common Chinese name patterns.
    static func resolveGenderFromName(_ name: String) -> CharacterGender {
        let femaleKeywords = ["女", "小姐", "姑娘", "她", "姐", "妹", "妈", "妻", "媳妇", "公主", "阿姨", "奶奶"]
        let maleKeywords = ["男", "先生", "哥", "弟", "爸", "父", "丈夫", "老公", "王子", "公子"]

        for kw in femaleKeywords { if name.contains(kw) { return .female } }
        for kw in maleKeywords { if name.contains(kw) { return .male } }
        return .unknown
    }
}