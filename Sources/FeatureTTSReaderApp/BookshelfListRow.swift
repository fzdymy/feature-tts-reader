import SwiftUI

struct BookListRow: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book
    @State private var chapterCount = 0

    private var progressValue: Double {
        if chapterCount == 0 { return 0 }
        let sum = store.bookChaptersCache[book.id]?.reduce(0.0) { $0 + (store.bookProgressByChapter[$1.id] ?? 0) } ?? 0
        return chapterCount > 0 ? sum / Double(chapterCount) : 0
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 50, height: 70)
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(chapterCount) 章 · \(formatDate(book.importedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if progressValue > 0 {
                    HStack {
                        ProgressView(value: progressValue)
                            .frame(width: 120)
                        Text("\(Int(progressValue * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .task {
            await loadChapterCount(for: book, store: store, chapterCount: $chapterCount)
        }
    }
}
