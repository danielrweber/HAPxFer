import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.hapxfer", category: "AppState")

/// Central application state wiring discovery, SMB connection, sync, and folder monitoring.
@Observable
@MainActor
final class AppState {
    var deviceInfo: DeviceInfo?
    var connectionStatus: ConnectionStatus = .disconnected
    var syncEngine: SyncEngine?
    var shareName: String = DeviceInfo.internalShare
    var autoSyncEnabled: Bool = false
    var syncDeletions: Bool = true

    /// Persisted MAC address for Wake-on-LAN (resolved on first successful connection)
    @ObservationIgnored
    var deviceMAC: String? {
        get { UserDefaults.standard.string(forKey: "deviceMAC") }
        set { UserDefaults.standard.set(newValue, forKey: "deviceMAC") }
    }

    /// Persisted last-used IP address
    @ObservationIgnored
    var lastDeviceIP: String? {
        get { UserDefaults.standard.string(forKey: "lastDeviceIP") }
        set { UserDefaults.standard.set(newValue, forKey: "lastDeviceIP") }
    }

    private let smbService = LibSMBClientService()
    private var folderMonitor: FolderMonitor?
    private var debounceTask: Task<Void, Never>?

    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case waking
        case connected
        case error(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    /// Wake the device via WOL, then connect.
    func wakeAndConnect(to device: DeviceInfo, share: String? = nil, modelContainer: ModelContainer) async {
        guard let mac = deviceMAC else {
            // No MAC stored — just try a regular connect
            await connect(to: device, share: share, modelContainer: modelContainer)
            return
        }

        connectionStatus = .waking
        deviceInfo = device

        do {
            try WakeOnLAN.wake(macAddress: mac)
            logger.info("Sent WOL packet to \(mac), waiting for device...")

            let reachable = await WakeOnLAN.waitForDevice(ip: device.host, port: device.port, timeout: 45)
            if reachable {
                await connect(to: device, share: share, modelContainer: modelContainer)
            } else {
                connectionStatus = .error("Device did not wake up within 45 seconds")
                logger.error("WOL timeout for \(device.host)")
            }
        } catch {
            connectionStatus = .error("Wake-on-LAN failed: \(error.localizedDescription)")
            logger.error("WOL error: \(error.localizedDescription)")
        }
    }

    func connect(to device: DeviceInfo, share: String? = nil, modelContainer: ModelContainer) async {
        let targetShare = share ?? shareName
        connectionStatus = .connecting
        deviceInfo = device

        do {
            try await smbService.connect(host: device.host, port: device.port, share: targetShare)
            connectionStatus = .connected
            syncEngine = SyncEngine(smbService: smbService, modelContainer: modelContainer)

            // Store the IP and resolve/store MAC for future WOL
            lastDeviceIP = device.host
            if deviceMAC == nil {
                if let mac = WakeOnLAN.resolveMAC(for: device.host) {
                    deviceMAC = mac
                    logger.info("Stored MAC \(mac) for future Wake-on-LAN")
                }
            }

            logger.info("Connected to \(device.name) at \(device.host)/\(targetShare)")
        } catch {
            connectionStatus = .error(error.localizedDescription)
            deviceInfo = nil
            logger.error("Connection failed: \(error.localizedDescription)")
        }
    }

    /// Fetch disk space info from the connected share.
    func fetchDiskSpace() async -> DiskSpaceInfo? {
        try? await smbService.diskSpace()
    }

    /// Recursively count tracks and albums on the device.
    func fetchContentStats() async -> (tracks: Int, albums: Int) {
        do {
            return await countContent(at: "")
        } catch {
            logger.error("Failed to count content: \(error.localizedDescription)")
            return (0, 0)
        }
    }

    /// Recursively walk directories counting audio files (tracks) and directories containing audio (albums).
    private func countContent(at path: String) async -> (tracks: Int, albums: Int) {
        guard let items = try? await smbService.listDirectory(at: path) else {
            return (0, 0)
        }

        var tracks = 0
        var albums = 0
        var hasAudioFiles = false

        for item in items {
            if item.isDirectory {
                let sub = await countContent(at: item.path)
                tracks += sub.tracks
                albums += sub.albums
            } else if FileFilters.isSupportedName(item.name) {
                tracks += 1
                hasAudioFiles = true
            }
        }

        if hasAudioFiles {
            albums += 1
        }

        return (tracks, albums)
    }

    func disconnect() async {
        stopMonitoring()
        try? await smbService.disconnect()
        connectionStatus = .disconnected
        syncEngine = nil
        deviceInfo = nil
        logger.info("Disconnected")
    }

    /// List a remote directory — propagates errors to the caller.
    func listRemoteDirectory(at path: String) async throws -> [RemoteFileInfo] {
        try await smbService.listDirectory(at: path)
    }

    /// Delete a remote file from the connected share.
    func deleteRemoteFile(at path: String) async throws {
        try await smbService.deleteFile(at: path)
    }

    /// Delete a remote directory from the connected share.
    func deleteRemoteDirectory(at path: String) async throws {
        try await smbService.deleteDirectory(at: path)
    }

    // MARK: - Folder Monitoring

    func startMonitoring(folders: [MonitoredFolder]) {
        stopMonitoring()
        let paths = folders.filter(\.isEnabled).map(\.path)
        guard !paths.isEmpty, autoSyncEnabled else { return }

        folderMonitor = FolderMonitor(paths: paths, latency: 2.0) { [weak self] changedPaths in
            Task { @MainActor [weak self] in
                self?.handleFileChanges(changedPaths)
            }
        }
        folderMonitor?.start()
        logger.info("Started monitoring \(paths.count) folder(s)")
    }

    func stopMonitoring() {
        folderMonitor?.stop()
        folderMonitor = nil
    }

    private func handleFileChanges(_ changedPaths: Set<String>) {
        // Debounce: wait 5 seconds after last change before syncing
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await syncEngine?.syncAll(syncDeletions: syncDeletions)
        }
    }
}
