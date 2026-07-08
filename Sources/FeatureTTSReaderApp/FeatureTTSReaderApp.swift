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
            BookshelfView()
                .environmentObject(store)
                .onAppear {
                    ReaderStore.writeCrashMarker("bookshelf_onAppear")
                    // Defer all audio + state loading to background, after view is settled
                    Task.detached(priority: .background) {
                        await MainActor.run {
                            store.audioController.ensureEngineSetup()
                            store.audioController.ensureEngineStarted()
                            ReaderStore.writeCrashMarker("bookshelf_engine_setup")
                        }
                        await store.loadStateAsync()
                        ReaderStore.writeCrashMarker("bookshelf_task_done")
                    }
                }
        }
    }
}
