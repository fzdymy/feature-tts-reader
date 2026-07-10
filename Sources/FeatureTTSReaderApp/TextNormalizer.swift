import Foundation

struct TextNormalizer {

    /// Minimal normalization: only fix line endings (CRLF→LF) and remove BOM.
    /// Preserves all original text structure, indentation, and spacing.
    static func normalize(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\u{FEFF}", with: "")
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
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
