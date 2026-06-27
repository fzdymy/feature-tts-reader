import Foundation

func parseChapters(text: String) -> [BookChapter] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    let headingPattern = "(?m)^(第[零一二三四五六七八九十百千0-9]{1,8}[章节].*)"
    let headings = trimmed.regexGroups(pattern: headingPattern)
    if headings.count >= 2 {
        var chapters: [BookChapter] = []
        let lines = trimmed.components(separatedBy: .newlines)
        var currentTitle: String?
        var currentText = ""
        for line in lines {
            if let firstHead = line.firstMatch(regex: headingPattern)?.first {
                if let title = currentTitle, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chapters.append(BookChapter(id: UUID(), title: title, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                currentTitle = firstHead
                currentText = line + "\n"
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
