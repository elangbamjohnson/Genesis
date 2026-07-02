import SwiftUI

@main
struct LegacyAIApp: App {
    @StateObject private var archiveStore = ArchiveStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(archiveStore)
                .environmentObject(settings)
        }
    }
}
