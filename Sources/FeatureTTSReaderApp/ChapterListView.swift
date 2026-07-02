import SwiftUI

struct ChapterListView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    var currentChapterID: UUID?
    var onSelect: ((BookChapter, Int) -> Void)?
    var chapters: [BookChapter] = []

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
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { chapterIndex, chapter in
                            let isCurrent = chapter.id == currentChapterID
                            let bg = isCurrent ? Color.accentColor.opacity(0.15) : Color.clear
                            Button(action: {
                                onSelect?(chapter, chapterIndex)
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
                            if chapterIndex < chapters.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
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
