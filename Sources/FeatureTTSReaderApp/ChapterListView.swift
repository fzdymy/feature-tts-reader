import SwiftUI

struct ChapterListView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    var currentChapterID: UUID?
    var chapters: [BookChapter] = []
    var onSelect: ((BookChapter, Int) -> Void)?
    @State private var searchText = ""

    private var filteredChapters: [BookChapter] {
        guard !searchText.isEmpty else { return chapters }
        return chapters.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if chapters.isEmpty {
                Spacer()
                Text("当前还没有章节，请先导入小说并扫描章节。")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filteredChapters.enumerated()), id: \.element.id) { chapterIndex, chapter in
                            let originalIndex = chapters.firstIndex(where: { $0.id == chapter.id }) ?? chapterIndex
                            let isCurrent = chapter.id == currentChapterID
                            let bg = isCurrent ? Color.accentColor.opacity(0.15) : Color.clear
                            Button(action: {
                                onSelect?(chapter, originalIndex)
                                dismiss()
                            }) {
                                HStack {
                                    Text(chapter.title)
                                        .font(.headline)
                                        .foregroundColor(isCurrent ? .accentColor : .primary)
                                    Spacer()
                                    if isCurrent {
                                        Image(systemName: "bookmark.fill")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(bg)
                            }
                            .buttonStyle(.plain)
                            if chapterIndex < filteredChapters.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索章节")
        .navigationTitle("章节目录")
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
