import SwiftUI

struct ChapterListView: View {
    @EnvironmentObject private var store: ReaderStore

    var body: some View {
        List {
            if store.chapters.isEmpty {
                Text("当前还没有章节，请先导入小说并扫描章节。")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.chapters) { chapter in
                    NavigationLink(destination: TextReaderView(chapter: chapter)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(chapter.title)
                                .font(.headline)
                            Text(chapter.preview)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("章节目录")
        .listStyle(.insetGrouped)
    }
}

struct ChapterListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ChapterListView()
                .environmentObject(ReaderStore())
        }
    }
}
