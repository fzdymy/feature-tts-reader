import Foundation

struct TextNormalizer {

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
            lines[i] = lines[i].replacingOccurrences(of: " +$", with: "", options: .regularExpression)
        }
        s = lines.joined(separator: "\n")

        // 4. Collapse single newlines within paragraphs (hard line wraps) into spaces
        s = s.replacingOccurrences(of: "(?<!\n)\n(?!\n)", with: " ", options: .regularExpression)

        // 5. Collapse excessive blank lines (≥3 consecutive → 2)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        // 6. Collapse multiple horizontal spaces (2+ → 1)
        s = s.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

        // 7. Remove stray control characters except \n, \t
        s = s.unicodeScalars.filter { c in
            c == "\n" || c == "\t" || !CharacterSet.controlCharacters.contains(c)
        }.map(String.init).joined()

        // 8. NFC normalization (composed form) — preferred for Han text
        s = s.precomposedStringWithCanonicalMapping

        return s
    }
}
