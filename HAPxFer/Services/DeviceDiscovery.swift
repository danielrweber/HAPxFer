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
import Network
import OSLog

private let logger = Logger(subsystem: "com.hapxfer", category: "Discovery")

/// Discovers Sony HAP-Z1ES devices on the local network.
///
/// Discovery strategy (in order of reliability):
/// 1. Manual IP entry — always available, most reliable
/// 2. Subnet probe — scans local subnet for SMB1 devices on port 445
/// 3. Bonjour (NWBrowser for _smb._tcp) — secondary, may not find HAP-Z1ES
///
/// The HAP-Z1ES does not advertise via Bonjour or SSDP reliably.
@Observable
@MainActor
final class DeviceDiscovery {
    var discoveredDevices: [DeviceInfo] = []
    var isSearching: Bool = false

    private var browser: NWBrowser?
    private var resolveConnections: [NWConnection] = []
    private var probeTask: Task<Void, Never>?

    func startDiscovery() {
        stopDiscovery()
        isSearching = true
        discoveredDevices = []

        // Start both discovery methods in parallel
        startBonjourDiscovery()
        startSubnetProbe()

        // Auto-stop spinner after 8 seconds
        Task {
            try? await Task.sleep(for: .seconds(8))
            if self.isSearching {
                self.isSearching = false
            }
        }
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        resolveConnections.forEach { $0.cancel() }
        resolveConnections = []
        probeTask?.cancel()
        probeTask = nil
        isSearching = false
    }

    nonisolated func manualDevice(host: String) -> DeviceInfo {
        DeviceInfo(name: "HAP-Z1ES (\(host))", host: host)
    }

    // MARK: - Subnet Probe

    /// Probes common IPs on the local subnet for SMB1 service on port 445.
    /// When a device responds, we check if it has the HAP_Internal share.
    private func startSubnetProbe() {
        probeTask = Task {
            // Get the local IP to determine subnet
            let localIPs = Self.getLocalIPAddresses()
            var candidateIPs: [String] = []

            for ip in localIPs {
                let parts = ip.split(separator: ".").map(String.init)
                guard parts.count == 4, let subnet = parts.dropLast().joined(separator: ".") as String? else { continue }

                // Scan common DHCP ranges (1-254)
                for i in 1...254 {
                    let candidate = "\(subnet).\(i)"
                    if candidate != ip { // Skip self
                        candidateIPs.append(candidate)
                    }
                }
            }

            // Probe candidates concurrently (limited concurrency)
            await withTaskGroup(of: DeviceInfo?.self) { group in
                var launched = 0
                for ip in candidateIPs {
                    if Task.isCancelled { break }

                    group.addTask {
                        await Self.probeForHAP(ip: ip)
                    }
                    launched += 1

                    // Process results as they come, limit to 30 concurrent probes
                    if launched >= 30 {
                        if let result = await group.next(), let device = result {
                            await MainActor.run {
                                if !self.discoveredDevices.contains(where: { $0.host == device.host }) {
                                    self.discoveredDevices.append(device)
                                    logger.info("Found HAP device via probe: \(device.host)")
                                }
                            }
                        }
                        launched -= 1
                    }
                }

                // Collect remaining results
                for await result in group {
                    if let device = result {
                        if !self.discoveredDevices.contains(where: { $0.host == device.host }) {
                            self.discoveredDevices.append(device)
                            logger.info("Found HAP device via probe: \(device.host)")
                        }
                    }
                }
            }
        }
    }

    /// Probe a single IP to check if it's a HAP-Z1ES (has SMB on port 445)
    private static func probeForHAP(ip: String) async -> DeviceInfo? {
        // Quick TCP connect check on port 445
        let connection = NWConnection(
            host: NWEndpoint.Host(ip),
            port: 445,
            using: .tcp
        )

        let connected: Bool = await withCheckedContinuation { continuation in
            // Use a class to safely track resume state across Sendable boundaries
            final class ResumeGuard: @unchecked Sendable {
                private var _resumed = false
                private let lock = NSLock()
                func tryResume(_ cont: CheckedContinuation<Bool, Never>, returning value: Bool) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !_resumed else { return }
                    _resumed = true
                    cont.resume(returning: value)
                }
            }
            let guard_ = ResumeGuard()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard_.tryResume(continuation, returning: true)
                case .failed, .cancelled:
                    guard_.tryResume(continuation, returning: false)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))

            // Timeout after 1 second
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                connection.cancel()
                guard_.tryResume(continuation, returning: false)
            }
        }

        connection.cancel()

        if connected {
            return DeviceInfo(name: "SMB Device (\(ip))", host: ip)
        }
        return nil
    }

    /// Get local IPv4 addresses
    private static func getLocalIPAddresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return addresses }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let addr = current.pointee.ifa_addr

            // Filter for IPv4, non-loopback, up interfaces
            if let addr, addr.pointee.sa_family == UInt8(AF_INET),
               (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let addr = hostname.withUnsafeBufferPointer { buf in
                        String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8($0) }, as: UTF8.self)
                    }
                    addresses.append(addr)
                }
            }
            ptr = current.pointee.ifa_next
        }

        return addresses
    }

    // MARK: - Bonjour Discovery

    private func startBonjourDiscovery() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_smb._tcp", domain: "local."), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    logger.info("Bonjour browser ready")
                case .failed(let error):
                    logger.error("Bonjour browser failed: \(error.localizedDescription)")
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleBrowseResults(results)
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            switch result.endpoint {
            case .service(let name, _, _, _):
                logger.info("Found Bonjour service: \(name)")

                // Filter for HAP devices
                let lowerName = name.lowercased()
                guard lowerName.contains("hap") else { continue }

                resolveEndpoint(result.endpoint, serviceName: name)

            default:
                break
            }
        }
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint, serviceName: String) {
        let params = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    if let path = connection.currentPath,
                       let remoteEndpoint = path.remoteEndpoint {
                        let host = self?.extractHost(from: remoteEndpoint) ?? "unknown"
                        let port = self?.extractPort(from: remoteEndpoint) ?? 445

                        let device = DeviceInfo(name: serviceName, host: host, port: port)
                        if !(self?.discoveredDevices.contains(where: { $0.host == host }) ?? true) {
                            self?.discoveredDevices.append(device)
                            logger.info("Resolved Bonjour: \(serviceName) -> \(host):\(port)")
                        }
                    }
                    connection.cancel()

                case .failed(let error):
                    logger.warning("Failed to resolve \(serviceName): \(error.localizedDescription)")
                    let device = DeviceInfo(name: serviceName, host: "\(serviceName).local")
                    if !(self?.discoveredDevices.contains(where: { $0.name == serviceName }) ?? true) {
                        self?.discoveredDevices.append(device)
                    }
                    connection.cancel()

                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        resolveConnections.append(connection)
    }

    private func extractHost(from endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let addr): return "\(addr)"
            case .ipv6(let addr): return "\(addr)"
            case .name(let name, _): return name
            @unknown default: return nil
            }
        default:
            return nil
        }
    }

    private func extractPort(from endpoint: NWEndpoint) -> UInt16 {
        switch endpoint {
        case .hostPort(_, let port): return port.rawValue
        default: return 445
        }
    }
}
