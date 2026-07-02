import SwiftUI

struct BookshelfView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var showingImporter = false
    @State private var viewMode: ViewMode = .grid
    @State private var sortOption: SortOption = .recent
    @State private var searchText = ""

    enum ViewMode: String, CaseIterable, Identifiable {
        case grid, list
        var id: String { rawValue }
        var icon: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
        var name: String { self == .grid ? "网格" : "列表" }
    }

    private var filteredBooks: [Book] {
        let books = store.books
        let filtered = searchText.isEmpty ? books : books.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
        switch sortOption {
        case .recent:
            return filtered.sorted { $0.importedAt > $1.importedAt }
        case .title:
            return filtered.sorted { $0.title < $1.title }
        case .progress:
            return filtered
        }
    }

    var body: some View {
        NavigationStack(path: $store.navigationPath) {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    searchAndSortBar
                        .padding(.horizontal)
                        .padding(.top, 8)

                    if store.books.isEmpty {
                        emptyStateView
                    } else if viewMode == .grid {
                        gridView
                    } else {
                        listView
                    }
                }
            }
            .navigationTitle("书架")
            .searchable(text: $searchText, prompt: "搜索书籍")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Picker("视图模式", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Image(systemName: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)

                    Menu {
                        Picker("排序", selection: $sortOption) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.name).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }

                    Button(action: { showingImporter = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                DocumentImporter { url in
                    showingImporter = false
                    Task { await store.importFile(at: url) }
                }
            }
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book)
                    .environmentObject(store)
            }
            .navigationDestination(for: ReaderNavigationKey.self) { key in
                let book = store.books.first { $0.id == key.bookID } ?? Book(id: key.bookID, title: "", text: "", importedAt: Date())
                let chaps = store.bookChaptersCache[key.bookID] ?? []
                let chapter = chaps.indices.contains(key.chapterIndex) ? chaps[key.chapterIndex] : BookChapter(id: key.chapterID, title: "", text: "")
                ReaderView(book: book,
                           chapter: chapter,
                           bookID: key.bookID,
                           chapterIndex: key.chapterIndex)
                    .environmentObject(store)
            }
        }
    }

    private var searchAndSortBar: some View {
        HStack {
            Picker("视图", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.name, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()

            Menu {
                Picker("排序", selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Label(option.name, systemImage: sortIcon(option)).tag(option)
                    }
                }
            } label: {
                Label(sortOption.name, systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
            }
        }
    }

    private func sortIcon(_ option: SortOption) -> String {
        switch option {
        case .recent: return "clock"
        case .title: return "textformat"
        case .progress: return "chart.bar"
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("书架为空")
                .font(.title2)
                .fontWeight(.medium)
            Text("点击右上角 + 导入 TXT 文件\n或通过分享功能将文件发送到本应用")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: { showingImporter = true }) {
                Label("导入第一本书", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .padding()
                    .frame(width: 220)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
            ], spacing: 20) {
                ForEach(filteredBooks) { book in
                    NavigationLink(value: book) {
                        BookGridCard(book: book)
                            .environmentObject(store)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { bookContextMenu(for: book) }
                }
            }
            .padding(16)
        }
    }

    private var listView: some View {
        List {
            ForEach(filteredBooks) { book in
                NavigationLink(value: book) {
                    BookListRow(book: book)
                        .environmentObject(store)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        if let index = store.books.firstIndex(where: { $0.id == book.id }) {
                            store.removeBook(at: index)
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func bookContextMenu(for book: Book) -> some View {
        Button(action: { store.navigationPath.append(book) }) {
            Label("查看详情", systemImage: "info.circle")
        }
        Button(role: .destructive) {
            if let index = store.books.firstIndex(where: { $0.id == book.id }) {
                store.removeBook(at: index)
            }
        } label: {
            Label("删除", systemImage: "trash")
        }
        Button(action: { exportBook(book) }) {
            Label("导出", systemImage: "square.and.arrow.up")
        }
    }

    private func exportBook(_ book: Book) {
        let text = store.loadBookTextFromFile(bookID: book.id) ?? book.text
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

struct BookGridCard: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book
    @State private var chapterCount = 0

    private var progress: Double {
        if chapterCount == 0 { return 0 }
        let sum = store.bookChaptersCache[book.id]?.reduce(0.0) { $0 + (store.bookProgressByChapter[$1.id] ?? 0) } ?? 0
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
            await loadChapterCount()
        }
    }

    private func loadChapterCount() async {
        if let cached = store.bookChaptersCache[book.id] {
            chapterCount = cached.count
            return
        }
        let text = store.loadBookTextFromFile(bookID: book.id) ?? book.text
        guard !text.isEmpty else { return }
        let parsed = await Task.detached(priority: .background) {
            store.extractChapters(from: text)
        }.value
        await MainActor.run {
            store.bookChaptersCache[book.id] = parsed
            chapterCount = parsed.count
        }
    }
}

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
            await loadChapterCount()
        }
    }

    private func loadChapterCount() async {
        if let cached = store.bookChaptersCache[book.id] {
            chapterCount = cached.count
            return
        }
        let text = store.loadBookTextFromFile(bookID: book.id) ?? book.text
        guard !text.isEmpty else { return }
        let parsed = await Task.detached(priority: .background) {
            store.extractChapters(from: text)
        }.value
        await MainActor.run {
            store.bookChaptersCache[book.id] = parsed
            chapterCount = parsed.count
        }
    }
}

struct BookDetailView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let book: Book

    @State private var chapterCount = 0
    @State private var isLoadingChapters = true
    @State private var loadError = false

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
                }
            }

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
    }

    private func loadChapters() async {
        if let cached = store.bookChaptersCache[book.id] {
            chapterCount = cached.count
            isLoadingChapters = false
            return
        }
        let text = store.loadBookTextFromFile(bookID: book.id) ?? book.text
        guard !text.isEmpty else {
            loadError = true
            isLoadingChapters = false
            return
        }
        let parsed = await Task.detached(priority: .userInitiated) {
            store.extractChapters(from: text)
        }.value
        await MainActor.run {
            store.bookChaptersCache[book.id] = parsed
            chapterCount = parsed.count
            isLoadingChapters = false
        }
    }

    private func openReader() {
        guard let chaps = store.bookChaptersCache[book.id], !chaps.isEmpty else { return }
        let saved = ReaderStore.loadLastChapterIndex(for: book.id)
        let safeIndex = min(saved, chaps.count - 1)
        store.navigationPath.append(ReaderNavigationKey(
            bookID: book.id,
            chapterID: chaps[safeIndex].id,
            chapterIndex: safeIndex
        ))
    }
}

struct ReaderNavigationKey: Hashable {
    let bookID: UUID
    let chapterID: UUID
    let chapterIndex: Int

    static func == (lhs: ReaderNavigationKey, rhs: ReaderNavigationKey) -> Bool {
        lhs.bookID == rhs.bookID && lhs.chapterID == rhs.chapterID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bookID)
        hasher.combine(chapterID)
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

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = Locale(identifier: "zh_CN")
    return formatter.string(from: date)
}

struct BookshelfView_Previews: PreviewProvider {
    static var previews: some View {
        BookshelfView().environmentObject(ReaderStore())
    }
}