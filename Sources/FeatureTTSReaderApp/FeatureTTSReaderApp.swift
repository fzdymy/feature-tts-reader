import SwiftUI

@main
struct FeatureTTSReaderApp: App {
    @StateObject private var store: ReaderStore = {
        let s = ReaderStore()
        return s
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                BookshelfView()
                    .tabItem { Label("书架", systemImage: "books.vertical") }
                TTSView()
                    .tabItem { Label("语音", systemImage: "waveform") }
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
            .environmentObject(store)
            .task { DebugLogger.startSession() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    store.saveState()
                }
            }
        }
    }
}
