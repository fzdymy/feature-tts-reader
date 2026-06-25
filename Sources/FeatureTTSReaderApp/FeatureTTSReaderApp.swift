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

                ContentView()
                    .environmentObject(store)
                    .tabItem { Label("朗读", systemImage: "play.circle") }
            }
        }
    }
}
