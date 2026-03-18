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
