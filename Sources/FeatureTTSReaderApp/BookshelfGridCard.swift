import SwiftUI

struct BookGridCard: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book
    @State private var chapterCount = 0

    private var progress: Double {
        if chapterCount == 0 { return 0 }
        let cached = store.cachedChapters(for: book.id)
        let sum = cached?.reduce(0.0) { $0 + (store.bookProgressByChapter[$1.id] ?? 0) } ?? 0
        return chapterCount > 0 ? sum / Double(chapterCount) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue.opacity(0.6))
                    )

                if progress > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(6)
                                .padding(8)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(chapterCount) 章 · \(formatDate(book.importedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if progress > 0 {
                    ProgressView(value: progress)
                        .tint(.blue)
                        .scaleEffect(y: 0.5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .task {
            await loadChapterCount(for: book, store: store, chapterCount: $chapterCount)
        }
    }
}
