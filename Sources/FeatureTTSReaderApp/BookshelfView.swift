import SwiftUI

struct BookshelfView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var showingImporter = false
    @State private var viewMode: ViewMode = .grid
    @State private var sortOption: SortOption = .recent
    @State private var searchText = ""
    @State private var showStatus = false

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
            Group {
                if !store.isStateLoaded {
                    ProgressView("载入中...")
                        .scaleEffect(1.5)
                } else {
                    ZStack {
                        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                        VStack(spacing: 0) {
                            searchAndSortBar
                                .padding(.horizontal)
                                .padding(.top, 8)

                            if showStatus && !store.statusMessage.isEmpty {
                                Text(store.statusMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor)
                                    .cornerRadius(6)
                                    .padding(.horizontal)
                                    .padding(.top, 4)
                                    .transition(.opacity)
                            }

                            if store.books.isEmpty {
                                emptyStateView
                            } else if viewMode == .grid {
                                gridView
                            } else {
                                listView
                            }
                        }
                        .onChange(of: store.statusMessage) { _, newValue in
                            guard !newValue.isEmpty else { return }
                            showStatus = true
                            Task {
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                withAnimation { showStatus = false }
                            }
                        }
                    }
                }
            }
            .navigationTitle("书架")
            .searchable(text: $searchText, prompt: "搜索书籍")
            .onAppear { store.loadState() }
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
        Button {
            store.reformatBookText(bookID: book.id)
        } label: {
            Label("重新格式化", systemImage: "doc.text.magnifyingglass")
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

func loadChapterCount(for book: Book, store: ReaderStore, chapterCount: Binding<Int>) async {
    await MainActor.run {
        if let cached = store.chaptersForBookCached(book.id) {
            chapterCount.wrappedValue = cached.count
            return
        }
        // For async extraction, we'll use a detached task
    }
    // If no cache, extract chapters in background
    var textToParse = ""
    await MainActor.run {
        if !book.text.isEmpty {
            textToParse = book.text
        } else if store.currentBookID == book.id.uuidString && !store.bookText.isEmpty {
            textToParse = store.bookText
        } else {
            textToParse = store.loadBookTextFromFile(bookID: book.id) ?? ""
        }
    }
    guard !textToParse.isEmpty else { return }
    let parsed = await Task.detached(priority: .background) { [textToParse] in
        ReaderStore.extractChapters(from: textToParse)
    }.value
    await MainActor.run {
        store.setCachedChapters(parsed, for: book.id, text: textToParse)
        chapterCount.wrappedValue = parsed.count
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