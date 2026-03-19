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

import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.hapxfer", category: "SyncEngine")

/// Represents a single file being transferred or deleted
struct TransferItem: Identifiable, Sendable {
    let id: String
    let fileName: String
    /// The relative path including parent folders (e.g. "Artist/Album/Track.flac")
    let relativePath: String
    let totalBytes: Int64
    var bytesTransferred: Int64 = 0
    var status: Status = .waiting
    var error: String?
    var isDeletion: Bool = false

    var isComplete: Bool { status == .complete }
    var isActive: Bool { status == .active }
    var isWaiting: Bool { status == .waiting }

    enum Status: Sendable {
        case waiting
        case active
        case complete
    }
}

/// File info collected during scanning, safe to pass across isolation boundaries
private struct PendingFile: Sendable {
    let relativePath: String
    let localURL: URL
    let size: Int64
    let modDate: Date
}

/// A file that should be deleted from the remote device
private struct PendingDeletion: Sendable {
    let relativePath: String
    let size: Int64
}

/// Orchestrates scanning, diffing, and transferring files to the HAP-Z1ES.
@Observable
@MainActor
final class SyncEngine {
    var currentTransfers: [TransferItem] = []
    var pendingCount: Int = 0
    var deletionCount: Int = 0
    var totalBytesToTransfer: Int64 = 0
    var totalBytesTransferred: Int64 = 0
    var isSyncing: Bool = false
    var lastError: String?
    var lastSyncDate: Date?
    /// Counts from the most recent sync run (reset at the start of each sync).
    var completedCount: Int = 0
    var failedCount: Int = 0

    var overallProgress: Double {
        guard totalBytesToTransfer > 0 else { return 0 }
        return Double(totalBytesTransferred) / Double(totalBytesToTransfer)
    }

    private let smbService: any SMBServiceProtocol
    private let modelContainer: ModelContainer
    var maxConcurrentTransfers: Int = 2

    init(smbService: any SMBServiceProtocol, modelContainer: ModelContainer) {
        self.smbService = smbService
        self.modelContainer = modelContainer
    }

    func syncAll(syncDeletions: Bool = true) async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<MonitoredFolder>(
            predicate: #Predicate { $0.isEnabled }
        )

