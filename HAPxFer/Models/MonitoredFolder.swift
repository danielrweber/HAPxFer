import Foundation
import SwiftData

@Model
final class MonitoredFolder {
    var path: String
    var bookmarkData: Data?
    var isEnabled: Bool = true
    var lastSyncDate: Date?
    /// Destination path on the remote share (defaults to folder name)
    var remotePath: String

    @Relationship(deleteRule: .cascade, inverse: \SyncRecord.folder)
    var syncRecords: [SyncRecord] = []

    init(path: String, bookmarkData: Data? = nil, remotePath: String? = nil) {
        self.path = path
        self.bookmarkData = bookmarkData
        self.remotePath = remotePath ?? (path as NSString).lastPathComponent
    }

    var displayName: String {
        (path as NSString).lastPathComponent
    }

    var url: URL? {
        URL(fileURLWithPath: path)
    }
}
