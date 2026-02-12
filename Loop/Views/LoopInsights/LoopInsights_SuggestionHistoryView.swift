//
//  LoopInsights_SuggestionHistoryView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Scrollable log of all past suggestions with status indicators.
/// Shows the complete history of LoopInsights recommendations.
struct LoopInsights_SuggestionHistoryView: View {

    @ObservedObject var store: LoopInsights_SuggestionStore
    @State private var selectedRecord: LoopInsightsSuggestionRecord?
    @State private var filterStatus: FilterOption = .all
    @Environment(\.dismiss) private var dismiss

    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case applied = "Applied"
        case dismissed = "Dismissed"
        case autoApplied = "Auto-Applied"

        var id: String { rawValue }
    }

    var body: some View {
        List {
            filterSection
            if filteredRecords.isEmpty {
                emptySection
            } else {
                recordsSection
            }
        }
        .navigationTitle(NSLocalizedString("Suggestion History", comment: "LoopInsights history title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Done", comment: "Done button")) {
                    dismiss()
                }
            }
        }
        .sheet(item: $selectedRecord) { record in
            NavigationView {
                LoopInsights_SuggestionDetailView(
                    record: record,
                    onApply: {},
                    onDismiss: {}
                )
            }
        }
    }

    // MARK: - Filter

    private var filterSection: some View {
        Section {
            Picker(NSLocalizedString("Filter", comment: "LoopInsights filter picker"), selection: $filterStatus) {
                ForEach(FilterOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }

    // MARK: - Records

    private var recordsSection: some View {
        Section(header: Text(String(format: NSLocalizedString("%d suggestions", comment: "LoopInsights suggestion count"), filteredRecords.count))) {
            ForEach(filteredRecords) { record in
                Button(action: { selectedRecord = record }) {
                    historyRow(record)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteRecords)
        }
    }

    private func historyRow(_ record: LoopInsightsSuggestionRecord) -> some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: record.status.systemImage)
                .foregroundColor(statusColor(record.status))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.suggestion.summaryDescription)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text(record.suggestion.settingType.abbreviation)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(3)

                    Text(record.suggestion.confidence.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(Self.dateFormatter.string(from: record.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty State

    private var emptySection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text(NSLocalizedString("No suggestions yet", comment: "LoopInsights empty history title"))
                    .font(.headline)
                Text(NSLocalizedString("Run an analysis from the LoopInsights Dashboard to generate your first suggestions.", comment: "LoopInsights empty history message"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Computed

    private var filteredRecords: [LoopInsightsSuggestionRecord] {
        let allRecords = store.allRecords
        switch filterStatus {
        case .all:
            return allRecords
        case .applied:
            return allRecords.filter { $0.status == .applied }
        case .dismissed:
            return allRecords.filter { $0.status == .dismissed }
        case .autoApplied:
            return allRecords.filter { $0.status == .autoApplied }
        }
    }

    private func statusColor(_ status: LoopInsightsSuggestionStatus) -> Color {
        switch status {
        case .pending: return .blue
        case .applied: return .green
        case .dismissed: return .gray
        case .autoApplied: return .orange
        }
    }

    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            let record = filteredRecords[index]
            store.deleteRecord(withID: record.id)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
