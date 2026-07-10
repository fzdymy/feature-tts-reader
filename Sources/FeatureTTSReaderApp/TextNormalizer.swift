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
    ///   - Preserve each original line as a paragraph (already-indented text stays intact)
    ///   - Detect dialogue (`“`), chapter headers (`第N章`), and standalone short lines (≤6 CJK chars) as
    ///     definitive paragraph breaks from the *next* line — only merge unambiguous continuations
    ///   - Add 2 full-width space indentation (　　)
    ///   - Does NOT use 。！？ as paragraph terminators (in hard-wrapped CJK every line ends with them)
    static func reformatChineseNovel(_ raw: String) -> String {
        // --- Phase 1: basic cleanup ---
        var s = raw
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")

        var lines = s.components(separatedBy: "\n")
        // Preserve empty lines as paragraph separators
        // Strip only outer whitespace per line
        for i in lines.indices {
            lines[i] = lines[i].trimmingCharacters(in: .whitespaces)
        }

        // --- Phase 2: group into paragraphs ---
        let chapterPattern = try! NSRegularExpression(pattern: "^第[0-9一二三四五六七八九十百千]+[章节回部篇]")
        let openQuotes  = "“"

        var paragraphs: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line
            // Blank line → explicit paragraph separator
            guard !trimmed.isEmpty else {
                if !current.isEmpty { paragraphs.append(current); current = "" }
                continue
            }

            if current.isEmpty {
                // First line of a paragraph: chapter headers and short
                // standalone lines are emitted immediately as one-liners.
                let isChapterHeader = chapterPattern.firstMatch(
                    in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)
                ) != nil
                let isShort = trimmed.utf16.count <= 6
                if isChapterHeader || (isShort && !trimmed.hasPrefix("“")) {
                    paragraphs.append(trimmed)
                } else {
                    current = trimmed
                }
                continue
            }

            let firstChar = trimmed.first ?? " "
            // Heuristics for "this line starts a NEW paragraph"
            let startsWithOpenQuote = openQuotes.contains(firstChar)
            let isChapterHeader = chapterPattern.firstMatch(
                in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)
            ) != nil
            let isStandaloneShort = trimmed.utf16.count <= 6

            if startsWithOpenQuote || isChapterHeader || isStandaloneShort {
                // Flush current paragraph
                paragraphs.append(current)
                // Chapter headers and short standalone lines are one-line paragraphs
                if (isChapterHeader || isStandaloneShort) && !startsWithOpenQuote {
                    paragraphs.append(trimmed)
                    current = ""
                } else {
                    current = trimmed
                }
            } else {
                current += trimmed
            }
        }
        if !current.isEmpty { paragraphs.append(current) }

        // --- Phase 3: indentation and polish ---
        let indent = "\u{3000}\u{3000}"
        var result = paragraphs.map { indent + $0 }.joined(separator: "\n\n")

        result = result.replacingOccurrences(of: "\u{FEFF}", with: "")
        result = result.replacingOccurrences(of: "\u{200B}", with: "")

        result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

        let cjk = "\\u4E00-\\u9FFF\\u3400-\\u4DBF\\uF900-\\uFAFF\\u3000-\\u303F\\uFF00-\\uFFEF"
        result = result.replacingOccurrences(of: "([\(cjk)]) ([\(cjk)])", with: "$1$2", options: .regularExpression)

        result = result.unicodeScalars.filter { c in
            c == "\n" || c == "\t" || !CharacterSet.controlCharacters.contains(c)
        }.map(String.init).joined()

        return result.precomposedStringWithCanonicalMapping
    }
}
