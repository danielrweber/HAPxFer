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
final class MonitoredFolder {
    var path: String
    var bookmarkData: Data?
    var isEnabled: Bool = true
    var overrideArtistFromFolder: Bool = false
    var lastSyncDate: Date?
    /// Destination path on the remote share (defaults to folder name)
    var remotePath: String
    /// Which HAP storage to sync to: "HAP_Internal" or "HAP_External"
    var destinationShare: String = Destination.internal.rawValue

    @Relationship(deleteRule: .cascade, inverse: \SyncRecord.folder)
    var syncRecords: [SyncRecord] = []

    enum Destination: String, CaseIterable, Sendable {
        case `internal` = "HAP_Internal"
        case external = "HAP_External"

        var displayName: String {
            switch self {
            case .internal: return "Internal HDD"
            case .external: return "External USB"
            }
        }
    }

    var destination: Destination {
        get { Destination(rawValue: destinationShare) ?? .internal }
        set { destinationShare = newValue.rawValue }
    }

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
