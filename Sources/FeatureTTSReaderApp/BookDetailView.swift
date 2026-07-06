import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let book: Book

    @State private var chapterCount = 0
    @State private var isLoadingChapters = true
    @State private var loadError = false
    @State private var readerCover: ReaderCoverKey?

    struct ReaderCoverKey: Identifiable {
        let id: UUID
        let chapter: BookChapter
        let chapterIndex: Int
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 100, height: 140)
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue.opacity(0.6))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title)
                                .font(.title2).fontWeight(.bold).lineLimit(3)
                            Text("导入时间：\(formatDate(book.importedAt))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Button(action: openReader) {
                    HStack {
                        Image(systemName: "book.fill")
                        if isLoadingChapters {
                            ProgressView().scaleEffect(0.8)
                            Text("加载章节中...")
                        } else if loadError {
                            Text("无法加载")
                                .foregroundColor(.red)
                        } else {
                            Text("开始阅读")
                        }
                        Spacer()
                    }
                }
                .disabled(isLoadingChapters || loadError || chapterCount == 0)
                .foregroundColor(.blue)
            }

            Section(header: Text("信息")) {
                VStack(spacing: 8) {
                    InfoRow(label: "标题", value: book.title)
                    if isLoadingChapters {
                        HStack { Text("章节数").foregroundColor(.secondary); Spacer(); ProgressView().scaleEffect(0.7) }
                    } else {
                        InfoRow(label: "章节数", value: "\(chapterCount)")
                    }
                    let wan = Double(book.text.count) / 10000
                    InfoRow(label: "字数", value: "\(String(format: "%.1f", wan)) 万字")
                }
            }

            CharacterAssignmentPanel(book: book)
                .environmentObject(store)

            Section {
                Button(role: .destructive) {
                    if let index = store.books.firstIndex(where: { $0.id == book.id }) {
                        store.books.remove(at: index)
                        store.saveState()
                    }
                    dismiss()
                } label: {
                    Label("删除本书", systemImage: "trash")
                }
            }
        }
        .navigationTitle("书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadChapters()
        }
        .fullScreenCover(item: $readerCover) { cover in
            ReaderView(book: book,
                       chapter: cover.chapter,
                       bookID: book.id,
                       chapterIndex: cover.chapterIndex)
                .environmentObject(store)
        }
    }

    private func loadChapters() async {
        if let cached = store.bookChaptersCache[book.id] {
            chapterCount = cached.count
            isLoadingChapters = false
            return
        }
        let text = await loadBookText()
        guard let text, !text.isEmpty else {
            loadError = true
            isLoadingChapters = false
            return
        }
        let parsed = await Task.detached(priority: .userInitiated) { [text] in
            ReaderStore.extractChapters(from: text)
        }.value
        await MainActor.run {
            store.bookChaptersCache[book.id] = parsed
            chapterCount = parsed.count
            isLoadingChapters = false
        }
    }

    private func loadBookText() async -> String? {
        if !book.text.isEmpty { return book.text }
        if store.currentBookID == book.id.uuidString && !store.bookText.isEmpty { return store.bookText }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = docs.appendingPathComponent("book_texts/\(book.id.uuidString).txt")
        return await Task.detached(priority: .userInitiated) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
    }

    private func openReader() {
        guard let chaps = store.bookChaptersCache[book.id], !chaps.isEmpty else {
            ReaderStore.debugLog("[OPEN-READER-FAIL] no cache for \(book.id.uuidString)")
            return
        }
        let saved = ReaderStore.loadLastChapterIndex(for: book.id)
        let safeIndex = min(saved, chaps.count - 1)
        ReaderStore.debugLog("[OPEN-READER] saved=\(saved) safe=\(safeIndex) total=\(chaps.count)")
        readerCover = ReaderCoverKey(
            id: chaps[safeIndex].id,
            chapter: chaps[safeIndex],
            chapterIndex: safeIndex
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).foregroundColor(.primary)
        }
    }
}
