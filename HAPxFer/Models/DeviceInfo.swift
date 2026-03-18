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
