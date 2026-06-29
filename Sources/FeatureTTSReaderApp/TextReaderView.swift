import SwiftUI

// MARK: - Deprecated - Use ReaderView instead
@available(*, deprecated, message: "Use ReaderView instead")
struct TextReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    let chapter: BookChapter

    var body: some View {
        ReaderView(book: Book(id: UUID(), title: chapter.title, text: chapter.text, importedAt: Date()),
                   chapter: chapter, bookID: UUID(), chapterIndex: 0)
            .environmentObject(store)
    }
}

struct TextReaderView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TextReaderView(chapter: BookChapter(id: UUID(), title: "示例章节", text: String(repeating: "这是示例文本。\n\n", count: 30)))
                .environmentObject(ReaderStore())
        }
    }
}
