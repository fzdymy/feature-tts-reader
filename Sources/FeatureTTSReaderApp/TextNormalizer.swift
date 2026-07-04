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

        // 3. Strip trailing whitespace per line
        var lines = s.components(separatedBy: "\n")
        for i in lines.indices {
            lines[i] = lines[i].trimmingCharacters(in: .whitespaces)
        }
        s = lines.joined(separator: "\n")

        // 4. Collapse excessive blank lines (≥3 consecutive → 2)
        s = s.replacingOccurrences(of: "\n{4,}", with: "\n\n\n", options: .regularExpression)

        // 5. Collapse multiple horizontal spaces (but not newlines)
        s = s.replacingOccurrences(of: " {3,}", with: "  ", options: .regularExpression)

        // 6. Remove stray control characters except \n, \t
        s = s.unicodeScalars.filter { c in
            c == "\n" || c == "\t" || !c.properties.isControl
        }.map(String.init).joined()

        // 7. NFC normalization (composed form) — preferred for Han text
        s = s.precomposedStringWithCanonicalMapping

        return s
    }
}
