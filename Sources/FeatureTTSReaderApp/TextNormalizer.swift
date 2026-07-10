import Foundation

struct TextNormalizer {

    /// Lightweight normalization: line endings, trailing whitespace, control chars, NFC.
    /// Does NOT merge lines or detect paragraphs — use `reformatChineseNovel` for that.
    static func normalize(_ text: String) -> String {
        var s = text

        // 1. Remove BOM and zero-width characters
        s = s.replacingOccurrences(of: "\u{FEFF}", with: "")
        s = s.replacingOccurrences(of: "\u{200B}", with: "")
        s = s.replacingOccurrences(of: "\u{200C}", with: "")
        s = s.replacingOccurrences(of: "\u{200D}", with: "")
        s = s.replacingOccurrences(of: "\u{2060}", with: "")

        // 2. Normalize line endings: CRLF → LF, CR → LF
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")

        // 3. Strip trailing whitespace per line (preserve leading indentation)
        var lines = s.components(separatedBy: "\n")
        for i in lines.indices {
            if let lastNonSpace = lines[i].lastIndex(where: { !$0.isWhitespace }) {
                lines[i] = String(lines[i][...lastNonSpace])
            } else {
                lines[i] = ""
            }
        }
        s = lines.joined(separator: "\n")

        // 4. Collapse excessive blank lines (≥3 consecutive → 2)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        // 5. Collapse multiple horizontal spaces (2+ → 1)
        s = s.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

        // 6. Remove stray control characters except \n, \t
        s = s.unicodeScalars.filter { c in
            c == "\n" || c == "\t" || !CharacterSet.controlCharacters.contains(c)
        }.map(String.init).joined()

        // 7. NFC normalization (composed form) — preferred for Han text
        s = s.precomposedStringWithCanonicalMapping

        return s
    }

    /// Smart reformat for Chinese novel text:
    ///   - Detect paragraph boundaries (。！？, opening quotes `“`, short standalone lines ≤6 CJK chars)
    ///   - Join hard-wrapped continuations within each paragraph
    ///   - Add 2 full-width space indentation (　　)
    static func reformatChineseNovel(_ raw: String) -> String {
        // --- Phase 1: basic cleanup (line endings, trailing spaces) ---
        var s = raw
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")

        var lines = s.components(separatedBy: "\n")
        for i in lines.indices {
            lines[i] = lines[i].trimmingCharacters(in: .whitespaces)
        }

        // --- Phase 2: smart paragraph rebuilding ---
        let terminators = "。！？"
        let openQuotes  = "“"

        var paragraphs: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line
            guard !trimmed.isEmpty else {
                if !current.isEmpty { paragraphs.append(current); current = "" }
                continue
            }

            if current.isEmpty {
                current = trimmed
                continue
            }

            // Determine if this line starts a new paragraph
            let lastChar = current.last ?? " "
            let firstChar = trimmed.first ?? " "
            let prevEndsWithTerminator = terminators.contains(lastChar)
            let startsWithOpenQuote = openQuotes.contains(firstChar)
            let prevIsShort = current.utf16.count <= 6
            let curIsShort = trimmed.utf16.count <= 6

            let isNewParagraph = prevEndsWithTerminator || startsWithOpenQuote || (prevIsShort && curIsShort)

            if isNewParagraph {
                paragraphs.append(current)
                current = trimmed
            } else {
                // Continuation — just concatenate (CJK doesn't need spaces between chars)
                current += trimmed
            }
        }
        if !current.isEmpty { paragraphs.append(current) }

        // --- Phase 3: add indentation and finish ---
        let indent = "\u{3000}\u{3000}"
        var result = paragraphs.map { indent + $0 }.joined(separator: "\n\n")

        // Cleanup: remove BOM / zero-width chars
        result = result.replacingOccurrences(of: "\u{FEFF}", with: "")
        result = result.replacingOccurrences(of: "\u{200B}", with: "")

        // Collapse multiple spaces
        result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

        // Remove spaces between CJK characters
        let cjk = "\\u4E00-\\u9FFF\\u3400-\\u4DBF\\uF900-\\uFAFF\\u3000-\\u303F\\uFF00-\\uFFEF"
        result = result.replacingOccurrences(of: "([\(cjk)]) ([\(cjk)])", with: "$1$2", options: .regularExpression)

        // Remove control chars
        result = result.unicodeScalars.filter { c in
            c == "\n" || c == "\t" || !CharacterSet.controlCharacters.contains(c)
        }.map(String.init).joined()

        return result.precomposedStringWithCanonicalMapping
    }
}