        do {
            let folders = try context.fetch(descriptor)
            guard !folders.isEmpty else {
                logger.info("No enabled folders to sync")
                return
            }

            isSyncing = true
            lastError = nil
            currentTransfers = []
            totalBytesToTransfer = 0
            totalBytesTransferred = 0
            deletionCount = 0
            completedCount = 0
            failedCount = 0

            for folder in folders {
                // Switch to the correct share for this folder's destination
                let targetShare = folder.destinationShare
                do {
                    try await smbService.switchShare(targetShare)
                } catch {
                    logger.error("Failed to switch to share \(targetShare) for \(folder.displayName): \(error.localizedDescription)")
                    continue
                }

                let folderPath = folder.path
                let folderRemotePath = folder.remotePath
                let folderDisplayName = folder.displayName
                let overrideArtist = folder.overrideArtistFromFolder
                let existingRecords = folder.syncRecords.map { record in
                    (relativePath: record.relativePath, fileSize: record.fileSize,
                     localModDate: record.localModDate, status: record.status)
                }

                // Scan and diff on main actor (data is local)
                let folderURL = URL(fileURLWithPath: folderPath)
                let localFiles = Self.scanLocalFiles(at: folderURL)

                // Reconcile: if this folder has no sync records yet, scan the HAP
                // to find files that already exist so we don't re-upload duplicates.
                if folder.syncRecords.isEmpty && !localFiles.isEmpty {
                    logger.info("Reconciling \(folderDisplayName) — scanning remote for existing files")
                    let reconciled = await reconcileWithRemote(
                        localFiles: localFiles,
                        remotePath: folderRemotePath,
                        folder: folder,
                        context: context
                    )
                    if reconciled > 0 {
                        logger.info("Reconciled \(reconciled) file(s) already on device for \(folderDisplayName)")
                    }
                }

                // Re-fetch records after reconciliation
                let updatedRecords = folder.syncRecords.map { record in
                    (relativePath: record.relativePath, fileSize: record.fileSize,
                     localModDate: record.localModDate, status: record.status)
                }

                let pending = Self.diffFiles(
                    localFiles: localFiles,
                    existingRecords: updatedRecords,
                    baseFolderURL: folderURL
                )

                // --- Upload new/changed files ---
                if !pending.isEmpty {
                    // Update SwiftData records for pending files
                    for file in pending {
                        if let record = folder.syncRecords.first(where: { $0.relativePath == file.relativePath }) {
                            record.status = .pending
                            record.fileSize = file.size
                            record.localModDate = file.modDate
                        } else {
                            let record = SyncRecord(relativePath: file.relativePath, fileSize: file.size, localModDate: file.modDate)
                            record.folder = folder
                            context.insert(record)
                        }
                    }
                    try? context.save()

                    pendingCount += pending.count
                    totalBytesToTransfer += pending.reduce(0) { $0 + $1.size }

                    // Transfer files
                    await transferFiles(pending, remotePath: folderRemotePath, overrideArtist: overrideArtist)

                    // Update folder sync date and records, create log entries
                    for file in pending {
                        if let record = folder.syncRecords.first(where: { $0.relativePath == file.relativePath }) {
                            let transferError = currentTransfers.first(where: { $0.id == file.relativePath })?.error
                            if transferError == nil {
                                record.status = .synced
                                record.syncDate = Date()
                                completedCount += 1
                                // Log successful upload
                                let logEntry = SyncLogEntry(
                                    action: .uploaded,
                                    relativePath: file.relativePath,
                                    fileSize: file.size,
                                    folderName: folderDisplayName
                                )
                                context.insert(logEntry)
                            } else {
                                record.status = .failed
                                failedCount += 1
                                // Log failed upload
                                let logEntry = SyncLogEntry(
                                    action: .uploaded,
                                    relativePath: file.relativePath,
                                    fileSize: file.size,
                                    folderName: folderDisplayName,
                                    success: false,
                                    errorMessage: transferError
                                )
                                context.insert(logEntry)
                            }
                        }
                    }
                    try? context.save()
                }

                // --- Delete files removed locally ---
                if syncDeletions {
                    let localFileSet = Set(localFiles.map(\.relativePath))
                    let deletions = Self.findDeletedFiles(
                        existingRecords: existingRecords,
                        localFileSet: localFileSet
                    )

                    if !deletions.isEmpty {
                        deletionCount += deletions.count

                        for deletion in deletions {
                            let remoteFilePath = folderRemotePath.isEmpty
                                ? deletion.relativePath
                                : "\(folderRemotePath)/\(deletion.relativePath)"

                            let item = TransferItem(
                                id: "del:\(deletion.relativePath)",
                                fileName: (deletion.relativePath as NSString).lastPathComponent,
                                relativePath: deletion.relativePath,
                                totalBytes: deletion.size,
                                isDeletion: true
                            )
                            currentTransfers.append(item)

                            do {
                                try await smbService.deleteFile(at: remoteFilePath)

                                // Try to remove empty parent directories
                                await cleanupEmptyDirectories(
                                    for: deletion.relativePath,
                                    remotePath: folderRemotePath
                                )

                                // Mark transfer complete
                                if let idx = currentTransfers.firstIndex(where: { $0.id == "del:\(deletion.relativePath)" }) {
                                    currentTransfers[idx].status = .complete
                                }

                                // Update record
                                if let record = folder.syncRecords.first(where: { $0.relativePath == deletion.relativePath }) {
                                    record.status = .deleted
                                }

                                // Log successful deletion
                                let logEntry = SyncLogEntry(
                                    action: .deleted,
                                    relativePath: deletion.relativePath,
                                    fileSize: deletion.size,
                                    folderName: folderDisplayName
                                )
                                context.insert(logEntry)

                                logger.info("Deleted remote file: \(remoteFilePath)")
                            } catch {
                                if let idx = currentTransfers.firstIndex(where: { $0.id == "del:\(deletion.relativePath)" }) {
                                    currentTransfers[idx].error = error.localizedDescription
                                }

                                // Log failed deletion
                                let logEntry = SyncLogEntry(
                                    action: .deleted,
                                    relativePath: deletion.relativePath,
                                    fileSize: deletion.size,
                                    folderName: folderDisplayName,
                                    success: false,
                                    errorMessage: error.localizedDescription
                                )
                                context.insert(logEntry)

                                logger.error("Failed to delete: \(remoteFilePath) - \(error.localizedDescription)")
                            }
                        }
                        try? context.save()
                    }
                }

                folder.lastSyncDate = Date()
                try? context.save()
            }

            lastSyncDate = Date()
            isSyncing = false

            try? await Task.sleep(for: .seconds(3))
            currentTransfers.removeAll(where: { $0.isComplete })
        } catch {
            lastError = error.localizedDescription
            isSyncing = false
        }
    }

    func syncFolderByPath(_ path: String) async {
        await syncAll()
    }

    // MARK: - Private

    /// Recursively scan a directory for supported audio files.
    private static func scanLocalFiles(at url: URL) -> [(relativePath: String, size: Int64, modDate: Date)] {
        let fm = FileManager.default
        var results: [(String, Int64, Date)] = []

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        let basePath = url.path
        for case let fileURL as URL in enumerator {
            guard FileFilters.isSupported(fileURL) else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            let relativePath = String(fileURL.path.dropFirst(basePath.count + 1))
            let size = Int64(values.fileSize ?? 0)
            let modDate = values.contentModificationDate ?? Date.distantPast

            results.append((relativePath, size, modDate))
        }

        return results
    }

    /// Compare local files against existing sync records to find new/changed files.
    private static func diffFiles(
        localFiles: [(relativePath: String, size: Int64, modDate: Date)],
        existingRecords: [(relativePath: String, fileSize: Int64, localModDate: Date, status: SyncRecord.SyncStatus)],
        baseFolderURL: URL
    ) -> [PendingFile] {
        let recordMap = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.relativePath, $0) })
        var pending: [PendingFile] = []

        for file in localFiles {
            if let record = recordMap[file.relativePath] {
                // Skip files manually removed from device via Browse
                if record.status == .manuallyRemoved {
                    continue
                }
                if record.status == .synced && record.fileSize == file.size &&
                   abs(record.localModDate.timeIntervalSince(file.modDate)) < 1.0 {
                    continue
                }
            }
            pending.append(PendingFile(
                relativePath: file.relativePath,
                localURL: baseFolderURL.appendingPathComponent(file.relativePath),
                size: file.size,
                modDate: file.modDate
            ))
        }

        return pending
    }

    /// Find synced records whose local files no longer exist.
    /// Only returns files that were previously synced by this app (status .synced).
    private static func findDeletedFiles(
        existingRecords: [(relativePath: String, fileSize: Int64, localModDate: Date, status: SyncRecord.SyncStatus)],
        localFileSet: Set<String>
    ) -> [PendingDeletion] {
        var deletions: [PendingDeletion] = []

        for record in existingRecords {
            // Only delete files we previously synced — never touch manually placed files
            guard record.status == .synced else { continue }
            if !localFileSet.contains(record.relativePath) {
                deletions.append(PendingDeletion(
                    relativePath: record.relativePath,
                    size: record.fileSize
                ))
            }
        }

        return deletions
    }

    /// Scan the remote device and match files against local files by path and size.
    /// Creates SyncRecord entries for matches so they won't be re-uploaded.
    private func reconcileWithRemote(
        localFiles: [(relativePath: String, size: Int64, modDate: Date)],
        remotePath: String,
        folder: MonitoredFolder,
        context: ModelContext
    ) async -> Int {
        // Build a lookup of local files by relative path
        let localMap = Dictionary(uniqueKeysWithValues: localFiles.map { ($0.relativePath, $0) })

        // Recursively scan the remote directory
        let remoteFiles = await scanRemoteFiles(at: remotePath)

        var matched = 0
        for remoteFile in remoteFiles {
            // Remote path relative to the folder's remote root
            let relPath: String
            if remotePath.isEmpty {
                relPath = remoteFile.path
            } else if remoteFile.path.hasPrefix(remotePath + "/") {
                relPath = String(remoteFile.path.dropFirst(remotePath.count + 1))
            } else {
                relPath = remoteFile.path
            }

            // Match by relative path only — size may differ due to artist override metadata
            if let local = localMap[relPath] {
                let record = SyncRecord(
                    relativePath: relPath,
                    fileSize: local.size,
                    localModDate: local.modDate
                )
                record.status = .synced
                record.syncDate = Date()
                record.folder = folder
                context.insert(record)
                matched += 1
            }
        }

        if matched > 0 {
            try? context.save()
        }
        return matched
    }

    /// Recursively list all files on the remote device at the given path.
    private func scanRemoteFiles(at path: String) async -> [(path: String, size: Int64)] {
        var results: [(path: String, size: Int64)] = []

        guard let items = try? await smbService.listDirectory(at: path) else {
            return results
        }

        for item in items {
            if item.isDirectory {
                let subResults = await scanRemoteFiles(at: item.path)
                results.append(contentsOf: subResults)
            } else if FileFilters.isSupportedName(item.name) {
                results.append((path: item.path, size: item.size))
            }
        }

        return results
    }

    /// Try to remove empty parent directories after a file deletion.
    private func cleanupEmptyDirectories(for relativePath: String, remotePath: String) async {
        var components = relativePath.split(separator: "/").map(String.init)
        components.removeLast() // Remove the filename

        // Walk up the directory tree
        while !components.isEmpty {
            let dirRelPath = components.joined(separator: "/")
            let remoteDirPath = remotePath.isEmpty ? dirRelPath : "\(remotePath)/\(dirRelPath)"

            do {
                try await smbService.deleteDirectory(at: remoteDirPath)
                logger.info("Cleaned up empty directory: \(remoteDirPath)")
            } catch {
                // Directory not empty or other error — stop climbing
                break
            }

            components.removeLast()
        }
    }

    /// Transfer files to the device with concurrency control.
    private func transferFiles(_ files: [PendingFile], remotePath: String, overrideArtist: Bool = false) async {
        let sorted = files.sorted { $0.relativePath < $1.relativePath }
        let service = smbService
        let maxConcurrent = maxConcurrentTransfers

        // Add ALL files to the transfer list upfront as "waiting"
        for file in sorted {
            let item = TransferItem(
                id: file.relativePath,
                fileName: (file.relativePath as NSString).lastPathComponent,
                relativePath: file.relativePath,
                totalBytes: file.size,
                status: .waiting
            )
            currentTransfers.append(item)
        }

        await withTaskGroup(of: (String, String?).self) { group in
            var inFlight = 0

            for file in sorted {
                if inFlight >= maxConcurrent {
                    if let result = await group.next() {
                        handleTransferResult(id: result.0, error: result.1)
                    }
                    inFlight -= 1
                }

                let remoteFilePath = remotePath.isEmpty
                    ? file.relativePath
                    : "\(remotePath)/\(file.relativePath)"

                let relPath = file.relativePath

                // Mark as active
                if let idx = currentTransfers.firstIndex(where: { $0.id == relPath }) {
                    currentTransfers[idx].status = .active
                }

                // Progress callback — updates per-file and overall progress on MainActor
                let progressCallback: TransferProgress = { [weak self] bytesTransferred, totalBytes in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let idx = self.currentTransfers.firstIndex(where: { $0.id == relPath }) {
                            let previousBytes = self.currentTransfers[idx].bytesTransferred
                            let delta = bytesTransferred - previousBytes
                            self.currentTransfers[idx].bytesTransferred = bytesTransferred
                            self.totalBytesTransferred += delta
                        }
                    }
                }

                inFlight += 1
                group.addTask {
                    var uploadURL = file.localURL
                    var tempURL: URL? = nil

                    // If artist override is enabled, create a temp copy with modified metadata
                    if overrideArtist,
                       let artist = MetadataService.artistFromRelativePath(file.relativePath) {
                        do {
                            let temp = try MetadataService.copyWithArtistOverride(
                                sourceURL: file.localURL,
                                artist: artist
                            )
                            uploadURL = temp
                            tempURL = temp
                        } catch {
                            // Graceful degradation: upload with original metadata
                            logger.warning("Artist override failed for \(relPath): \(error.localizedDescription)")
                        }
                    }

                    defer {
                        if let tempURL {
                            MetadataService.cleanupTempFile(at: tempURL)
                        }
                    }

                    do {
                        try await service.upload(
                            localURL: uploadURL,
                            remotePath: remoteFilePath,
                            progress: progressCallback
                        )
                        return (relPath, nil)
                    } catch {
                        return (relPath, error.localizedDescription)
                    }
                }
            }

            // Collect remaining results
            for await result in group {
                handleTransferResult(id: result.0, error: result.1)
            }
        }
    }

    private func handleTransferResult(id: String, error: String?) {
        if let idx = currentTransfers.firstIndex(where: { $0.id == id }) {
            if let error {
                currentTransfers[idx].error = error
                currentTransfers[idx].status = .complete
                logger.error("Transfer failed: \(id) - \(error)")
            } else {
                // Ensure final bytes are accounted for
                let remaining = currentTransfers[idx].totalBytes - currentTransfers[idx].bytesTransferred
                if remaining > 0 {
                    totalBytesTransferred += remaining
                    currentTransfers[idx].bytesTransferred = currentTransfers[idx].totalBytes
                }
                currentTransfers[idx].status = .complete
                logger.info("Transferred: \(id)")
            }
        }
        pendingCount -= 1
    }
}
