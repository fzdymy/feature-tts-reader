import Foundation

func parseChapters(text: String) -> [BookChapter] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    let headingPattern = "(?m)^(第[零一二三四五六七八九十百千0-9]{1,8}[章节].*)"
    guard let headingRegex = try? NSRegularExpression(pattern: headingPattern) else { return [] }

    // Precompile regex for per-line matching (avoids O(n) regex compilation per line)
    let matches = headingRegex.matches(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count))
    let headings = matches.map { m -> String in
        let r = m.range(at: 1)
        return (r.location != NSNotFound && r.location < trimmed.utf16.count) ? String(trimmed[Range(r, in: trimmed)!]) : ""
    }
    if headings.count >= 2 {
        var chapters: [BookChapter] = []
        let lines = trimmed.components(separatedBy: .newlines)
        var currentTitle: String?
        var currentText = ""
        for line in lines {
            let lineRange = NSRange(location: 0, length: line.utf16.count)
            if let m = headingRegex.firstMatch(in: line, range: lineRange),
               m.numberOfRanges > 1,
               let titleRange = Range(m.range(at: 1), in: line) {
                let firstHead = String(line[titleRange])
                if let title = currentTitle, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chapters.append(BookChapter(id: UUID(), title: title, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                currentTitle = firstHead
                currentText = ""
            } else {
                currentText.append(line + "\n")
            }
        }
        if let title = currentTitle, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chapters.append(BookChapter(id: UUID(), title: title, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return chapters
    }

    var parts = trimmed.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if parts.count < 3 {
        parts = trimmed.chunked(into: 12000)
    }
    return parts.enumerated().map { index, piece in
        BookChapter(id: UUID(), title: "章节 \(index + 1)", text: piece.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
