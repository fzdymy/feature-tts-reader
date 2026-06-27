import SwiftUI

struct BookshelfView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var showingImporter = false

    private func readerDestination(for book: Book) -> some View {
        AnyView(BookDetailView(book: book).environmentObject(store))
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

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("书架")) {
                    if store.books.isEmpty {
                        Text("书架为空，点击导入本地 TXT 或分享文件到本应用。")
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                                ForEach(store.books) { book in
                                    NavigationLink(destination: readerDestination(for: book)) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(Color.blue.opacity(0.15))
                                                    .frame(height: 120)
                                                Image(systemName: "book.fill")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 50, height: 50)
                                                    .foregroundColor(.blue)
                                            }
                                            Text(book.title)
                                                .font(.headline)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text(book.preview)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(3)
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 18).fill(Color(UIColor.secondarySystemBackground)))
                                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.2)))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }
                Section(header: Text("操作")) {
                    Button(action: { showingImporter = true }) {
                        Label("导入 TXT 文件", systemImage: "square.and.arrow.down")
                    }
                    Button(action: { store.clearLibrary() }) {
                        Label("清空书架", systemImage: "trash")
                    }
                    NavigationLink(destination: SettingsView().environmentObject(store)) {
                        Label("全局设置", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("书架")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView().environmentObject(store)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                DocumentImporter { url in
                    showingImporter = false
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

    private var resumeIndex: Int? {
        let index = store.lastReadChapterIndex(for: book.id)
        guard let index = index, index >= 0, index < chapters.count else { return nil }
        return index
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(book.title).font(.title2).bold()
            Text("导入时间：\(book.importedAt.formatted())").font(.caption).foregroundColor(.secondary)
            Text("共 \(chapters.count) 章").font(.caption).foregroundColor(.secondary)
            Divider()
            
            if let resumeIndex = resumeIndex {
                Section {
                    NavigationLink(destination: ReaderDetailView(book: book, chapter: chapters[resumeIndex], bookID: book.id, chapterIndex: resumeIndex).environmentObject(store)) {
                        HStack {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("继续阅读")
                                    .font(.headline)
                                Text("从第 \(resumeIndex + 1) 章继续")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            if chapters.isEmpty {
                Text("未发现章节，显示全文")
                    .foregroundColor(.secondary)
                    .padding()
                NavigationLink(destination: ReaderDetailView(book: book, chapter: BookChapter(id: UUID(), title: "全文", text: book.text), bookID: book.id, chapterIndex: 0).environmentObject(store)) {
                    Label("开始阅读全文", systemImage: "book")
                        .padding(.vertical, 8)
                }
                ScrollView {
                    Text(book.text).padding()
                }
            } else {
                List {
                    ForEach(chapters.indices, id: \.self) { index in
                        let chapter = chapters[index]
                        NavigationLink(destination: ReaderDetailView(book: book, chapter: chapter, bookID: book.id, chapterIndex: index).environmentObject(store)) {
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
            Task {
                let parsed = await Task.detached { parseChapters(text: book.text) }.value
                chapters = parsed
            }
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
    let bookID: UUID
    let chapterIndex: Int
    @State private var showControls: Bool = true
    @State private var isReading: Bool = false

    private var textColor: Color {
        store.readerTheme == .dark ? .white : .primary
    }

    @ViewBuilder
    private var chapterTextView: some View {
        Text(chapter.text)
            .font(.system(size: store.readerFontSize))
            .foregroundColor(textColor)
            .lineSpacing(store.readerLineSpacing)
            .padding()
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        chapterTextView
                        Spacer().frame(height: 100)
                    }
                    .id("content")
                }
            }
            .background(store.readerTheme == .dark ? Color.black : Color.white)
            .onTapGesture { withAnimation { showControls.toggle() } }
            
            if showControls {
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 12) {
                        Button(action: {
                            store.readerTheme = store.readerTheme == .dark ? .light : .dark
                            store.saveState()
                        }) {
                            Image(systemName: store.readerTheme == .dark ? "sun.max" : "moon.fill")
                        }
                        Button(action: {
                            store.readerFontSize = max(14, store.readerFontSize - 2)
                            store.saveState()
                        }) {
                            Image(systemName: "textformat.size.smaller")
                        }
                        Text("\(Int(store.readerFontSize))")
                            .font(.subheadline)
                            .frame(minWidth: 32)
                        Button(action: {
                            store.readerFontSize = min(32, store.readerFontSize + 2)
                            store.saveState()
                        }) {
                            Image(systemName: "textformat.size.larger")
                        }
                        Button(action: {
                            if store.selectedChapterID != chapter.id {
                                store.selectedChapterID = chapter.id
                            }
                            store.addBookmark(note: "")
                        }) {
                            Image(systemName: "bookmark")
                        }
                        Button(action: {
                            if isReading {
                                store.stopPlayback()
                                isReading = false
                            } else {
                                isReading = true
                                Task {
                                    await store.playChapterWithTTS(chapter: chapter)
                                    await MainActor.run { isReading = false }
                                }
                            }
                        }) {
                            Image(systemName: isReading ? "pause.fill" : "play.fill")
                        }
                    }
                    .padding()
                    .background(VisualEffectView(style: .systemThinMaterial))
                }
            }
            
            Text("\(Int(store.getChapterProgress(chapter.id) * 100))%")
                .font(.caption2)
                .padding(8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(6)
                .padding()
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.selectedChapterID = chapter.id
            store.rememberLastReadChapter(bookID: bookID, chapterIndex: chapterIndex)
            store.saveState()
        }
        .onDisappear {
            store.saveState()
        }
    }
}

struct BookshelfView_Previews: PreviewProvider {
    static var previews: some View {
        BookshelfView().environmentObject(ReaderStore())
    }
}
