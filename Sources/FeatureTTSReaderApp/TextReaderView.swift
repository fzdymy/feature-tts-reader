import SwiftUI

struct TextReaderView: View {
    let chapter: BookChapter
    @State private var fontSize: Double = 18
    @State private var isNightMode: Bool = false

    var body: some View {
        ScrollView {
            Text(chapter.text)
                .font(.system(size: fontSize))
                .foregroundColor(isNightMode ? .white : .primary)
                .lineSpacing(8)
                .padding()
                .background(isNightMode ? Color.black : Color.white)
        }
        .background(isNightMode ? Color.black : Color(UIColor.systemGroupedBackground))
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button(action: { isNightMode.toggle() }) {
                    Label(isNightMode ? "日间" : "夜间", systemImage: isNightMode ? "sun.max" : "moon.fill")
                }
                Slider(value: $fontSize, in: 14...28, step: 1) {
                    Text("字号")
                }
                .accentColor(.blue)
                Text("\(Int(fontSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct TextReaderView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TextReaderView(chapter: BookChapter(id: UUID(), title: "示例章节", text: String(repeating: "这是示例文本。", count: 50)))
        }
    }
}
