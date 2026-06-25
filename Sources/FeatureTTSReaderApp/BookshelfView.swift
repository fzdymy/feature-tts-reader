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
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(book.title).font(.title2).bold()
            Text("导入时间：\(book.importedAt.formatted())").font(.caption).foregroundColor(.secondary)
            Divider()
            ScrollView { Text(book.text).padding() }
        }
        .padding()
        .navigationTitle(book.title)
    }
}

struct BookshelfView_Previews: PreviewProvider {
    static var previews: some View {
        BookshelfView().environmentObject(ReaderStore())
    }
}
