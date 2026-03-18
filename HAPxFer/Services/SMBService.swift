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

/// Information about a remote file or directory on the SMB share
struct RemoteFileInfo: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?
}

/// Progress callback: (bytesTransferred, totalBytes)
typealias TransferProgress = @Sendable (Int64, Int64) -> Void

/// Disk space information for the remote share
struct DiskSpaceInfo: Sendable {
    let totalBytes: UInt64
    let freeBytes: UInt64
    var usedBytes: UInt64 { totalBytes - freeBytes }

    var totalFormatted: String { ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file) }
    var freeFormatted: String { ByteCountFormatter.string(fromByteCount: Int64(freeBytes), countStyle: .file) }
    var usedFormatted: String { ByteCountFormatter.string(fromByteCount: Int64(usedBytes), countStyle: .file) }
    var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

/// Protocol abstracting SMB operations. Allows swapping SMBClient for AMSMB2 if needed.
protocol SMBServiceProtocol: Sendable {
    func connect(host: String, port: UInt16, share: String) async throws
    func disconnect() async throws
    func listDirectory(at path: String) async throws -> [RemoteFileInfo]
    func fileExists(at path: String) async throws -> Bool
    func createDirectory(at path: String) async throws
    func upload(localURL: URL, remotePath: String, progress: TransferProgress?) async throws
    func deleteFile(at path: String) async throws
    func deleteDirectory(at path: String) async throws
    func diskSpace() async throws -> DiskSpaceInfo?
}

enum SMBError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case transferFailed(String)
    case directoryCreationFailed(String)
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to the device."
        case .connectionFailed(let detail):
            return "Connection failed: \(detail)"
        case .transferFailed(let detail):
            return "Transfer failed: \(detail)"
        case .directoryCreationFailed(let detail):
            return "Failed to create directory: \(detail)"
        case .deletionFailed(let detail):
            return "Deletion failed: \(detail)"
        }
    }
}
