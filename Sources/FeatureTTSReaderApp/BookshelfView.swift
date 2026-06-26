import SwiftUI

struct BookshelfView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("书架")) {
                    if store.books.isEmpty {
                        Text("书架为空，点击导入本地 TXT 或分享文件到本应用。")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(store.books) { book in
                            NavigationLink(destination: BookDetailView(book: book)) {
                                VStack(alignment: .leading) {
                                    Text(book.title).font(.headline)
                                    Text(book.preview).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                Section(header: Text("操作")) {
                    Button(action: { showingImporter = true }) {
                        Label("导入 TXT 文件", systemImage: "square.and.arrow.down")
                    }
                    Button(action: { store.clearLibrary() }) {
                        Label("清空书架", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("书架")
            .sheet(isPresented: $showingImporter) {
                DocumentImporter { url in
                    Task { await store.importFile(at: url) }
                }
            }
        }
    }
}

struct BookDetailView: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book
    @State private var chapters: [BookChapter] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(book.title).font(.title2).bold()
            Text("导入时间：\(book.importedAt.formatted())").font(.caption).foregroundColor(.secondary)
            Text("共 \(chapters.count) 章").font(.caption).foregroundColor(.secondary)
            Divider()
            
            if chapters.isEmpty {
                Text("未发现章节，显示全文")
                    .foregroundColor(.secondary)
                    .padding()
                ScrollView {
                    Text(book.text).padding()
                }
            } else {
                List {
                    ForEach(chapters) { chapter in
                        NavigationLink(destination: ReaderDetailView(book: book, chapter: chapter)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title).font(.headline)
                                Text(chapter.preview).font(.caption).foregroundColor(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(book.title)
        .onAppear {
            chapters = extractChapters(from: book.text)
        }
    }
    
    private func extractChapters(from text: String) -> [BookChapter] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        let headingPattern = "(?m)^(第[零一二三四五六七八九十百千0-9]{1,8}[章节].*)"
        let headings = trimmed.regexGroups(pattern: headingPattern)
        if headings.count >= 2 {
            var chapters: [BookChapter] = []
            let lines = trimmed.components(separatedBy: .newlines)
            var currentTitle: String?
            var currentText = ""
            for line in lines {
                if let firstHead = line.firstMatch(regex: headingPattern)?.first {
                    if let title = currentTitle, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        chapters.append(BookChapter(id: UUID(), title: title, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                    currentTitle = firstHead
                    currentText = line + "\n"
                } else {
                    currentText.append(line + "\n")
                }
            }
            if let title = currentTitle, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chapters.append(BookChapter(id: UUID(), title: title, text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            return chapters
        }
        
        var parts = trimmed.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if parts.count < 3 {
            parts = trimmed.chunked(into: 12000)
        }
        return parts.enumerated().map { index, piece in
            BookChapter(id: UUID(), title: "章节 \(index + 1)", text: piece.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

struct ReaderDetailView: View {
    @EnvironmentObject private var store: ReaderStore
    let book: Book
    let chapter: BookChapter
    @State private var showControls: Bool = true
    @State private var scrollPosition: CGFloat = 0
    @State private var fontSize: Double = 18
    @State private var lineSpacing: Double = 8
    @State private var theme: ReaderTheme = .light
    @State private var isReading: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(chapter.text)
                            .font(.system(size: fontSize))
                            .foregroundColor(theme == .dark ? .white : .primary)
                            .lineSpacing(lineSpacing)
                            .padding()
                        Spacer().frame(height: 100)
                    }
                    .id("content")
                }
            }
            .background(theme == .dark ? Color.black : Color.white)
            .onTapGesture { withAnimation { showControls.toggle() } }
            
            if showControls {
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 12) {
                        Button(action: { theme = theme == .dark ? .light : .dark }) {
                            Image(systemName: theme == .dark ? "sun.max" : "moon.fill")
                        }
                        Slider(value: $fontSize, in: 14...32).frame(maxWidth: 150)
                        Button(action: { 
                            store.bookmarks.append(BookBookmark(id: UUID(), chapterID: chapter.id, chapterTitle: chapter.title, percent: 0, note: "", createdAt: Date()))
                        }) {
                            Image(systemName: "bookmark")
                        }
                        Button(action: { isReading.toggle() }) {
                            Image(systemName: isReading ? "pause.fill" : "play.fill")
                        }
                    }
                    .padding()
                    .background(VisualEffectView(material: .systemThinMaterial))
                }
            }
            
            Text("\(Int(scrollPosition))%")
                .font(.caption2)
                .padding(8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(6)
                .padding()
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BookshelfView_Previews: PreviewProvider {
    static var previews: some View {
        BookshelfView().environmentObject(ReaderStore())
    }
}
