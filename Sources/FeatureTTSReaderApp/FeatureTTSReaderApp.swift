import SwiftUI

@main
struct FeatureTTSReaderApp: App {
    @StateObject private var store = ReaderStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                BookshelfView()
                    .environmentObject(store)
                    .tabItem { Label("书架", systemImage: "books.vertical") }

                TTSView()
                    .environmentObject(store)
                    .tabItem { Label("TTS", systemImage: "waveform") }

                SettingsView()
                    .environmentObject(store)
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
        }
    }
}
