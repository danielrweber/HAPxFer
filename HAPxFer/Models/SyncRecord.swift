import Foundation
import SwiftData

@Model
final class SyncRecord {
    var relativePath: String
    var fileSize: Int64
    var localModDate: Date
    var syncDate: Date?
    var statusRaw: String = SyncStatus.pending.rawValue

    var folder: MonitoredFolder?

    var status: SyncStatus {
        get { SyncStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(relativePath: String, fileSize: Int64, localModDate: Date, status: SyncStatus = .pending) {
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.localModDate = localModDate
        self.statusRaw = status.rawValue
    }

    enum SyncStatus: String, Codable, Sendable {
        case pending
        case synced
        case failed
        case deleted
        /// File was manually removed from device via Browse — skip on future syncs
        case manuallyRemoved
    }
}
