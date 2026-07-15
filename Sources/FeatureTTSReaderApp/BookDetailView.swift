import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let book: Book

    @State private var chapterCount = 0
    @State private var isLoadingChapters = true
    @State private var loadError = false
    @State private var readerCover: ReaderCoverKey?
    @State private var resolvedTextLength = 0
    @State private var isDeleting = false

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
                    let wan = Double(resolvedTextLength) / 10000
                    InfoRow(label: "字数", value: "\(String(format: "%.1f", wan)) 万字")
                }
            }

            CharacterAssignmentPanel(book: book)
                .environmentObject(store)

            Section {
                VStack(spacing: 8) {
                    Button(action: {
                        Task { await loadChapters() }
                    }) {
                        Label("重试加载章节", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoadingChapters)

                    Button(role: .destructive) {
                        isDeleting = true
                        let targetID = book.id
                        store.books.removeAll { $0.id == targetID }
                        store.clearCachedChapters(for: targetID)
                        store.saveState()
                        dismiss()
                    } label: {
                        Label("删除本书", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .navigationTitle("书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: book.id) {
            await loadChapters()
        }
        .onAppear {
            refreshChapterCount()
        }
        .onReceive(store.objectWillChange) { _ in
            refreshChapterCount()
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
        refreshChapterCount()
        if let cached = store.chaptersForBookCached(book.id), !cached.isEmpty {
            chapterCount = cached.count
            isLoadingChapters = false
            loadError = false
            return
        }

        isLoadingChapters = true
        loadError = false
        let text = await loadBookText()
        guard !Task.isCancelled else { return }
        guard let text, !text.isEmpty else {
            await MainActor.run {
                loadError = true
                isLoadingChapters = false
            }
            return
        }

        let parsed = await Task(priority: .userInitiated) { ReaderStore.extractChapters(from: text) }.value
        guard !Task.isCancelled else { return }
        await MainActor.run {
            store.setCachedChapters(parsed, for: book.id, text: text)
            chapterCount = parsed.count
            isLoadingChapters = false
            loadError = parsed.isEmpty
            resolvedTextLength = text.count
        }
    }

    private func loadBookText() async -> String? {
        if !book.text.isEmpty { return book.text }
        if store.currentBookID == book.id.uuidString && !store.bookText.isEmpty { return store.bookText }
        if let fileText = store.loadBookTextFromFile(bookID: book.id) { return fileText }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = docs.appendingPathComponent("book_texts/\(book.id.uuidString).txt")
        return await Task(priority: .userInitiated) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
    }

    private func refreshChapterCount() {
        chapterCount = store.chaptersForBookCached(book.id)?.count ?? 0
        let fallbackText: String
        if !book.text.isEmpty {
            fallbackText = book.text
        } else if store.currentBookID == book.id.uuidString {
            fallbackText = store.bookText
        } else {
            fallbackText = store.loadBookTextFromFile(bookID: book.id) ?? ""
        }
        resolvedTextLength = fallbackText.count
        if chapterCount > 0 {
            isLoadingChapters = false
            loadError = false
        }
    }

    private func openReader() {
        let fallbackText = book.text.isEmpty ? (store.currentBookID == book.id.uuidString ? store.bookText : store.loadBookTextFromFile(bookID: book.id) ?? "") : book.text
        let chaps = store.chaptersForBookCached(book.id) ?? (fallbackText.isEmpty ? nil : store.chaptersForBook(book.id, text: fallbackText))
        guard let chapters = chaps, !chapters.isEmpty else {
            ReaderStore.debugLog("[OPEN-READER-FAIL] no cache for \(book.id.uuidString)")
            loadError = true
            return
        }
        let saved = ReaderStore.loadLastChapterIndex(for: book.id)
        let safeIndex = max(0, min(saved, chapters.count - 1))
        store.currentBookID = book.id.uuidString
        ReaderStore.debugLog("[OPEN-READER] saved=\(saved) safe=\(safeIndex) total=\(chapters.count)")
        readerCover = ReaderCoverKey(
            id: chapters[safeIndex].id,
            chapter: chapters[safeIndex],
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

#Preview {
    NavigationStack {
        BookDetailView(book: Book(id: UUID(), title: "示例书籍", text: "这是一个样本文本，用于预览书籍详情。", importedAt: Date()))
            .environmentObject(ReaderStore())
    }
}
