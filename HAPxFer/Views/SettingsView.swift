import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \MonitoredFolder.path) private var folders: [MonitoredFolder]

    @AppStorage("shareName") private var shareName: String = "HAP_Internal"
    @AppStorage("autoSync") private var autoSync: Bool = false
    @AppStorage("maxConcurrent") private var maxConcurrent: Int = 2
    @AppStorage("syncDeletions") private var syncDeletions: Bool = true
    @AppStorage("periodicSyncMinutes") private var periodicSyncMinutes: Int = 0
    @AppStorage("menuBarEnabled") private var menuBarEnabled: Bool = false

    private let syncIntervalOptions = [
        (0, "Disabled"),
        (15, "Every 15 minutes"),
        (30, "Every 30 minutes"),
        (60, "Every hour"),
        (120, "Every 2 hours"),
        (360, "Every 6 hours"),
        (720, "Every 12 hours"),
        (1440, "Once a day")
    ]

    var body: some View {
        Form {
            Section("Connection") {
                TextField("SMB Share Name", text: $shareName)
                    .help("The SMB share to connect to. Usually HAP_Internal or HAP_External.")
            }

            Section("Sync") {
                Toggle("Auto-sync when files change", isOn: $autoSync)
                    .onChange(of: autoSync) { _, newValue in
                        appState.autoSyncEnabled = newValue
                        if newValue {
                            appState.startMonitoring(folders: folders)
                        } else {
                            appState.stopMonitoring()
                        }
                    }
                    .help("Watches monitored folders for changes and syncs after 60 seconds of inactivity.")

                Toggle("Delete files from device when removed locally", isOn: $syncDeletions)
                    .onChange(of: syncDeletions) { _, newValue in
                        appState.syncDeletions = newValue
                    }
                    .help("When enabled, files removed from a monitored folder will also be deleted from the HAP-Z1ES. Only affects files previously synced by this app.")

                Stepper("Concurrent transfers: \(maxConcurrent)", value: $maxConcurrent, in: 1...4)
                    .onChange(of: maxConcurrent) { _, newValue in
                        appState.syncEngine?.maxConcurrentTransfers = newValue
                    }
            }

            Section("Periodic Sync") {
                Picker("Sync interval", selection: $periodicSyncMinutes) {
                    ForEach(syncIntervalOptions, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .onChange(of: periodicSyncMinutes) { _, newValue in
                    appState.periodicSyncMinutes = newValue
                    if newValue > 0 {
                        appState.startPeriodicSync()
                    } else {
                        appState.stopPeriodicSync()
                    }
                }
                .help("Automatically sync on a fixed schedule while the app is open. The device will be woken via Wake-on-LAN if needed.")

                if periodicSyncMinutes > 0 {
                    Text("The HAP-Z1ES will be woken automatically before each sync and will return to standby after its idle timeout (~20 min).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Menu Bar") {
                Toggle("Show in menu bar", isOn: $menuBarEnabled)
                    .onChange(of: menuBarEnabled) { _, newValue in
                        appState.menuBarMode = newValue
                    }
                    .help("Show a menu bar icon for quick access to sync status and controls. When enabled, closing the window keeps the app running.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .padding()
        .onAppear {
            appState.shareName = shareName
            appState.autoSyncEnabled = autoSync
            appState.syncDeletions = syncDeletions
            appState.menuBarMode = menuBarEnabled
            appState.periodicSyncMinutes = periodicSyncMinutes
            if periodicSyncMinutes > 0 {
                appState.startPeriodicSync()
            }
        }
    }
}
