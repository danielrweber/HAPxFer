import Foundation
import OSLog

private let logger = Logger(subsystem: "com.hapxfer", category: "LibSMBClient")

/// Auth callback for libsmbclient — provides empty (guest) credentials.
/// Uses the deprecated simple API callback signature which is required
/// by smbc_init() — the only API that works reliably with SMB1 devices.
private func guestAuthCallback(
    _ server: UnsafePointer<CChar>?,
    _ share: UnsafePointer<CChar>?,
    _ workgroup: UnsafeMutablePointer<CChar>?,
    _ wgLen: Int32,
    _ username: UnsafeMutablePointer<CChar>?,
    _ unLen: Int32,
    _ password: UnsafeMutablePointer<CChar>?,
    _ pwLen: Int32
) {
    // Set empty strings for guest/anonymous access
    workgroup?[0] = 0
    username?[0] = 0
    password?[0] = 0
}

/// libsmbclient-backed implementation of SMBServiceProtocol.
/// Connects to the HAP-Z1ES using guest (anonymous) authentication over SMB1 (NT1).
///
/// Uses smbc_init() (the "simple" API) rather than the context-based API because
/// the context API has protocol negotiation issues with SMB1-only devices.
///
/// All libsmbclient C calls are serialized on a dedicated dispatch queue
/// since the library is not thread-safe.
final class LibSMBClientService: SMBServiceProtocol, @unchecked Sendable {
    private var isInitialized = false
    private var connectedHost: String?
    private var connectedShare: String?

    /// Serial queue for all libsmbclient calls (not thread-safe)
    private let smbQueue = DispatchQueue(label: "com.hapxfer.libsmbclient", qos: .userInitiated)

    /// Upload chunk size (64 KB)
    private let chunkSize = 65536

    /// Path to the smb.conf that forces SMB1.
    /// Prefers the bundled resource; falls back to writing a temp file.
    private static let smbConfPath: String = {
        // Try bundled resource first
        if let bundledPath = Bundle.main.path(forResource: "hapxfer_smb", ofType: "conf") {
            return bundledPath
        }

        // Fallback: write to temp directory
        let confPath = NSTemporaryDirectory() + "hapxfer_smb.conf"
        let confContent = """
        [global]
           client min protocol = CORE
           client max protocol = NT1
           client use spnego = no
           client NTLMv2 auth = no
           client lanman auth = yes
           client plaintext auth = yes
           client signing = disabled
           client ipc signing = disabled
           client ipc min protocol = CORE
           client ipc max protocol = NT1
           name resolve order = host bcast
        """
        try? confContent.write(toFile: confPath, atomically: true, encoding: .utf8)
        return confPath
    }()

    // MARK: - Helper

    /// Build an SMB URL for the connected share
    private func smbURL(_ path: String = "") -> String? {
        guard let host = connectedHost, let share = connectedShare else { return nil }
        if path.isEmpty {
            return "smb://\(host)/\(share)"
        }
        return "smb://\(host)/\(share)/\(path)"
    }

    // MARK: - SMBServiceProtocol

