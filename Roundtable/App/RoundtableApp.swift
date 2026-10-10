import SwiftUI

@main
struct RoundtableApp: App {
    @StateObject private var store = CaptionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
