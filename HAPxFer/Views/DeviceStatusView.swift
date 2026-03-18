import SwiftUI
import SwiftData

struct DeviceStatusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var manualHost: String = UserDefaults.standard.string(forKey: "lastDeviceIP") ?? "192.168.1.66"
    @State private var showBrowser: Bool = false

    private var modelContainer: ModelContainer {
        modelContext.container
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.headline)
            }

            if let device = appState.deviceInfo {
                Text(device.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            switch appState.connectionStatus {
            case .disconnected, .error:
                VStack(spacing: 6) {
                    HStack {
                        TextField("Hostname or IP", text: $manualHost)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { connectManual() }

                        Button("Connect") { connectManual() }
                            .buttonStyle(.borderedProminent)
                    }

                    if appState.deviceMAC != nil {
                        Button {
                            wakeAndConnect()
                        } label: {
                            Label("Wake & Connect", systemImage: "wake")
                        }
                        .controlSize(.small)
                        .help("Send Wake-on-LAN packet to wake the device from standby, then connect")
                    }
                }

                if case .error(let msg) = appState.connectionStatus {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }

            case .connecting:
                ProgressView("Connecting...")
                    .controlSize(.small)

            case .waking:
                VStack(spacing: 4) {
                    ProgressView("Waking device...")
                        .controlSize(.small)
                    Text("Sending Wake-on-LAN packet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .connected:
                HStack {
                    Button("Disconnect") {
                        Task { await appState.disconnect() }
                    }

                    Button("Browse") {
                        showBrowser = true
                    }
                }
            }
        }
        .sheet(isPresented: $showBrowser) {
            RemoteBrowserView()
        }
    }

    private var statusColor: Color {
        switch appState.connectionStatus {
        case .connected: return .green
        case .connecting, .waking: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.connectionStatus {
        case .connected: return appState.deviceInfo?.name ?? "Connected"
        case .connecting: return "Connecting..."
        case .waking: return "Waking Device..."
        case .disconnected: return "Not Connected"
        case .error: return "Connection Error"
        }
    }

    private func connectManual() {
        let device = DeviceInfo(name: "HAP-Z1ES (\(manualHost))", host: manualHost)
        Task {
            await appState.connect(to: device, modelContainer: modelContainer)
        }
    }

    private func wakeAndConnect() {
        let device = DeviceInfo(name: "HAP-Z1ES (\(manualHost))", host: manualHost)
        Task {
            await appState.wakeAndConnect(to: device, modelContainer: modelContainer)
        }
    }
}
