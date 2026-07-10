import Foundation

struct TextNormalizer {

    /// Normalize: fix line endings, remove BOM, strip leading full-width spaces
    /// (app manages indentation via firstLineIndent setting).
    static func normalize(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\u{FEFF}", with: "")
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        let lines = s.components(separatedBy: "\n")
        let stripped = lines.map { $0.hasPrefix("\u{3000}") ? String($0.drop(while: { $0 == "\u{3000}" })) : $0 }
        s = stripped.joined(separator: "\n")
        return s
    }

    /// Whitespace set that preserves \u{3000} (full-width space, Chinese indent).
    /// Use this instead of `.whitespacesAndNewlines` when trimming paragraph text.
    static let nonIndentWhitespace: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.remove(charactersIn: "\u{3000}")
        return set
    }()
}
