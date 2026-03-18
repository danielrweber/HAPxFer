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

import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MonitoredFolder.path) private var folders: [MonitoredFolder]

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
        .onAppear {
            // Restore folder monitoring and periodic sync on app launch
            appState.startMonitoring(folders: folders)
            if appState.periodicSyncMinutes > 0 {
                appState.startPeriodicSync()
            }
        }
        .onChange(of: folders.map(\.isEnabled)) { _, _ in
            // Restart monitoring when folders are added/removed/toggled
            appState.startMonitoring(folders: folders)
        }
    }
}
