//
//  AlertHistoryView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopUI

@MainActor
final class AlertHistoryViewModel: ObservableObject {
    @Published private(set) var entries: [AlertHistoryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    @Published private(set) var canLoadMore = true

    private let alertStore: AlertStore
    private let pageSize: Int
    private var seenIDs = Set<String>()

    init(alertStore: AlertStore, pageSize: Int = 50) {
        self.alertStore = alertStore
        self.pageSize = pageSize
    }

    func loadInitialIfNeeded() async {
        guard entries.isEmpty, !isLoading else { return }
        await load(before: .distantFuture, reset: true)
    }

    func loadMore() async {
        guard canLoadMore, !isLoading, let oldest = entries.last else { return }
        await load(before: oldest.issuedDate, reset: false)
    }

    private func load(before: Date, reset: Bool) async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let page = try await alertStore.lookupRecent(before: before, limit: pageSize)
            if reset {
                entries.removeAll()
                seenIDs.removeAll()
            }
            // De-dupe across pages: alerts sharing an issuedDate can straddle a page boundary.
            entries.append(contentsOf: page.filter { seenIDs.insert($0.id).inserted })
            canLoadMore = page.count == pageSize
        } catch {
            loadFailed = true
            canLoadMore = false
        }
    }
}

struct AlertHistoryView: View {
    @StateObject private var viewModel: AlertHistoryViewModel

    init(alertStore: AlertStore) {
        _viewModel = StateObject(wrappedValue: AlertHistoryViewModel(alertStore: alertStore))
    }

    private var groupedByDay: [(day: Date, entries: [AlertHistoryEntry])] {
        Dictionary(grouping: viewModel.entries) { Calendar.current.startOfDay(for: $0.issuedDate) }
            .map { (day: $0.key, entries: $0.value.sorted { $0.issuedDate > $1.issuedDate }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        List {
            if viewModel.entries.isEmpty {
                if viewModel.isLoading {
                    centeredRow { ProgressView() }
                } else if viewModel.loadFailed {
                    centeredRow {
                        Text("Unable to load alert history.", comment: "Alert history load failure message")
                            .foregroundColor(.secondary)
                    }
                } else {
                    centeredRow {
                        Text("No alerts recorded.", comment: "Alert history empty state message")
                            .foregroundColor(.secondary)
                    }
                }
            }

            ForEach(groupedByDay, id: \.day) { group in
                Section(header: Text(group.day.formatted(date: .complete, time: .omitted))) {
                    ForEach(group.entries) { entry in
                        NavigationLink(destination: AlertHistoryDetailView(entry: entry)) {
                            AlertHistoryRow(entry: entry)
                        }
                    }
                }
            }

            if viewModel.canLoadMore && !viewModel.entries.isEmpty {
                centeredRow { ProgressView() }
                    .onAppear {
                        Task { await viewModel.loadMore() }
                    }
            }
        }
        .navigationTitle(Text("Alert History", comment: "Title of the alert history screen"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadInitialIfNeeded()
        }
    }

    private func centeredRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer()
            content()
            Spacer()
        }
        .listRowBackground(Color.clear)
    }
}

struct AlertHistoryRow: View {
    let entry: AlertHistoryEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: entry.interruptionLevel.symbolName)
                .foregroundColor(entry.interruptionLevel.tintColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.status.label)
                    .font(.subheadline)
                    .foregroundColor(entry.status.tintColor)
            }

            Spacer()

            Text(entry.issuedDate.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct AlertHistoryDetailView: View {
    let entry: AlertHistoryEntry

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title)
                        .font(.headline)
                    if !entry.body.isEmpty {
                        Text(entry.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent(NSLocalizedString("Status", comment: "Alert history field label")) {
                    Text(entry.status.label).foregroundColor(entry.status.tintColor)
                }
                LabeledContent(NSLocalizedString("Priority", comment: "Alert history field label")) {
                    Text(entry.interruptionLevel.label)
                }
                LabeledContent(NSLocalizedString("Issued", comment: "Alert history field label")) {
                    Text(entry.issuedDate.formatted(date: .abbreviated, time: .shortened))
                }
                if let acknowledgedDate = entry.acknowledgedDate {
                    LabeledContent(NSLocalizedString("Acknowledged", comment: "Alert history field label")) {
                        Text(acknowledgedDate.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let retractedDate = entry.retractedDate {
                    LabeledContent(NSLocalizedString("Retracted", comment: "Alert history field label")) {
                        Text(retractedDate.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }

            Section(header: Text("Details", comment: "Alert history details section header")) {
                LabeledContent(NSLocalizedString("Source", comment: "Alert history field label")) {
                    Text(entry.managerIdentifier)
                }
                LabeledContent(NSLocalizedString("Identifier", comment: "Alert history field label")) {
                    Text(entry.identifier.alertIdentifier)
                }
                LabeledContent(NSLocalizedString("Trigger", comment: "Alert history field label")) {
                    Text(entry.trigger.label)
                }
            }
        }
        .navigationTitle(Text("Alert", comment: "Title of the alert history detail screen"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AlertHistoryEntry.Status {
    var label: String {
        switch self {
        case .active: return NSLocalizedString("Active", comment: "Alert history status: alert still active")
        case .acknowledged: return NSLocalizedString("Acknowledged", comment: "Alert history status: alert acknowledged")
        case .retracted: return NSLocalizedString("Retracted", comment: "Alert history status: alert retracted before acknowledgement")
        }
    }

    var tintColor: Color {
        switch self {
        case .active: return .critical
        case .acknowledged: return .secondary
        case .retracted: return .secondary
        }
    }
}

private extension LoopKit.Alert.InterruptionLevel {
    var label: String {
        switch self {
        case .active: return NSLocalizedString("Normal", comment: "Alert priority: active/normal")
        case .timeSensitive: return NSLocalizedString("Time Sensitive", comment: "Alert priority: time sensitive")
        case .critical: return NSLocalizedString("Critical", comment: "Alert priority: critical")
        }
    }

    var symbolName: String {
        switch self {
        case .active: return "bell.fill"
        case .timeSensitive: return "bell.badge.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .active: return .secondary
        case .timeSensitive: return .orange
        case .critical: return .critical
        }
    }
}

private extension LoopKit.Alert.Trigger {
    var label: String {
        switch self {
        case .immediate:
            return NSLocalizedString("Immediate", comment: "Alert trigger type: immediate")
        case .delayed(let interval):
            let formatted = Self.durationFormatter.string(from: interval) ?? ""
            return String(format: NSLocalizedString("Delayed (%1$@)", comment: "Alert trigger type: delayed by a duration (1: duration)"), formatted)
        case .repeating(let interval):
            let formatted = Self.durationFormatter.string(from: interval) ?? ""
            return String(format: NSLocalizedString("Repeating (%1$@)", comment: "Alert trigger type: repeating on an interval (1: interval)"), formatted)
        }
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        return formatter
    }()
}
