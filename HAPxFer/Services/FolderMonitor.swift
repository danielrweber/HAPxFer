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
import CoreServices
import OSLog

private let logger = Logger(subsystem: "com.hapxfer", category: "FolderMonitor")

/// Monitors directories for file system changes using FSEvents.
/// Calls back with the set of changed paths when modifications occur.
final class FolderMonitor: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let latency: CFTimeInterval
    private let callback: @Sendable (Set<String>) -> Void
    private let queue: DispatchQueue

    init(paths: [String], latency: CFTimeInterval = 2.0, callback: @escaping @Sendable (Set<String>) -> Void) {
        self.paths = paths
        self.latency = latency
        self.callback = callback
        self.queue = DispatchQueue(label: "com.hapxfer.foldermonitor", qos: .utility)
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }

        let pathsToWatch = paths as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passRetained(CallbackBox(callback)).toOpaque()

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            logger.error("Failed to create FSEventStream")
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        logger.info("Started monitoring \(self.paths.count) folder(s)")
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        logger.info("Stopped monitoring folders")
    }
}

/// Box to pass the callback through the C function pointer context
private final class CallbackBox: @unchecked Sendable {
    let callback: @Sendable (Set<String>) -> Void
    init(_ callback: @escaping @Sendable (Set<String>) -> Void) {
        self.callback = callback
    }
}

/// FSEvents C callback function
private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var changedPaths = Set<String>()

    for i in 0..<numEvents {
        if let path = CFArrayGetValueAtIndex(paths, i) {
            let cfString = Unmanaged<CFString>.fromOpaque(path).takeUnretainedValue()
            changedPaths.insert(cfString as String)
        }
    }

    if !changedPaths.isEmpty {
        box.callback(changedPaths)
    }
}
