import SwiftUI

struct TextReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    let chapter: BookChapter
    @State private var showControls: Bool = true
    @State private var isSpeaking: Bool = false
    @State private var speakingIndex: Int = 0
    @State private var showBookmarks: Bool = false

    private var fontSizeBinding: Binding<Double> { $store.readerFontSize }
    private var lineSpacingBinding: Binding<Double> { $store.readerLineSpacing }
    private var chapterBookmarks: [BookBookmark] {
        store.bookmarks.filter { $0.chapterID == chapter.id }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(chapter.text)
                                .font(.system(size: store.readerFontSize))
                                .foregroundColor(store.readerTheme == .dark ? .white : .primary)
                                .lineSpacing(store.readerLineSpacing)
                                .padding()
                                .id("content")
                            Spacer().frame(height: 100)
                        }
                    }
                    .onTapGesture { withAnimation { showControls.toggle() } }
                }
                .background(store.readerTheme == .dark ? Color.black : Color.white)
            }
            
            if showControls {
                VStack(spacing: 0) {
                    if showBookmarks {
                        bookmarksList
                    } else {
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        // 书签按钮
                        Button(action: { showBookmarks.toggle() }) {
                            Image(systemName: "bookmark\(chapterBookmarks.isEmpty ? "" : ".fill")")
                        }
                        
                        // 主题切换
                        Button(action: { 
                            store.readerTheme = store.readerTheme == .dark ? .light : .dark
                        }) {
                            Image(systemName: store.readerTheme == .dark ? "sun.max" : "moon.fill")
                        }
                        
                        // 字体滑块
                        Slider(value: fontSizeBinding, in: 14...32)
                            .frame(maxWidth: 150)
                        
                        // 朗读按钮
                        Button(action: { 
                            if isSpeaking {
                                store.stopPlayback()
                                isSpeaking = false
                            } else {
                                Task {
                                    await store.playChapterWithTTS(chapter: chapter)
                                    isSpeaking = true
                                }
                            }
                        }) {
                            Image(systemName: isSpeaking ? "pause.fill" : "play.fill")
                        }
                        
                        // 添加书签
                        Button(action: { 
                            store.addBookmark(note: "")
                        }) {
                            Image(systemName: "plus.circle")
                        }
                    }
                    .padding()
                    .background(VisualEffectView(material: .systemThinMaterial))
                }
            }
            
            Text("\(Int((store.currentBookProgress) * 100))%")
                .font(.caption2)
                .padding(8)
                .background(Color.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(6)
                .padding()
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            store.saveState()
        }
    }
    
    private var bookmarksList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("书签 (\(chapterBookmarks.count))")
                .font(.headline)
                .padding(.horizontal)
            
            if chapterBookmarks.isEmpty {
                Text("暂无书签").foregroundColor(.secondary).padding()
            } else {
                List {
                    ForEach(chapterBookmarks) { bookmark in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bookmark.note.isEmpty ? "\(Int(bookmark.percent * 100))%" : bookmark.note)
                                    .font(.caption)
                                Text(bookmark.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: { store.removeBookmark(bookmark.id) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 150)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
        .padding()
    }
}

// Minimal visual effect wrapper for SwiftUI
import UIKit
struct VisualEffectView: UIViewRepresentable {
    let material: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: material))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct TextReaderView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TextReaderView(chapter: BookChapter(id: UUID(), title: "示例章节", text: String(repeating: "这是示例文本。\n\n", count: 30)))
                .environmentObject(ReaderStore())
        }
    }
}
