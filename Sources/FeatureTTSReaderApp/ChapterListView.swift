import SwiftUI

struct ChapterListView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    var currentChapterID: UUID?
    var onSelect: ((BookChapter, Int) -> Void)?

    private var currentBook: Book? {
        if let id = UUID(uuidString: store.currentBookID),
           let found = store.books.first(where: { $0.id == id }) {
            return found
        }
        return store.books.first
    }

    var body: some View {
        List {
            if store.chapters.isEmpty {
                Text("当前还没有章节，请先导入小说并扫描章节。")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.chapters) { chapter in
                    let chapterIndex = store.chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
                    let isCurrent = chapter.id == currentChapterID
                    if let onSelect {
                        Button(action: {
                            onSelect(chapter, chapterIndex)
                            dismiss()
                        }) {
                            HStack {
                                Text(chapter.title)
                                    .font(.headline)
                                    .foregroundColor(isCurrent ? .accentColor : .primary)
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear)
                    } else if let book = currentBook {
                        NavigationLink(destination: ReaderView(book: book, chapter: chapter, bookID: book.id, chapterIndex: chapterIndex).environmentObject(store)) {
                            HStack {
                                Text(chapter.title)
                                    .font(.headline)
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear)
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
