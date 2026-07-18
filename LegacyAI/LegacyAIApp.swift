import SwiftUI

@main
struct LegacyAIApp: App {
    @StateObject private var archiveStore = ArchiveStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var chatStore = ChatStore()
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = sessionManager.currentSession {
                    switch session.role {
                    case .owner:
                        ContentView()
                            .task {
                                await archiveStore.load(baseURL: settings.backendBaseURL)
                            }
                    case .visitor:
                        VisitorChatView()
                    }
                } else {
                    EntryView()
                }
            }
            .environmentObject(archiveStore)
            .environmentObject(settings)
            .environmentObject(chatStore)
            .environmentObject(sessionManager)
        }
    }
}
