import SwiftUI

@main
struct LegacyAIApp: App {
    @StateObject private var archiveStore = ArchiveStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var chatStore = ChatStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(archiveStore)
                .environmentObject(settings)
                .environmentObject(chatStore)
                .task {
                    await archiveStore.load(baseURL: settings.backendBaseURL)
                }
        }
    }
}
