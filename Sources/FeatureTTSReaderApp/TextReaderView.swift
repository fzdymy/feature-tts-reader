import SwiftUI

struct TextReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    let chapter: BookChapter
    @State private var showControls: Bool = true

    private var fontSizeBinding: Binding<Double> { $store.readerFontSize }
    private var lineSpacingBinding: Binding<Double> { $store.readerLineSpacing }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                Text(chapter.text)
                    .font(.system(size: store.readerFontSize))
                    .foregroundColor(store.readerTheme == .dark ? .white : .primary)
                    .lineSpacing(store.readerLineSpacing)
                    .padding()
                    .background(store.readerTheme == .dark ? Color.black : Color.white)
                    .onTapGesture { withAnimation { showControls.toggle() } }
            }
            if showControls {
                VStack {
                    Spacer()
                    HStack {
                        Button(action: { store.readerTheme = store.readerTheme == .dark ? .light : .dark }) {
                            Image(systemName: store.readerTheme == .dark ? "sun.max" : "moon.fill")
                        }
                        Slider(value: fontSizeBinding, in: 14...32)
                            .frame(maxWidth: 200)
                        Button(action: { store.addBookmark() }) {
                            Image(systemName: "bookmark")
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
