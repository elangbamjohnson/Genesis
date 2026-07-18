import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
