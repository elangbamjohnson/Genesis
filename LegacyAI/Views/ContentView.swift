import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }

            EntryListView()
                .tabItem {
                    Label("Archive", systemImage: "tray.full")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ArchiveStore())
        .environmentObject(AppSettings())
}
