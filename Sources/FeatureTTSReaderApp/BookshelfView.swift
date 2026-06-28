import SwiftUI

struct BookshelfView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var showingImporter = false
    @State private var viewMode: ViewMode = .grid
    @State private var sortOption: SortOption = .recent
    @State private var searchText = ""
    @State private var selectedBook: Book?
    @State private var showBookDetail = false

    enum ViewMode: String, CaseIterable, Identifiable {
        case grid = "grid"
        case list = "list"
        var id: String { rawValue }
        var icon: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
        var name: String { self == .grid ? "网格" : "列表" }
    }
        }
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
            return filtered.sorted { (b1: Book, b2: Book) in
                let p1 = store.currentBookID == b1.id.uuidString ? store.currentBookProgress : 0
                let p2 = store.currentBookID == b2.id.uuidString ? store.currentBookProgress : 0
                return p1 > p2
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search & Sort Bar
                    searchAndSortBar
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Books Content
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
                    // View Mode Toggle
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
            .sheet(item: $selectedBook) { book in
                BookDetailView(book: book)
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
                    BookGridCard(book: book)
                        .environmentObject(store)
                        .onTapGesture {
                            selectedBook = book
                        }
                        .contextMenu {
                            bookContextMenu(for: book)
                        }
                }
            }
            .padding(16)
        }
    }

    private var listView: some View {
        List {
            ForEach(filteredBooks) { book in
                BookListRow(book: book)
                    .environmentObject(store)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let index = store.books.firstIndex(where: { $0.id == book.id }) {
                                store.books.remove(at: index)
                                store.saveState()
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            selectedBook = book
                        } label: {
                            Label("详情", systemImage: "info.circle")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            if let index = store.books.firstIndex(where: { $0.id == book.id }) {
                                let chapters = parseChapters(text: book.text)
                                let progress = chapters.first.flatMap { store.bookProgressByChapter[$0.id] } ?? 0
                                if let chapterID = chapters.first?.id {
                                    store.setChapterProgress(chapterID, percent: min(max(progress + 0.1, 0), 1))
                                }
                            }
                        } label: {
                            Label("进度+10%", systemImage: "forward")
                        }
                        .tint(.green)
                    }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func bookContextMenu(for book: Book) -> some View {
        Button(action: { selectedBook = book }) {
            Label("查看详情", systemImage: "info.circle")
        }
        Button(action: {
            if let index = store.books.firstIndex(where: { $0.id == book.id }) {
                store.books.remove(at: index)
                store.saveState()
            }
        }) {
            Label("删除", systemImage: "trash")
        }
        .tint(.red)
        Button(action: {
            // Export book
            exportBook(book)
        }) {
            Label("导出", systemImage: "square.and.arrow.up")
        }
    }

    private func exportBook(_ book: Book) {
        let activityVC = UIActivityViewController(activityItems: [book.text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

struct BookGridCard: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book

    private var progress: Double {
        let chapters = parseChapters(text: book.text)
        if let chapterID = chapters.first?.id {
            return store.bookProgressByChapter[chapterID] ?? 0
        }
        return 0
    }

    private var chapterCount: Int {
        parseChapters(text: book.text).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Cover
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

                // Progress overlay
                if progress > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Text("\(Int(progress * 100))%")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(6)
                            }
                            .padding(8)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Book info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(chapterCount) 章 · \(formatDate(book.importedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Progress bar
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
    }
}

struct SpacerStack: View {
    var body: some View { Spacer() }
}

struct BookListRow: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book

    private var progress: Double {
        let chapters = parseChapters(text: book.text)
        if let chapterID = chapters.first?.id {
            return store.bookProgressByChapter[chapterID] ?? 0
        }
        return 0
    }

    private var chapterCount: Int {
        parseChapters(text: book.text).count
    }

    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
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

                if progress > 0 {
                    HStack {
                        ProgressView(value: progress)
                            .frame(width: 120)
                        Text("\(Int(progress * 100))%")
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
    }
}

struct BookDetailView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let book: Book
    @State private var chapters: [BookChapter] = []
    @State private var showDeleteAlert = false

    private var totalProgress: Double {
        guard !chapters.isEmpty else { return 0 }
        let sum = chapters.reduce(0.0) { $0 + (store.bookProgressByChapter[$1.id] ?? 0) }
        return sum / Double(chapters.count)
    }

    private var readChapters: Int {
        chapters.filter { store.bookProgressByChapter[$0.id] ?? 0 > 0.95 }.count
    }

    private var totalReadingTime: String {
        let totalChars = chapters.reduce(0) { $0 + $1.text.count }
        let minutes = totalChars / 400 // ~400 chars/min
        return "\(minutes) 分钟"
    }

    var body: some View {
        NavigationStack {
            List {
                // Header Section
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 16) {
                            // Cover
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 140)
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.blue.opacity(0.6))
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(book.title)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .lineLimit(3)

                                Text("作者：未知")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Text("导入时间：\(formatDate(book.importedAt))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Stats
                        HStack(spacing: 24) {
                            StatView(value: "\(chapters.count)", label: "章节")
                            StatView(value: "\(readChapters)", label: "已读")
                            StatView(value: "\(Int(totalProgress * 100))%", label: "进度")
                            StatView(value: totalReadingTime, label: "预计")
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // Actions
                Section {
                    Button(action: {
                        if let chapter = chapters.first,
                           let index = chapters.firstIndex(where: { $0.id == chapter.id }) {
                            store.selectedChapterID = chapter.id
                            store.currentBookID = book.id.uuidString
                            store.currentBookTitle = book.title
                            store.bookText = book.text
                            dismiss()
                        }
                    }) {
                        HStack {
                            Image(systemName: readChapters > 0 ? "bookmark.fill" : "book.fill")
                            Text(readChapters > 0 ? "继续阅读" : "开始阅读")
                            Spacer()
                            if readChapters > 0 {
                                Text("第 \(readChapters + 1) 章")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .foregroundColor(.blue)

                    NavigationLink(destination: ChapterListView()
                        .environmentObject(store)
                    ) {
                        Label("章节目录", systemImage: "list.bullet")
                    }

                    NavigationLink(destination: ReaderSettingsView()
                        .environmentObject(store)
                    ) {
                        Label("阅读设置", systemImage: "textformat")
                    }
                }

                // Chapters
                Section(header: Text("章节目录 (\(chapters.count))")) {
                    if chapters.isEmpty {
                        Text("正在解析章节...")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(chapters) { chapter in
                            let chapterIndex = chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
                            let progress = store.bookProgressByChapter[chapter.id] ?? 0
                            let isCurrent = store.selectedChapterID == chapter.id

                            NavigationLink(destination: ReaderView(
                                book: book,
                                chapter: chapter,
                                bookID: book.id,
                                chapterIndex: chapterIndex
                            ).environmentObject(store)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(chapter.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        if isCurrent {
                                            Image(systemName: "bookmark.fill")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    Text(chapter.preview)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)

                                    if progress > 0 {
                                        HStack {
                                            ProgressView(value: progress)
                                            Text("\(Int(progress * 100))%")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                // Info
                Section(header: Text("信息")) {
                    InfoRow(label: "标题", value: book.title)
                    InfoRow(label: "章节数", value: "\(chapters.count)")
                    InfoRow(label: "字数", value: "\(book.text.count)")
                    InfoRow(label: "导入时间", value: formatDate(book.importedAt))
                    InfoRow(label: "整体进度", value: "\(Int(totalProgress * 100))%")
                }

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("删除本书", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("书籍详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("删除本书", isPresented: $showDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let index = store.books.firstIndex(where: { $0.id == book.id }) {
                        store.books.remove(at: index)
                        store.saveState()
                    }
                    dismiss()
                }
            } message: {
                Text("确定要删除《\(book.title)》吗？此操作不可撤销。")
            }
            .onAppear {
                Task {
                    let parsed = await Task.detached { parseChapters(text: book.text) }.value
                    chapters = parsed
                }
            }
        }
    }

    struct StatView: View {
        let value: String
        let label: String

        var body: some View {
            VStack(spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    struct InfoRow: View {
        let label: String
        let value: String

        var body: some View {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .foregroundColor(.primary)
            }
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