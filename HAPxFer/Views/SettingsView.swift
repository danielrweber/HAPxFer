import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage("shareName") private var shareName: String = "HAP_Internal"
    @AppStorage("autoSync") private var autoSync: Bool = false
    @AppStorage("maxConcurrent") private var maxConcurrent: Int = 2
    @AppStorage("syncDeletions") private var syncDeletions: Bool = true

    var body: some View {
        @Bindable var state = appState

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
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .onAppear {
            appState.shareName = shareName
            appState.autoSyncEnabled = autoSync
            appState.syncDeletions = syncDeletions
        }
    }
}
