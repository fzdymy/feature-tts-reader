import SwiftUI

struct FontItem: Hashable {
    let postScriptName: String
    let displayName: String

    static func displayNameFor(_ name: String) -> String {
        let known: [String: String] = [
            "PingFangSC-Regular": "苹方", "PingFangSC-Medium": "苹方中黑",
            "PingFangSC-Semibold": "苹方粗体",
            "STHeitiSC-Light": "黑体", "STHeitiSC-Medium": "黑体中",
            "STSongti-SC-Regular": "宋体", "STSongti-SC-Bold": "宋体粗",
            "STKaitiSC-Regular": "楷体", "STKaitiSC-Bold": "楷体粗",
            "STFangsong": "仿宋",
            "HiraMinProN-W3": "明朝", "HiraMinProN-W6": "明朝粗",
            "NotoSansCJKsc-Regular": "思源黑体", "NotoSansCJKsc-Medium": "思源黑体中",
            "NotoSerifCJKsc-Regular": "思源宋体", "NotoSerifCJKsc-Bold": "思源宋体粗",
            "SourceHanSerifSC-Regular": "源ノ明朝", "SourceHanSerifSC-Bold": "源ノ明朝粗",
        ]
        if let chinese = known[name] { return chinese }
        return name.replacingOccurrences(of: "SC-", with: "SC ").replacingOccurrences(of: "-", with: " ")
    }
}

struct FontManager {
    static let availableFonts: [FontItem] = {
        let cjkFamilies = UIFont.familyNames.filter {
            $0.localizedCaseInsensitiveContains("PingFang") ||
            $0.localizedCaseInsensitiveContains("Heiti") ||
            $0.localizedCaseInsensitiveContains("STHeiti") ||
            $0.localizedCaseInsensitiveContains("Hiragino") ||
            $0.localizedCaseInsensitiveContains("Songti") ||
            $0.localizedCaseInsensitiveContains("Noto") ||
            $0.localizedCaseInsensitiveContains("Source Han") ||
            $0.localizedCaseInsensitiveContains("Kaiti") ||
            $0.localizedCaseInsensitiveContains("Fangsong") ||
            $0.localizedCaseInsensitiveContains("YuanTi") ||
            $0.localizedCaseInsensitiveContains("Xingkai")
        }
        var fonts: [FontItem] = []
        for family in cjkFamilies {
            for name in UIFont.fontNames(forFamilyName: family) {
                fonts.append(FontItem(postScriptName: name, displayName: FontItem.displayNameFor(name)))
            }
        }
        if fonts.isEmpty {
            let fallback = ["PingFangSC-Regular", "PingFangSC-Medium", "PingFangSC-Semibold",
                           "STHeitiSC-Light", "STHeitiSC-Medium", "STSongti-SC-Regular",
                           "HiraMinProN-W3", "HiraMinProN-W6", "NotoSansCJKsc-Regular"]
            fonts = fallback.map { FontItem(postScriptName: $0, displayName: FontItem.displayNameFor($0)) }
        }
        return fonts
    }()
}
