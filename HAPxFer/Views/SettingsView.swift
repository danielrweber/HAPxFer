import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage("shareName") private var shareName: String = "HAP_Internal"
    @AppStorage("autoSync") private var autoSync: Bool = false
    @AppStorage("maxConcurrent") private var maxConcurrent: Int = 2
    @AppStorage("syncDeletions") private var syncDeletions: Bool = true
    @AppStorage("periodicSyncMinutes") private var periodicSyncMinutes: Int = 0

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

            Section("Scheduled Sync") {
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
                .help("Automatically sync on a fixed schedule. The device will be woken via Wake-on-LAN if needed.")

                if periodicSyncMinutes > 0 {
                    Text("The HAP-Z1ES will be woken automatically before each sync and will return to standby after its idle timeout (~20 min).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .padding()
        .onAppear {
            appState.shareName = shareName
            appState.autoSyncEnabled = autoSync
            appState.syncDeletions = syncDeletions
            appState.periodicSyncMinutes = periodicSyncMinutes
            if periodicSyncMinutes > 0 {
                appState.startPeriodicSync()
            }
        }
    }
}
