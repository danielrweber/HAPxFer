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
import OSLog

private let logger = Logger(subsystem: "com.hapxfer", category: "Metadata")

/// Errors that can occur during metadata operations.
enum MetadataError: LocalizedError {
    case unsupportedFormat(String)
    case writeFailed(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported format for metadata writing: \(ext)"
        case .writeFailed(let detail):
            return "Failed to write metadata: \(detail)"
        case .copyFailed(let detail):
            return "Failed to create temp copy: \(detail)"
        }
    }
}

/// Handles audio metadata modification for the "Override Artist" feature.
/// Creates temporary copies of files, modifies metadata, and provides
/// the temp URL for upload. Callers are responsible for cleanup.
enum MetadataService {

    private static let tempSubdirectory = "HAPxFer-meta"

    // MARK: - Public API

    /// Extracts the artist name from a relative path.
    /// Given "Matthew and the Atlas/Other Rivers (2014)/01-Track.flac",
    /// returns "Matthew and the Atlas" (the first path component).
    /// Returns nil if the file is at the root (no subfolder structure).
    static func artistFromRelativePath(_ relativePath: String) -> String? {
        let components = relativePath.split(separator: "/").map(String.init)
        // Need at least 2 components: artist folder + filename
        guard components.count >= 2 else { return nil }
        return components[0]
    }

    /// Creates a temporary copy of the file at `sourceURL` with the Artist
    /// tag overwritten to `artist`. Returns the URL of the temp file.
    /// The caller MUST delete the temp file after use via `cleanupTempFile`.
    static func copyWithArtistOverride(sourceURL: URL, artist: String) throws -> URL {
        // Create unique temp directory
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(tempSubdirectory)
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            throw MetadataError.copyFailed("Cannot create temp directory: \(error.localizedDescription)")
        }

        let tempFileURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Copy source to temp
        do {
            try FileManager.default.copyItem(at: sourceURL, to: tempFileURL)
        } catch {
            // Clean up the empty temp dir
            try? FileManager.default.removeItem(at: tempDir)
            throw MetadataError.copyFailed("Cannot copy file: \(error.localizedDescription)")
        }

        // Modify the Artist tag in the temp copy
        let path = tempFileURL.path
        do {
            try setArtistTag(filePath: path, artist: artist)
            logger.info("Set Artist to '\(artist)' in temp copy: \(sourceURL.lastPathComponent)")
        } catch {
            // Graceful degradation: upload the unmodified copy
            logger.warning("Could not set Artist tag for \(sourceURL.lastPathComponent): \(error.localizedDescription). Uploading with original metadata.")
        }

        return tempFileURL
    }

    /// Deletes a temporary file (and its parent UUID directory), logging errors.
    static func cleanupTempFile(at url: URL) {
        // Remove the UUID directory (parent of the temp file)
        let parentDir = url.deletingLastPathComponent()
        do {
            try FileManager.default.removeItem(at: parentDir)
        } catch {
            logger.warning("Failed to clean up temp file at \(parentDir.path): \(error.localizedDescription)")
        }
    }

    /// Removes any leftover temp directories from previous sessions.
    static func cleanupStaleTempFiles() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(tempSubdirectory)
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
            logger.info("Cleaned up stale temp metadata directory")
        }
    }

    // MARK: - TagLib Integration

    /// Sets the Artist tag in the file at the given path using TagLib's C API.
    private static func setArtistTag(filePath: String, artist: String) throws {
        // Ensure TagLib uses UTF-8 strings
        taglib_set_strings_unicode(1)

        guard let file = taglib_file_new(filePath) else {
            throw MetadataError.unsupportedFormat(
                URL(fileURLWithPath: filePath).pathExtension
            )
        }
        defer { taglib_file_free(file) }

        guard taglib_file_is_valid(file) != 0 else {
            throw MetadataError.unsupportedFormat(
                URL(fileURLWithPath: filePath).pathExtension
            )
        }

        guard let tag = taglib_file_tag(file) else {
            throw MetadataError.writeFailed("Could not access tag")
        }

        taglib_tag_set_artist(tag, artist)

        let saved = taglib_file_save(file)
        taglib_tag_free_strings()

        guard saved != 0 else {
            throw MetadataError.writeFailed("taglib_file_save returned false")
        }
    }
}
