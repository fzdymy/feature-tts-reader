import SwiftUI

// MARK: - AudioReaderView (朗读听书模式)

struct AudioReaderView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let bookID: UUID
    @State var startChapterIndex: Int

    @State private var currentChapterIndex: Int
    @State private var displayedChapterTitle: String
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 1.0
    @State private var currentTime = Date()
    @State private var batteryLevel: Int = 100

    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init(book: Book, bookID: UUID, chapterIndex: Int) {
        self.book = book
        self.bookID = bookID
        self.startChapterIndex = chapterIndex
        self._currentChapterIndex = State(initialValue: chapterIndex)
        self._displayedChapterTitle = State(initialValue: "")
    }

    private var chapters: [BookChapter]? {
        store.chaptersForBookCached(bookID)
    }

    private var currentChapter: BookChapter? {
        guard let chs = chapters, currentChapterIndex < chs.count else { return nil }
        return chs[currentChapterIndex]
    }

    private var chapterDisplayText: String {
        guard let ch = currentChapter else { return "" }
        return "\u{3000}\u{3000}" + ch.text
            .replacingOccurrences(of: "\n", with: "\n\u{3000}\u{3000}")
    }

    private var textColor: Color {
        switch store.readerTheme {
        case .dark: return .white
        case .light: return Color(red: 0.1, green: 0.1, blue: 0.1)
        case .sepia: return Color(red: 0.2, green: 0.18, blue: 0.15)
        }
    }

    private var bgColor: Color {
        if store.customBackgroundImage != nil { return Color.clear }
        switch store.readerTheme {
        case .dark: return .black
        case .light: return .white
        case .sepia: return Color(red: 0.98, green: 0.93, blue: 0.82)
        }
    }

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                audioHeader

                // Content
                ScrollView {
                    Text(chapterDisplayText)
                        .font(Font.custom(store.readerFontName, size: store.readerFontSize + 2))
                        .foregroundColor(textColor)
                        .lineSpacing(store.readerLineSpacing + 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                }

                // Bottom controls
                audioControlBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .statusBarHidden(false)
        .onReceive(timer) { _ in
            currentTime = Date()
            updateBatteryLevel()
        }
        .onAppear {
            updateBatteryLevel()
            if displayedChapterTitle.isEmpty,
               let chs = chapters, currentChapterIndex < chs.count {
                displayedChapterTitle = chs[currentChapterIndex].title
            }
            store.selectedChapterID = currentChapter?.id
        }
    }

    // MARK: - Header

    private var audioHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(textColor.opacity(0.7))
            }
            Text(displayedChapterTitle)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(textColor)
                .padding(.leading, 8)
            Spacer()
            Text("朗读").font(.caption).foregroundColor(textColor.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(bgColor.opacity(0.9))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Control Bar

    private var audioControlBar: some View {
        VStack(spacing: 12) {
            // Progress bar
            HStack {
                Text("00:00").font(.caption2).foregroundColor(textColor.opacity(0.5)).monospacedDigit()
                Slider(value: $playbackProgress, in: 0...1)
                    .accentColor(.blue)
                Text("--:--").font(.caption2).foregroundColor(textColor.opacity(0.5)).monospacedDigit()
            }
            .padding(.horizontal, 20)

            // Main controls
            HStack(spacing: 24) {
                Button(action: previousChapter) {
                    Image(systemName: "backward.end.fill").font(.title2)
                }
                .disabled(currentChapterIndex <= 0)

                Button(action: {
                    isPlaying.toggle()
                    if isPlaying {
                        Task { await startPlayback() }
                    } else {
                        store.stopPlayback()
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                }

                Button(action: nextChapter) {
                    Image(systemName: "forward.end.fill").font(.title2)
                }
                .disabled(currentChapterIndex >= (chapters?.count ?? 1) - 1)
            }
            .foregroundColor(textColor)

            // Speed & timer
            HStack(spacing: 16) {
                speedButton("0.75x", speed: 0.75)
                speedButton("1.0x", speed: 1.0)
                speedButton("1.25x", speed: 1.25)
                speedButton("1.5x", speed: 1.5)
                speedButton("2.0x", speed: 2.0)

                Spacer()

                Button(action: {}) {
                    Image(systemName: "timer").font(.title3)
                }
                .foregroundColor(textColor.opacity(0.6))
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @State private var playbackProgress: Double = 0

    private func speedButton(_ label: String, speed: Double) -> some View {
        Button(action: {
            playbackSpeed = speed
            // TODO: apply speed to TTS engine
        }) {
            Text(label)
                .font(.caption)
                .fontWeight(playbackSpeed == speed ? .bold : .regular)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    playbackSpeed == speed
                        ? Color.blue.opacity(0.2)
                        : Color.clear
                )
                .cornerRadius(6)
                .foregroundColor(
                    playbackSpeed == speed ? .blue : textColor.opacity(0.6)
                )
        }
    }

    // MARK: - Navigation

    private func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        displayedChapterTitle = chapters?[currentChapterIndex].title ?? ""
        store.selectedChapterID = chapters?[currentChapterIndex].id
        ReaderStore.saveLastChapterIndex(currentChapterIndex, for: bookID)
        isPlaying = false
        store.stopPlayback()
    }

    private func nextChapter() {
        guard let chs = chapters, currentChapterIndex < chs.count - 1 else { return }
        if currentChapterIndex < chs.count {
            store.setChapterProgress(chs[currentChapterIndex].id, percent: 1.0)
        }
        currentChapterIndex += 1
        displayedChapterTitle = chs[currentChapterIndex].title
        store.selectedChapterID = chs[currentChapterIndex].id
        ReaderStore.saveLastChapterIndex(currentChapterIndex, for: bookID)
        isPlaying = false
        store.stopPlayback()
    }

    // MARK: - Playback (stub)

    private func startPlayback() async {
        guard let chapter = currentChapter else { return }
        await store.playChapterWithTTS(chapter: chapter)
        isPlaying = false
    }

    // MARK: - Helpers

    private func updateBatteryLevel() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel >= 0
            ? Int(UIDevice.current.batteryLevel * 100) : -1
    }
}
