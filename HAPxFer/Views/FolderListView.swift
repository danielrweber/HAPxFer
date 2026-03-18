import SwiftUI
import SwiftData

struct FolderListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MonitoredFolder.path) private var folders: [MonitoredFolder]

    @State private var showFilePicker = false
    @State private var folderPendingRemoval: MonitoredFolder?
    @State private var folderPendingDisable: MonitoredFolder?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Monitored Folders")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showFilePicker = true
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }

                if appState.connectionStatus.isConnected {
                    Button {
                        Task { await appState.syncEngine?.syncAll(syncDeletions: appState.syncDeletions) }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(appState.syncEngine?.isSyncing ?? false)
                }
            }
            .padding()

            Divider()

            if folders.isEmpty {
                ContentUnavailableView {
                    Label("No Folders", systemImage: "folder.badge.plus")
                } description: {
                    Text("Add folders containing your music files to sync with the HAP-Z1ES.")
                } actions: {
                    Button("Add Folder") { showFilePicker = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(folders) { folder in
                        FolderRow(
                            folder: folder,
                            onRemove: {
                                if folder.syncRecords.contains(where: { $0.status == .synced }) &&
                                   appState.connectionStatus.isConnected {
                                    folderPendingRemoval = folder
                                } else {
                                    removeFolderOnly(folder)
                                }
                            },
                            onDisable: {
                                if folder.syncRecords.contains(where: { $0.status == .synced }) &&
                                   appState.connectionStatus.isConnected {
                                    folderPendingDisable = folder
                                } else {
                                    folder.isEnabled = false
                                    try? modelContext.save()
                                }
                            }
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                if folder.syncRecords.contains(where: { $0.status == .synced }) &&
                                   appState.connectionStatus.isConnected {
                                    folderPendingRemoval = folder
                                } else {
                                    removeFolderOnly(folder)
                                }
                            } label: {
                                Label("Remove Folder", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            handleFolderSelection(result)
        }
        // Confirmation for removing a folder
        .alert("Remove Folder", isPresented: Binding(
            get: { folderPendingRemoval != nil },
            set: { if !$0 { folderPendingRemoval = nil } }
        )) {
            Button("Keep Files on Device") {
                if let folder = folderPendingRemoval {
                    removeFolderOnly(folder)
                }
                folderPendingRemoval = nil
            }
            Button("Delete Files from Device", role: .destructive) {
                if let folder = folderPendingRemoval {
                    Task {
                        await deleteRemoteFilesAndRemoveFolder(folder)
                    }
                }
                folderPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                folderPendingRemoval = nil
            }
        } message: {
            if let folder = folderPendingRemoval {
                let count = folder.syncRecords.filter { $0.status == .synced }.count
                Text("\"\(folder.displayName)\" has \(count) synced file(s) on the HAP-Z1ES. Would you also like to delete them from the device?")
            }
        }
        // Confirmation for disabling a folder
        .alert("Disable Folder", isPresented: Binding(
            get: { folderPendingDisable != nil },
            set: { if !$0 { folderPendingDisable = nil } }
        )) {
            Button("Keep Files on Device") {
                if let folder = folderPendingDisable {
                    folder.isEnabled = false
                    try? modelContext.save()
                }
                folderPendingDisable = nil
            }
            Button("Delete Files from Device", role: .destructive) {
                if let folder = folderPendingDisable {
                    Task {
                        await deleteRemoteFilesForFolder(folder)
                        folder.isEnabled = false
                        try? modelContext.save()
                    }
                }
                folderPendingDisable = nil
            }
            Button("Cancel", role: .cancel) {
                // Re-enable since the toggle already flipped
                folderPendingDisable?.isEnabled = true
                try? modelContext.save()
                folderPendingDisable = nil
            }
        } message: {
            if let folder = folderPendingDisable {
                let count = folder.syncRecords.filter { $0.status == .synced }.count
                Text("\"\(folder.displayName)\" has \(count) synced file(s) on the HAP-Z1ES. Would you also like to delete them from the device?")
            }
        }
    }

    // MARK: - Actions

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            let bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let folder = MonitoredFolder(
                path: url.path(percentEncoded: false),
                bookmarkData: bookmarkData
            )
            modelContext.insert(folder)
        }
        try? modelContext.save()
    }

    /// Remove the folder from the monitored list without touching the device.
    private func removeFolderOnly(_ folder: MonitoredFolder) {
        modelContext.delete(folder)
        try? modelContext.save()
    }

    /// Delete all synced files from the device for this folder, then remove it.
    private func deleteRemoteFilesAndRemoveFolder(_ folder: MonitoredFolder) async {
        await deleteRemoteFilesForFolder(folder)
        modelContext.delete(folder)
        try? modelContext.save()
    }

    /// Delete all synced files from the device for this folder.
    private func deleteRemoteFilesForFolder(_ folder: MonitoredFolder) async {
        let syncedRecords = folder.syncRecords.filter { $0.status == .synced }
        guard !syncedRecords.isEmpty else { return }

        for record in syncedRecords {
            let remotePath = folder.remotePath.isEmpty
                ? record.relativePath
                : "\(folder.remotePath)/\(record.relativePath)"
            do {
                _ = try await appState.listRemoteDirectory(at: "") // ensure connection is alive
                try await deleteRemoteFile(at: remotePath)
                record.status = .deleted

                // Log the deletion
                let logEntry = SyncLogEntry(
                    action: .deleted,
                    relativePath: record.relativePath,
                    fileSize: record.fileSize,
                    folderName: folder.displayName
                )
                modelContext.insert(logEntry)
            } catch {
                // Log failure but continue with other files
                let logEntry = SyncLogEntry(
                    action: .deleted,
                    relativePath: record.relativePath,
                    fileSize: record.fileSize,
                    folderName: folder.displayName,
                    success: false,
                    errorMessage: error.localizedDescription
                )
                modelContext.insert(logEntry)
            }
        }
        try? modelContext.save()
    }

    /// Delete a single remote file via the SMB service.
    private func deleteRemoteFile(at path: String) async throws {
        // Access the SMB service through AppState's public method
        // We use a dedicated method on AppState for this
        try await appState.deleteRemoteFile(at: path)
    }
}

struct FolderRow: View {
    @Bindable var folder: MonitoredFolder
    var onRemove: () -> Void
    var onDisable: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(folder.isEnabled ? .blue : .gray)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                    .fontWeight(.medium)
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let lastSync = folder.lastSyncDate {
                Text(lastSync, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let syncedCount = folder.syncRecords.filter { $0.status == .synced }.count
            if syncedCount > 0 {
                Text("\(syncedCount) files")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Toggle("", isOn: Binding(
                get: { folder.isEnabled },
                set: { newValue in
                    if !newValue {
                        onDisable()
                    } else {
                        folder.isEnabled = true
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove folder")
        }
        .padding(.vertical, 2)
    }
}
