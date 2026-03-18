import Foundation
import SwiftData

@Model
final class SyncLogEntry {
    var timestamp: Date
    var actionRaw: String
    var relativePath: String
    var fileSize: Int64
    var folderName: String
    var success: Bool
    var errorMessage: String?

    var action: Action {
        get { Action(rawValue: actionRaw) ?? .uploaded }
        set { actionRaw = newValue.rawValue }
    }

    var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    init(action: Action, relativePath: String, fileSize: Int64, folderName: String, success: Bool = true, errorMessage: String? = nil) {
        self.timestamp = Date()
        self.actionRaw = action.rawValue
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.folderName = folderName
        self.success = success
        self.errorMessage = errorMessage
    }

    enum Action: String, Codable, Sendable {
        case uploaded
        case deleted
    }
}
