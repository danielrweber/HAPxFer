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
