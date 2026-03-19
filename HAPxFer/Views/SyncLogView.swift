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
import UniformTypeIdentifiers

struct SyncLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SyncLogEntry.timestamp, order: .reverse) private var allEntries: [SyncLogEntry]

    @State private var filter: LogFilter = .all
    @State private var searchText: String = ""
    @State private var showExportPicker = false

    enum LogFilter: String, CaseIterable {
        case all = "All"
        case uploads = "Uploads"
        case deletions = "Deletions"
        case errors = "Errors"
    }

    private var filteredEntries: [SyncLogEntry] {
        var entries = allEntries

        switch filter {
        case .all: break
        case .uploads: entries = entries.filter { $0.action == .uploaded && $0.success }
        case .deletions: entries = entries.filter { $0.action == .deleted }
        case .errors: entries = entries.filter { !$0.success }
        }

        if !searchText.isEmpty {
            entries = entries.filter {
                $0.relativePath.localizedCaseInsensitiveContains(searchText) ||
                $0.folderName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return entries
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity Log")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()

                if !allEntries.isEmpty {
                    Button("Export Log...") {
                        showExportPicker = true
                    }

                    Button("Clear Log") {
                        clearLog()
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding()

            // Filter picker
            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(LogFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Search
            TextField("Search files...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            // Log entries
            if filteredEntries.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label(
                        allEntries.isEmpty ? "No Activity" : "No Matches",
                        systemImage: allEntries.isEmpty ? "clock" : "magnifyingglass"
                    )
                } description: {
                    Text(allEntries.isEmpty
                         ? "Sync activity will appear here."
                         : "No entries match the current filter.")
                }
                .frame(maxHeight: 200)
                Spacer()
            } else {
                List(filteredEntries) { entry in
                    LogEntryRow(entry: entry)
                }
            }

            // Summary bar
            if !allEntries.isEmpty {
                Divider()
                HStack {
                    let uploads = allEntries.filter { $0.action == .uploaded && $0.success }.count
                    let deletions = allEntries.filter { $0.action == .deleted && $0.success }.count
                    let errors = allEntries.filter { !$0.success }.count

                    Text("\(uploads) uploaded")
                        .foregroundStyle(.green)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(deletions) deleted")
                        .foregroundStyle(.orange)
                    if errors > 0 {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(errors) errors")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Text("\(filteredEntries.count) shown")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .fileExporter(
            isPresented: $showExportPicker,
            document: LogExportDocument(entries: filteredEntries),
            contentType: .commaSeparatedText,
            defaultFilename: "HAPxFer_SyncLog_\(Self.dateStamp).csv"
        ) { _ in }
    }

    private static var dateStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func clearLog() {
        for entry in allEntries {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }
}

/// Wraps the sync log as a CSV file for the fileExporter.
struct LogExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let csv: String

    init(entries: [SyncLogEntry]) {
        var lines = ["Timestamp,Action,Status,File,Folder,Size,Error"]
        let df = ISO8601DateFormatter()
        for e in entries {
            let status = e.success ? "OK" : "FAILED"
            let action = e.action == .uploaded ? "Upload" : "Delete"
            let error = (e.errorMessage ?? "").replacingOccurrences(of: ",", with: ";")
            let file = e.relativePath.replacingOccurrences(of: ",", with: ";")
            let folder = e.folderName.replacingOccurrences(of: ",", with: ";")
            lines.append("\(df.string(from: e.timestamp)),\(action),\(status),\(file),\(folder),\(e.fileSize),\(error)")
        }
        csv = lines.joined(separator: "\n")
    }

    init(configuration: ReadConfiguration) throws {
        csv = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: csv.data(using: .utf8) ?? Data())
    }
}

struct LogEntryRow: View {
    let entry: SyncLogEntry

    var body: some View {
        HStack(spacing: 8) {
            // Action icon
            Image(systemName: actionIcon)
                .foregroundStyle(actionColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let parentPath = Self.parentPath(from: entry.relativePath) {
                    Text(parentPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 4) {
                    Text(entry.folderName)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.timestamp, style: .relative)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2)

                if let error = entry.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private static func parentPath(from relativePath: String) -> String? {
        let components = relativePath.split(separator: "/")
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: " / ")
    }

    private var actionIcon: String {
        if !entry.success {
            return "exclamationmark.circle.fill"
        }
        switch entry.action {
        case .uploaded: return "arrow.up.circle.fill"
        case .deleted: return "trash.circle.fill"
        }
    }

    private var actionColor: Color {
        if !entry.success { return .red }
        switch entry.action {
        case .uploaded: return .green
        case .deleted: return .orange
        }
    }
}
