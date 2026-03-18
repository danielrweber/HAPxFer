import SwiftUI
import SwiftData

/// Navigable file browser for the HAP-Z1ES remote share.
/// Shows HDD info, allows drilling into subdirectories and deleting files.
struct RemoteBrowserView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var currentPath: String = ""
    @State private var pathStack: [String] = []
    @State private var items: [RemoteFileInfo] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    // HDD info
    @State private var diskSpace: DiskSpaceInfo?
    @State private var trackCount: Int = 0
    @State private var albumCount: Int = 0
    @State private var isLoadingStats: Bool = true

    // Delete confirmation
    @State private var itemPendingDeletion: RemoteFileInfo?

    var body: some View {
        VStack(spacing: 0) {
            // HDD Info bar
            if let disk = diskSpace {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "internaldrive.fill")
                            .foregroundStyle(.blue)
                        Text("HAP-Z1ES Internal HDD")
                            .font(.headline)
                        Spacer()
                        Button("Close") { dismiss() }
                            .buttonStyle(.borderless)
                    }

                    ProgressView(value: disk.usedFraction) {
                        HStack {
                            Text("\(disk.usedFormatted) used of \(disk.totalFormatted)")
                            Spacer()
                            Text("\(disk.freeFormatted) free")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .tint(disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.75 ? .orange : .blue)

                    HStack(spacing: 16) {
                        if isLoadingStats {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning content...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("\(trackCount) tracks", systemImage: "music.note")
                            Label("\(albumCount) albums", systemImage: "square.stack")
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()

                Divider()
            } else {
                // Minimal header when disk info not yet loaded
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .foregroundStyle(.blue)
                    Text("HAP-Z1ES Internal HDD")
                        .font(.headline)
                    Spacer()
                    if isLoadingStats {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderless)
                }
                .padding()

                Divider()
            }

            // Navigation bar
            HStack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(pathStack.isEmpty)
                .buttonStyle(.borderless)

                Text(currentPath.isEmpty ? "Root" : (currentPath as NSString).lastPathComponent)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if !items.isEmpty {
                    Text("\(items.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            // Breadcrumb path
            if !currentPath.isEmpty {
                HStack(spacing: 2) {
                    Button("Root") {
                        navigateTo(path: "")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    let components = currentPath.split(separator: "/").map(String.init)
                    ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                        Text("/")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(component) {
                            let newPath = components.prefix(index + 1).joined(separator: "/")
                            navigateTo(path: newPath)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { loadDirectory() }
                }
            } else if items.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder")
            } else {
                List {
                    let sorted = items.sorted { a, b in
                        if a.isDirectory != b.isDirectory { return a.isDirectory }
                        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    }

                    ForEach(sorted, id: \.path) { item in
                        if item.isDirectory {
                            Button {
                                navigateInto(item)
                            } label: {
                                RemoteFileRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    itemPendingDeletion = item
                                } label: {
                                    Label("Delete from Device", systemImage: "trash")
                                }
                            }
                        } else {
                            RemoteFileRow(item: item)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        itemPendingDeletion = item
                                    } label: {
                                        Label("Delete from Device", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 550, minHeight: 500)
        .onAppear {
            loadDirectory()
            loadHDDInfo()
        }
        .alert("Delete from Device", isPresented: Binding(
            get: { itemPendingDeletion != nil },
            set: { if !$0 { itemPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                itemPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if let item = itemPendingDeletion {
                    Task { await deleteItem(item) }
                }
                itemPendingDeletion = nil
            }
        } message: {
            if let item = itemPendingDeletion {
                if item.isDirectory {
                    Text("Delete \"\(item.name)\" and all its contents from the HAP-Z1ES? Files deleted this way will not be re-synced.")
                } else {
                    Text("Delete \"\(item.name)\" from the HAP-Z1ES? This file will not be re-synced.")
                }
            }
        }
    }

    // MARK: - Navigation

    private func loadDirectory() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                items = try await appState.listRemoteDirectory(at: currentPath)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func navigateInto(_ item: RemoteFileInfo) {
        pathStack.append(currentPath)
        currentPath = item.path
        loadDirectory()
    }

    private func navigateTo(path: String) {
        pathStack.removeAll()
        currentPath = path
        loadDirectory()
    }

    private func goBack() {
        guard let previous = pathStack.popLast() else { return }
        currentPath = previous
        loadDirectory()
    }

    // MARK: - HDD Info

    private func loadHDDInfo() {
        Task {
            diskSpace = await appState.fetchDiskSpace()
            let stats = await appState.fetchContentStats()
            trackCount = stats.tracks
            albumCount = stats.albums
            isLoadingStats = false
        }
    }

    // MARK: - Delete

    private func deleteItem(_ item: RemoteFileInfo) async {
        do {
            if item.isDirectory {
                // Recursively delete directory contents first
                await deleteDirectoryRecursively(at: item.path)
            } else {
                try await appState.deleteRemoteFile(at: item.path)
                markAsManuallyRemoved(remotePath: item.path)
            }

            // Refresh the directory listing
            loadDirectory()

            // Refresh disk space
            diskSpace = await appState.fetchDiskSpace()

        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func deleteDirectoryRecursively(at path: String) async {
        do {
            let contents = try await appState.listRemoteDirectory(at: path)
            for item in contents {
                if item.isDirectory {
                    await deleteDirectoryRecursively(at: item.path)
                } else {
                    try await appState.deleteRemoteFile(at: item.path)
                    markAsManuallyRemoved(remotePath: item.path)
                }
            }
            try await appState.deleteRemoteDirectory(at: path)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    /// Mark matching SyncRecords as manuallyRemoved so sync won't re-upload
    private func markAsManuallyRemoved(remotePath: String) {
        let descriptor = FetchDescriptor<MonitoredFolder>()
        guard let folders = try? modelContext.fetch(descriptor) else { return }

        for folder in folders {
            for record in folder.syncRecords {
                let fullRemotePath = folder.remotePath.isEmpty
                    ? record.relativePath
                    : "\(folder.remotePath)/\(record.relativePath)"
                if fullRemotePath == remotePath && record.status == .synced {
                    record.status = .manuallyRemoved
                }
            }
        }
        try? modelContext.save()
    }
}

struct RemoteFileRow: View {
    let item: RemoteFileInfo

    var body: some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon)
                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let date = item.modificationDate, date.timeIntervalSince1970 > 0 {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !item.isDirectory {
                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var fileIcon: String {
        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "dsf", "dff": return "waveform"
        case "flac", "wav", "aiff", "aif", "alac": return "music.note"
        case "mp3", "m4a", "aac": return "music.note"
        default: return "doc"
        }
    }
}
