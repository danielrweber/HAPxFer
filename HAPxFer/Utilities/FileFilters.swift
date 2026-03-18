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

enum FileFilters {
    /// Audio file extensions supported by the Sony HAP-Z1ES
    static let supportedExtensions: Set<String> = [
        "dsf", "dff",           // DSD formats
        "wav", "aiff", "aif",   // Uncompressed PCM
        "flac",                  // Lossless compressed
        "alac", "m4a",           // Apple Lossless / AAC
        "mp3",                   // Lossy
        "wma",                   // Windows Media
        "oma", "aa3"             // ATRAC
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func isSupported(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// Check a filename (not full path) for supported audio extension
    static func isSupportedName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }
}