    func connect(host: String, port: UInt16 = 445, share: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            smbQueue.async { [self] in
                // Set config file to force SMB1 protocol
                setenv("SMB_CONF_PATH", Self.smbConfPath, 1)

                // Initialize libsmbclient once with the simple API.
                // Note: smbc_init is deprecated by Samba but is the only API
                // that works reliably with SMB1-only devices like the HAP-Z1ES.
                if !self.isInitialized {
                    let result = smbc_init(guestAuthCallback, 0)
                    if result != 0 {
                        let errMsg = String(cString: strerror(errno))
                        continuation.resume(throwing: SMBError.connectionFailed("Failed to initialize SMB: \(errMsg)"))
                        return
                    }
                    self.isInitialized = true
                }

                // Test the connection by opening the share root
                let shareURL = "smb://\(host)/\(share)"
                let dirHandle = smbc_opendir(shareURL)
                if dirHandle < 0 {
                    let errNo = errno
                    let errMsg = String(cString: strerror(errNo))
                    continuation.resume(throwing: SMBError.connectionFailed("Cannot open share \(share) on \(host): \(errMsg)"))
                    return
                }
                smbc_closedir(dirHandle)

                self.connectedHost = host
                self.connectedShare = share

                logger.info("Connected to \(host)/\(share) via SMB1")
                continuation.resume()
            }
        }
    }

    func disconnect() async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            smbQueue.async { [self] in
                self.connectedHost = nil
                self.connectedShare = nil
                // Note: smbc_init() creates a global context that persists.
                // We don't free it here to allow reconnection without re-init.
                logger.info("Disconnected")
                continuation.resume()
            }
        }
    }

    func listDirectory(at path: String) async throws -> [RemoteFileInfo] {
        guard let dirURL = smbURL(path) else {
            throw SMBError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            smbQueue.async { [self] in
                logger.info("listDirectory: opening \(dirURL)")
                let dirHandle = smbc_opendir(dirURL)
                if dirHandle < 0 {
                    let errNo = errno
                    let errMsg = String(cString: strerror(errNo))
                    logger.error("listDirectory: smbc_opendir failed: \(errMsg)")
                    continuation.resume(throwing: SMBError.connectionFailed("Cannot list directory '\(path)': \(errMsg)"))
                    return
                }

                var results: [RemoteFileInfo] = []

                // Use smbc_readdir to get directory entries, then stat each for details.
                // smbc_readdirplus has issues with some SMB1 servers.
                while let direntPtr = smbc_readdir(UInt32(dirHandle)) {
                    let dirent = direntPtr.pointee

                    // Get the name from the flexible array member using pointer arithmetic
                    let namePtr = UnsafeRawPointer(direntPtr)
                        .advanced(by: MemoryLayout.offset(of: \smbc_dirent.name)!)
                        .assumingMemoryBound(to: CChar.self)
                    let name = String(cString: namePtr)

                    // Skip . and .. entries
                    guard name != "." && name != ".." else { continue }

                    let fullPath = path.isEmpty ? name : "\(path)/\(name)"
                    let isDir = dirent.smbc_type == UInt32(SMBC_DIR)

                    // Stat the entry for size and modification date
                    var size: Int64 = 0
                    var modDate: Date? = nil
                    if let statURL = self.smbURL(fullPath) {
                        var st = stat()
                        if smbc_stat(statURL, &st) == 0 {
                            size = Int64(st.st_size)
                            modDate = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                        }
                    }

                    results.append(RemoteFileInfo(
                        name: name,
                        path: fullPath,
                        isDirectory: isDir,
                        size: size,
                        modificationDate: modDate
                    ))
                }

                smbc_closedir(dirHandle)
                logger.info("listDirectory: found \(results.count) entries")
                continuation.resume(returning: results)
            }
        }
    }

    func fileExists(at path: String) async throws -> Bool {
        guard let fileURL = smbURL(path) else {
            throw SMBError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            smbQueue.async {
                var st = stat()
                let result = smbc_stat(fileURL, &st)
                continuation.resume(returning: result == 0)
            }
        }
    }

    func createDirectory(at path: String) async throws {
        guard connectedHost != nil else {
            throw SMBError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            smbQueue.async { [self] in
                // Create directories recursively
                let components = path.split(separator: "/").map(String.init)
                var currentPath = ""

                for component in components {
                    currentPath = currentPath.isEmpty ? component : "\(currentPath)/\(component)"
                    guard let dirURL = self.smbURL(currentPath) else {
                        continuation.resume(throwing: SMBError.notConnected)
                        return
                    }

                    // Check if it already exists
                    var st = stat()
                    if smbc_stat(dirURL, &st) == 0 {
                        continue // Already exists
                    }

                    // Create it
                    let mkdirResult = smbc_mkdir(dirURL, 0o755)
                    if mkdirResult < 0 {
                        let errNo = errno
                        // EEXIST is OK (race condition)
                        if errNo != EEXIST {
                            let errMsg = String(cString: strerror(errNo))
                            continuation.resume(throwing: SMBError.directoryCreationFailed("\(currentPath): \(errMsg)"))
                            return
                        }
                    }
                }

                continuation.resume()
            }
        }
    }

    func upload(localURL: URL, remotePath: String, progress: TransferProgress?) async throws {
        guard connectedHost != nil else {
            throw SMBError.notConnected
        }

        // Read file size for progress
        let fileSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
            fileSize = (attrs[.size] as? Int64) ?? 0
        } catch {
            throw SMBError.transferFailed("Cannot read local file: \(error.localizedDescription)")
        }

        // Ensure parent directory exists
        let parentDir = (remotePath as NSString).deletingLastPathComponent
        if !parentDir.isEmpty {
            try await createDirectory(at: parentDir)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            smbQueue.async { [self] in
                guard let remoteURL = self.smbURL(remotePath) else {
                    continuation.resume(throwing: SMBError.notConnected)
                    return
                }

                // Open local file
                guard let localFile = fopen(localURL.path, "rb") else {
                    let errMsg = String(cString: strerror(errno))
                    continuation.resume(throwing: SMBError.transferFailed("Cannot open local file: \(errMsg)"))
                    return
                }
                defer { fclose(localFile) }

                // Open remote file for writing (create/truncate)
                let remoteHandle = smbc_open(remoteURL, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
                if remoteHandle < 0 {
                    let errNo = errno
                    let errMsg = String(cString: strerror(errNo))
                    continuation.resume(throwing: SMBError.transferFailed("Cannot create remote file \(remotePath): \(errMsg)"))
                    return
                }

                // Transfer in chunks
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.chunkSize)
                defer {
                    buffer.deallocate()
                    smbc_close(remoteHandle)
                }

                var totalWritten: Int64 = 0

                while true {
                    let bytesRead = fread(buffer, 1, self.chunkSize, localFile)
                    if bytesRead == 0 {
                        if ferror(localFile) != 0 {
                            continuation.resume(throwing: SMBError.transferFailed("Error reading local file"))
                            return
                        }
                        break // EOF
                    }

                    var offset = 0
                    while offset < bytesRead {
                        let written = smbc_write(remoteHandle, buffer.advanced(by: offset), bytesRead - offset)
                        if written < 0 {
                            let errNo = errno
                            let errMsg = String(cString: strerror(errNo))
                            continuation.resume(throwing: SMBError.transferFailed("Write error at \(totalWritten) bytes: \(errMsg)"))
                            return
                        }
                        offset += written
                        totalWritten += Int64(written)
                    }

                    // Report progress (caller handles threading)
                    if let progress {
                        progress(totalWritten, fileSize)
                    }
                }

                logger.info("Uploaded \(totalWritten) bytes to \(remotePath)")
                continuation.resume()
            }
        }
    }

    func deleteFile(at path: String) async throws {
        guard connectedHost != nil else {
            throw SMBError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            smbQueue.async { [self] in
                guard let fileURL = self.smbURL(path) else {
                    continuation.resume(throwing: SMBError.notConnected)
                    return
                }

                let result = smbc_unlink(fileURL)
                if result < 0 {
                    let errNo = errno
                    let errMsg = String(cString: strerror(errNo))
                    continuation.resume(throwing: SMBError.deletionFailed("\(path): \(errMsg)"))
                    return
                }

                logger.info("Deleted file: \(path)")
                continuation.resume()
            }
        }
    }

    func deleteDirectory(at path: String) async throws {
        guard connectedHost != nil else {
            throw SMBError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            smbQueue.async { [self] in
                guard let dirURL = self.smbURL(path) else {
                    continuation.resume(throwing: SMBError.notConnected)
                    return
                }

                let result = smbc_rmdir(dirURL)
                if result < 0 {
                    let errNo = errno
                    // ENOTEMPTY is expected if directory still has files
                    if errNo == ENOTEMPTY || errNo == EEXIST {
                        // Not empty — that's OK, skip silently
                        continuation.resume()
                        return
                    }
                    let errMsg = String(cString: strerror(errNo))
                    continuation.resume(throwing: SMBError.deletionFailed("\(path): \(errMsg)"))
                    return
                }

                logger.info("Deleted directory: \(path)")
                continuation.resume()
            }
        }
    }

    func diskSpace() async throws -> DiskSpaceInfo? {
        guard let shareURL = smbURL() else {
            throw SMBError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            smbQueue.async {
                var st = statvfs()
                let result = shareURL.withCString { cStr in
                    smbc_statvfs(UnsafeMutablePointer(mutating: cStr), &st)
                }
                if result == 0 && st.f_bsize > 0 {
                    let total = UInt64(st.f_blocks) * UInt64(st.f_bsize)
                    let free = UInt64(st.f_bavail) * UInt64(st.f_bsize)
                    let info = DiskSpaceInfo(totalBytes: total, freeBytes: free)
                    logger.info("Disk space: \(info.usedFormatted) used / \(info.totalFormatted) total")
                    continuation.resume(returning: info)
                } else {
                    logger.warning("smbc_statvfs failed or returned zero block size")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - DOS attribute constant

private let SMBC_DOS_MODE_DIRECTORY: UInt16 = 0x10
