// This file is part of HAPxFer - Music transfer for Sony HAP-Z1ES
// Copyright (C) 2026 Daniel Weber
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import SwiftUI
import SwiftData
import UserNotifications

@main
struct HAPxFerApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarEnabled") private var menuBarEnabled: Bool = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("HAPxFer", id: "main") {
            MainView()
                .environment(appState)
                .onAppear {
                    appDelegate.menuBarEnabled = menuBarEnabled
                    MetadataService.cleanupStaleTempFiles()
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
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
        .modelContainer(for: [MonitoredFolder.self, SyncRecord.self, SyncLogEntry.self])

        Window("About HAPxFer", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 700)

        // Menu bar extra — only shown when enabled in Settings
        MenuBarExtra("HAPxFer", systemImage: "arrow.triangle.2.circlepath.circle", isInserted: $menuBarEnabled) {
            MenuBarView(openWindow: openWindow)
                .environment(appState)
        }
    }
}

/// App delegate to intercept window close and hide instead of quit when menu bar is active
final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarEnabled: Bool = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when closing the window if menu bar mode is on
        return !menuBarEnabled
    }
}

/// Lightweight menu bar dropdown for status and quick actions
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    var openWindow: OpenWindowAction

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
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
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
