import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
        case folders = "Monitored Folders"
        case transfers = "Transfers"
        case log = "Activity Log"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .folders: return "folder.badge.plus"
            case .transfers: return "arrow.up.circle"
            case .log: return "clock.arrow.circlepath"
            }
        }
    }

    @State private var selectedItem: SidebarItem? = .folders

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                DeviceStatusView()
                    .padding()

                Divider()

                List(selection: $selectedItem) {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            switch selectedItem {
            case .folders:
                FolderListView()
            case .transfers:
                SyncProgressView()
            case .log:
                SyncLogView()
            case .none:
                ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 700, minHeight: 450)
    }
}
