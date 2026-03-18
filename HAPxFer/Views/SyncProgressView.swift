import SwiftUI

struct SyncProgressView: View {
    @Environment(AppState.self) private var appState

    private var syncEngine: SyncEngine? {
        appState.syncEngine
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transfers")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()

                if let engine = syncEngine, engine.isSyncing {
                    HStack(spacing: 8) {
                        if engine.pendingCount > 0 {
                            Text("\(engine.pendingCount) uploading")
                        }
                        if engine.deletionCount > 0 {
                            Text("\(engine.deletionCount) deleting")
                                .foregroundStyle(.orange)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            if !appState.connectionStatus.isConnected {
                Spacer()
                ContentUnavailableView(
                    "Not Connected",
                    systemImage: "wifi.slash",
                    description: Text("Connect to your HAP-Z1ES to start transferring files.")
                )
                .frame(maxHeight: 200)
                Spacer()
            } else if let engine = syncEngine {
                if engine.isSyncing || !engine.currentTransfers.isEmpty {
                    // Overall progress
                    if engine.totalBytesToTransfer > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: engine.overallProgress) {
                                HStack {
                                    Text("Overall Progress")
                                    Spacer()
                                    Text("\(Int(engine.overallProgress * 100))%")
                                }
                                .font(.caption)
                            }
                            Text("\(formatBytes(engine.totalBytesTransferred)) / \(formatBytes(engine.totalBytesToTransfer))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding()

                        Divider()
                    }

                    // Sectioned transfer list
                    let active = engine.currentTransfers.filter { $0.isActive }
                    let waiting = engine.currentTransfers.filter { $0.isWaiting }
                    let completed = engine.currentTransfers.filter { $0.isComplete }

                    List {
                        if !active.isEmpty {
                            Section("Active") {
                                ForEach(active) { item in
                                    TransferRow(item: item)
                                }
                            }
                        }

                        if !waiting.isEmpty {
                            Section("Pending (\(waiting.count))") {
                                ForEach(waiting) { item in
                                    TransferRow(item: item)
                                }
                            }
                        }

                        if !completed.isEmpty {
                            Section("Completed (\(completed.count))") {
                                ForEach(completed) { item in
                                    TransferRow(item: item)
                                }
                            }
                        }
                    }
                } else if let lastSync = engine.lastSyncDate {
                    Spacer()
                    ContentUnavailableView {
                        Label("Up to Date", systemImage: "checkmark.circle")
                    } description: {
                        Text("Last sync: \(lastSync, style: .relative) ago")
                    }
                    .frame(maxHeight: 200)
                    Spacer()
                } else {
                    Spacer()
                    ContentUnavailableView(
                        "No Transfers",
                        systemImage: "arrow.up.circle",
                        description: Text("Click 'Sync Now' in Monitored Folders to start.")
                    )
                    .frame(maxHeight: 200)
                    Spacer()
                }

                if let error = engine.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.caption)
                        Spacer()
                    }
                    .padding()
                    .background(.red.opacity(0.1))
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct TransferRow: View {
    let item: TransferItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)

                Text(item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.isActive && item.error == nil {
                ProgressView(value: Double(item.bytesTransferred), total: Double(max(item.totalBytes, 1)))
            }

            if let error = item.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .opacity(item.isWaiting ? 0.6 : 1.0)
    }

    private var iconName: String {
        if item.error != nil { return "exclamationmark.circle.fill" }
        if item.isDeletion {
            return item.isComplete ? "trash.circle.fill" : "trash.circle"
        }
        switch item.status {
        case .complete: return "checkmark.circle.fill"
        case .active: return "arrow.up.circle.fill"
        case .waiting: return "clock"
        }
    }

    private var iconColor: Color {
        if item.error != nil { return .red }
        if item.isDeletion { return .orange }
        switch item.status {
        case .complete: return .green
        case .active: return .blue
        case .waiting: return .secondary
        }
    }
}
