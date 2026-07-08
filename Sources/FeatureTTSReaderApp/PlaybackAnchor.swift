import Foundation

struct PlaybackAnchor: Equatable, Hashable, Codable {
    let bookID: String
    let chapterIndex: Int
    let paragraphIndex: Int
    let sentenceIndex: Int
    let speakerID: UUID?
    let charRange: Range<Int>?

    init(
        bookID: String,
        chapterIndex: Int,
        paragraphIndex: Int,
        sentenceIndex: Int,
        speakerID: UUID? = nil,
        charRange: Range<Int>? = nil
    ) {
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.sentenceIndex = sentenceIndex
        self.speakerID = speakerID
        self.charRange = charRange
    }

    var uiIdentifier: String {
        "anchor_\(bookID)_\(chapterIndex)_\(paragraphIndex)_\(sentenceIndex)"
    }
}