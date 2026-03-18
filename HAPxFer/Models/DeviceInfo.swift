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

struct DeviceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let host: String
    let port: UInt16

    /// Known SMB share names on the HAP-Z1ES
    static let internalShare = "HAP_Internal"
    static let externalShare = "HAP_External"

    init(name: String, host: String, port: UInt16 = 445) {
        self.id = "\(host):\(port)"
        self.name = name
        self.host = host
        self.port = port
    }
}
