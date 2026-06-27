import SwiftUI

struct ChapterListView: View {
    @EnvironmentObject private var store: ReaderStore

    private var currentBook: Book {
        Book(id: UUID(uuidString: store.currentBookID) ?? UUID(), title: store.currentBookTitle.isEmpty ? "当前书籍" : store.currentBookTitle, text: store.bookText, importedAt: Date())
    }

    var body: some View {
        List {
            if store.chapters.isEmpty {
                Text("当前还没有章节，请先导入小说并扫描章节。")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.chapters) { chapter in
                    let chapterIndex = store.chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
                    NavigationLink(destination: ReaderDetailView(book: currentBook, chapter: chapter, bookID: currentBook.id, chapterIndex: chapterIndex).environmentObject(store)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(chapter.title)
                                .font(.headline)
                            Text(chapter.preview)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("章节目录")
        .listStyle(.insetGrouped)
    }
}

struct ChapterListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ChapterListView()
                .environmentObject(ReaderStore())
        }
    }
}
