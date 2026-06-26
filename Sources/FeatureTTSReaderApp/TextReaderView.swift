import SwiftUI

struct TextReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    let chapter: BookChapter
    @State private var showControls: Bool = true
    @State private var isSpeaking: Bool = false
    @State private var speakingIndex: Int = 0
    @State private var showBookmarks: Bool = false
    @State private var currentScale: CGFloat = 1.0

    private var fontSizeBinding: Binding<Double> { $store.readerFontSize }
    private var lineSpacingBinding: Binding<Double> { $store.readerLineSpacing }
    private var chapterBookmarks: [BookBookmark] {
        store.bookmarks.filter { $0.chapterID == chapter.id }
    }

    private func adjustPage(by delta: Double) {
        if let chapterID = store.selectedChapterID {
            let current = store.getChapterProgress(chapterID)
            let next = min(max(0, current + delta), 1)
            store.setChapterProgress(chapterID, percent: next)
            store.statusMessage = "已翻页，进度：\(Int(next * 100))%"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(chapter.text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { para in
                                    Text(para)
                                        .font(.system(size: store.readerFontSize))
                                        .foregroundColor(store.readerTheme == .dark ? .white : .primary)
                                        .lineSpacing(store.readerLineSpacing)
                                        .padding(.vertical, 6)
                                        .id(para)
                                        .onTapGesture(count: 2) {
                                            Task { await store.playFromParagraph(para); isSpeaking = true }
                                        }
                                }
                            }
                            .padding()
                            .id("content")
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                            })
                            Spacer().frame(height: 100)
                            Color.clear.frame(height: 1).background(GeometryReader { geo in
                                Color.clear.preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scrollView")) .minY)
                            })
                        }
                    }
                    .gesture(MagnificationGesture()
                        .onChanged { v in currentScale = v }
                        .onEnded { v in
                            let newSize = min(max(14, store.readerFontSize * Double(v)), 32)
                            store.readerFontSize = newSize
                            store.saveState()
                            currentScale = 1.0
                        }
                    )
                    .coordinateSpace(name: "scrollView")
                    .onTapGesture { withAnimation { showControls.toggle() } }
                    .onPreferenceChange(ContentHeightKey.self) { _ in }
                    .onPreferenceChange(ScrollOffsetKey.self) { minY in
                        // estimate progress by comparing minY to content height
                        DispatchQueue.main.async {
                            let contentH = (UIApplication.shared.windows.first?.bounds.height ?? 800)
                            let offset = -minY
                            let percent = max(0, min(1, Double(offset / max(200, contentH))))
                            if let chapterID = store.selectedChapterID {
                                store.setChapterProgress(chapterID, percent: percent)
                            }
                        }
                    }
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
                        Button(action: { adjustPage(by: -0.1) }) {
                            Image(systemName: "chevron.up.circle")
                        }
                        Button(action: { adjustPage(by: 0.1) }) {
                            Image(systemName: "chevron.down.circle")
                        }
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

    private struct ContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    private struct ScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
