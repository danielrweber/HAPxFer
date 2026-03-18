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

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MonitoredFolder.path) private var folders: [MonitoredFolder]
    @State private var resyncCount: Int?

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

            Section("Artist Override") {
                Text("When \"Override Artist tag\" is enabled on a folder, new files get the artist tag set before upload. Already-synced files are not re-processed unless you force a re-sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Re-sync all files with artist override") {
                    resyncForArtistOverride()
                }
                .disabled(appState.syncEngine?.isSyncing == true)
                .help("Marks all synced files in folders with artist override enabled as pending, so they will be re-uploaded with the corrected Artist tag on the next sync.")
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
        .alert("Re-sync Queued", isPresented: Binding(
            get: { resyncCount != nil },
            set: { if !$0 { resyncCount = nil } }
        )) {
            Button("OK") { resyncCount = nil }
        } message: {
            if let count = resyncCount {
                Text("\(count) file(s) marked for re-upload. Run Sync Now to apply the artist override.")
            }
        }
    }

    /// Marks all synced records in artist-override folders as pending re-upload.
    private func resyncForArtistOverride() {
        var count = 0
        for folder in folders where folder.overrideArtistFromFolder && folder.isEnabled {
            for record in folder.syncRecords where record.status == .synced {
                record.status = .pending
                count += 1
            }
        }
        try? modelContext.save()
        resyncCount = count
    }
}
