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
