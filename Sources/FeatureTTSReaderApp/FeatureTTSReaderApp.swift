import SwiftUI

@main
struct FeatureTTSReaderApp: App {
    @StateObject private var store: ReaderStore = {
        ReaderStore.writeCrashMarker("app_init_start")
        let s = ReaderStore()
        ReaderStore.writeCrashMarker("app_init_done")
        return s
    }()

    var body: some Scene {
        ReaderStore.writeCrashMarker("app_body_start")
        return WindowGroup {
            TabView {
                BookshelfView()
                    .environmentObject(store)
                    .onAppear { ReaderStore.writeCrashMarker("bookshelf_onAppear") }
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
