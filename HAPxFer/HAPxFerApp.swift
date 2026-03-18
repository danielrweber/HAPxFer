import SwiftUI
import SwiftData

@main
struct HAPxFerApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
        }
        .modelContainer(for: [MonitoredFolder.self, SyncRecord.self, SyncLogEntry.self])
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About HAPxFer") {
                    openWindow(id: "about")
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }

        Window("About HAPxFer", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 700)
    }
}
