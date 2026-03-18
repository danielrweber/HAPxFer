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

        // Menu bar extra — always visible for background sync control
        MenuBarExtra("HAPxFer", systemImage: "hifispeaker.2.fill") {
            MenuBarView()
                .environment(appState)
        }
    }
}

/// Lightweight menu bar dropdown for status and quick actions
struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Sync status
            if let engine = appState.syncEngine, engine.isSyncing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing... \(Int(engine.overallProgress * 100))%")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else if let lastSync = appState.lastAutoSync {
                Text("Last sync: \(lastSync, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            Divider()

            // Actions
            Button("Sync Now") {
                Task { await appState.autoSync() }
            }
            .disabled(appState.syncEngine?.isSyncing == true)
            .keyboardShortcut("s")

            if appState.periodicSyncMinutes > 0 {
                Text("Auto-sync every \(appState.periodicSyncMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            Divider()

            Button("Open HAPxFer") {
                NSApp.activate(ignoringOtherApps: true)
                // The main window will be shown by the WindowGroup
            }
            .keyboardShortcut("o")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .connected: return .green
        case .connecting, .waking: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.connectionStatus {
        case .connected: return appState.deviceInfo?.name ?? "Connected"
        case .connecting: return "Connecting..."
        case .waking: return "Waking device..."
        case .disconnected: return "Not Connected"
        case .error: return "Connection Error"
        }
    }
}
