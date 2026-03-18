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

private let logger = Logger(subsystem: "com.hapxfer", category: "WakeOnLAN")

/// Sends Wake-on-LAN magic packets to wake a sleeping device on the local network.
enum WakeOnLAN {

    /// Send a WOL magic packet to the given MAC address via UDP broadcast.
    /// The magic packet is 6 bytes of 0xFF followed by the MAC address repeated 16 times.
    static func wake(macAddress: String) throws {
        let macBytes = try parseMACAddress(macAddress)

        // Build magic packet: 6x 0xFF + 16x MAC
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }

        // Send via UDP broadcast on port 9
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else {
            throw WOLError.socketCreationFailed(String(cString: strerror(errno)))
        }
        defer { close(sock) }

        // Enable broadcast
        var broadcastEnable: Int32 = 1
        let optResult = setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
        guard optResult >= 0 else {
            throw WOLError.socketOptionFailed(String(cString: strerror(errno)))
        }

        // Target: 255.255.255.255:9
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(9).bigEndian
        addr.sin_addr.s_addr = INADDR_BROADCAST

        let sent = packet.withUnsafeBufferPointer { buf in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(sock, buf.baseAddress, buf.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        guard sent == packet.count else {
            throw WOLError.sendFailed(String(cString: strerror(errno)))
        }

        logger.info("Sent WOL magic packet to \(macAddress)")
    }

    /// Resolve the MAC address for an IP from the system ARP cache.
    /// Returns nil if the IP is not in the ARP table.
    static func resolveMAC(for ip: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ip]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Failed to run arp: \(error.localizedDescription)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Parse ARP output: "? (192.168.1.66) at 70:26:5:d7:ce:f3 on en0 ..."
        // The MAC is the field after "at"
        let parts = output.split(separator: " ")
        if let atIndex = parts.firstIndex(of: "at"), atIndex + 1 < parts.count {
            let rawMAC = String(parts[atIndex + 1])
            // Normalize: pad single-digit hex octets (e.g., "5" → "05")
            if rawMAC.contains(":") && !rawMAC.contains("incomplete") {
                let normalized = rawMAC.split(separator: ":").map { octet in
                    octet.count == 1 ? "0\(octet)" : String(octet)
                }.joined(separator: ":")
                logger.info("Resolved MAC for \(ip): \(normalized)")
                return normalized
            }
        }

        logger.warning("Could not resolve MAC for \(ip)")
        return nil
    }

    /// Wait for a device to become reachable via TCP on port 445.
    /// Returns true if the device responds within the timeout.
    static func waitForDevice(ip: String, port: UInt16 = 445, timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await tcpProbe(ip: ip, port: port, timeout: 2) {
                logger.info("Device \(ip) is reachable on port \(port)")
                return true
            }
            try? await Task.sleep(for: .seconds(2))
        }

        logger.warning("Device \(ip) did not respond within \(Int(timeout))s")
        return false
    }

    // MARK: - Private

    private static func parseMACAddress(_ mac: String) throws -> [UInt8] {
        let components = mac.split(separator: ":").map(String.init)
        guard components.count == 6 else {
            throw WOLError.invalidMAC(mac)
        }

        var bytes: [UInt8] = []
        for component in components {
            guard let byte = UInt8(component, radix: 16) else {
                throw WOLError.invalidMAC(mac)
            }
            bytes.append(byte)
        }
        return bytes
    }

    private static func tcpProbe(ip: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else {
                continuation.resume(returning: false)
                return
            }

            // Set send/receive timeout
            var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
            setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            inet_pton(AF_INET, ip, &addr.sin_addr)

            let connectResult = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            close(sock)
            continuation.resume(returning: connectResult == 0)
        }
    }
}

enum WOLError: LocalizedError {
    case invalidMAC(String)
    case socketCreationFailed(String)
    case socketOptionFailed(String)
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMAC(let mac): return "Invalid MAC address: \(mac)"
        case .socketCreationFailed(let msg): return "Failed to create socket: \(msg)"
        case .socketOptionFailed(let msg): return "Failed to set socket option: \(msg)"
        case .sendFailed(let msg): return "Failed to send WOL packet: \(msg)"
        }
    }
}
