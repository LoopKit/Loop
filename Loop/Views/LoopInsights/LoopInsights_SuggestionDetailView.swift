//
//  LoopInsights_SuggestionDetailView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Detailed view of a single suggestion showing reasoning, current vs proposed
/// values for each time block, and apply/dismiss actions.
struct LoopInsights_SuggestionDetailView: View {

    let record: LoopInsightsSuggestionRecord
    let onApply: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            headerSection
            reasoningSection
            timeBlocksSection
            if record.status == .pending {
                actionsSection
            } else {
                statusSection
            }
        }
        .navigationTitle(record.suggestion.settingType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Done", comment: "Done button")) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: record.suggestion.settingType.systemImage)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text(record.suggestion.settingType.displayName)
                            .font(.headline)
                        Text(record.suggestion.summaryDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    confidenceBadge
                }

                HStack {
                    Label(record.suggestion.analysisPeriod.displayName, systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Self.dateFormatter.string(from: record.suggestion.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Time Blocks

    private var timeBlocksSection: some View {
        Section(header: Text(NSLocalizedString("Proposed Changes", comment: "LoopInsights proposed changes header"))) {
            ForEach(record.suggestion.timeBlocks) { block in
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.timeRangeFormatted)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("Current", comment: "LoopInsights current value label"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f %@", block.currentValue, record.suggestion.settingType.unitDescription))
                                .font(.body)
                                .fontWeight(.medium)
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .foregroundColor(.accentColor)

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text(NSLocalizedString("Proposed", comment: "LoopInsights proposed value label"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f %@", block.proposedValue, record.suggestion.settingType.unitDescription))
                                .font(.body)
                                .fontWeight(.bold)
                                .foregroundColor(block.proposedValue > block.currentValue ? .orange : .blue)
                        }
                    }

                    HStack {
                        Spacer()
                        Text(String(format: "%+.1f%% change", block.changePercent))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Reasoning

    private var reasoningSection: some View {
        Section(header: Text(NSLocalizedString("AI Reasoning", comment: "LoopInsights reasoning header"))) {
            Text(record.suggestion.reasoning)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button(action: {
                onApply()
                dismiss()
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                    Text(NSLocalizedString("Apply Suggestion", comment: "LoopInsights apply suggestion button"))
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)

            Button(action: {
                onDismiss()
                dismiss()
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "xmark.circle")
                    Text(NSLocalizedString("Dismiss Suggestion", comment: "LoopInsights dismiss suggestion button"))
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Status (for resolved records)

    private var statusSection: some View {
        Section(header: Text(NSLocalizedString("Status", comment: "LoopInsights status header"))) {
            HStack {
                Image(systemName: record.status.systemImage)
                    .foregroundColor(statusColor)
                Text(record.status.displayName)
                    .fontWeight(.medium)
                Spacer()
                if let resolvedAt = record.resolvedAt {
                    Text(Self.dateFormatter.string(from: resolvedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let mode = record.applyMode {
                HStack {
                    Text(NSLocalizedString("Applied via", comment: "LoopInsights applied via label"))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(mode.displayName)
                        .fontWeight(.medium)
                }
            }
        }
    }

    // MARK: - Helpers

    private var confidenceBadge: some View {
        Text(record.suggestion.confidence.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidenceColor.opacity(0.2))
            .foregroundColor(confidenceColor)
            .cornerRadius(6)
    }

    private var confidenceColor: Color {
        switch record.suggestion.confidence {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .green
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .pending: return .blue
        case .applied: return .green
        case .dismissed: return .gray
        case .autoApplied: return .orange
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
