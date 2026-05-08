//
//  LoopInsights_SuggestionDetailView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

/// Detailed view of a single suggestion showing reasoning, current vs proposed
/// values for each time block, and apply/dismiss actions.
struct LoopInsights_SuggestionDetailView: View {

    let record: LoopInsightsSuggestionRecord
    let onApply: () -> Void
    let onDismiss: () -> Void
    var onRevert: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    private var unitContext: LoopInsights_GlucoseUnitContext {
        LoopInsights_GlucoseUnitContext(displayGlucosePreference: displayGlucosePreference)
    }

    /// Format an ISF/CR/basal value with the user's unit. ISF values are stored
    /// in canonical mg/dL — convert to mmol/L for mmol/L users.
    private func formatValue(_ value: Double, settingType: LoopInsightsSettingType) -> String {
        switch settingType {
        case .insulinSensitivity:
            return "\(unitContext.formatMgdl(value)) per U"
        case .carbRatio, .basalRate:
            return String(format: "\(settingType.valueFormatString) \(settingType.unitDescription)", value)
        }
    }

    var body: some View {
        List {
            headerSection
            reasoningSection
            if record.suggestion.successCriteria != nil {
                successCriteriaSection
            }
            if record.outcomeEvaluation != nil {
                outcomeEvaluationSection
            }
            if record.suggestion.hasGuardrailWarning {
                guardrailWarningSection
            }
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
                            Text(formatValue(block.currentValue, settingType: record.suggestion.settingType))
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
                            Text(formatValue(block.proposedValue, settingType: record.suggestion.settingType))
                                .font(.body)
                                .fontWeight(.bold)
                                .foregroundColor(proposedValueColor(for: block))
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

    // MARK: - Success Criteria

    private var successCriteriaSection: some View {
        Section(header: Text(NSLocalizedString("What to Watch For", comment: "LoopInsights success criteria header"))) {
            if let criteria = record.suggestion.successCriteria {
                // Evaluation timeline
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.blue)
                    Text(String(
                        format: NSLocalizedString("Evaluate after %d days", comment: "LoopInsights evaluation timeline"),
                        criteria.evaluationDays
                    ))
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .padding(.vertical, 2)

                // Expected outcomes
                ForEach(criteria.expectedOutcomes, id: \.self) { outcome in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "target")
                            .foregroundColor(.green)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(outcome)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Metric targets
                if !criteria.metricTargets.isEmpty {
                    ForEach(Array(criteria.metricTargets.sorted(by: { $0.key < $1.key })), id: \.key) { metric, target in
                        HStack {
                            Text(metric.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(target)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }

                // Revert warnings
                if !criteria.revertWarnings.isEmpty {
                    Text(NSLocalizedString("Things to watch out for", comment: "LoopInsights revert warnings subheader"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .padding(.top, 8)

                    ForEach(criteria.revertWarnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(warning)
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Outcome Evaluation

    private var outcomeEvaluationSection: some View {
        Section(header: Text(NSLocalizedString("Outcome", comment: "LoopInsights outcome evaluation header"))) {
            if let evaluation = record.outcomeEvaluation {
                // Verdict badge
                HStack(spacing: 8) {
                    Image(systemName: evaluation.verdict.systemImage)
                        .foregroundColor(evaluation.verdict.color)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(evaluation.verdict.displayName)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(evaluation.verdict.color)
                        if evaluation.criteriaTotalCount > 0 {
                            Text(String(
                                format: NSLocalizedString("%d of %d criteria met", comment: "LoopInsights criteria met count"),
                                evaluation.criteriaMetCount,
                                evaluation.criteriaTotalCount
                            ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(Self.dateFormatter.string(from: evaluation.evaluatedAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)

                // AI reasoning
                if !evaluation.reasoning.isEmpty {
                    Text(evaluation.reasoning)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
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
                    Text(NSLocalizedString("Apply Suggestion", comment: "LoopInsights apply suggestion button"))
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 10)
                .background(Color.green)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)

            Button(action: {
                onDismiss()
                dismiss()
            }) {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("Dismiss Suggestion", comment: "LoopInsights dismiss suggestion button"))
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 10)
                .background(Color.red)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
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

            // Revert button for applied/auto-applied records
            if record.status.isRevertable, record.settingsSnapshotBefore != nil, let onRevert = onRevert {
                Button(action: {
                    onRevert()
                    dismiss()
                }) {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Revert Changes", comment: "LoopInsights revert button"))
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Guardrail Warning

    private var guardrailWarningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    Text(NSLocalizedString("Safety Warning", comment: "LoopInsights guardrail warning title"))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }

                ForEach(record.suggestion.guardrailWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if record.suggestion.hasAbsoluteViolation {
                    Text(NSLocalizedString("One or more values are outside safe clinical bounds and cannot be applied.", comment: "LoopInsights guardrail absolute block message"))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    /// Color for a proposed value based on guardrail classification
    private func proposedValueColor(for block: LoopInsightsTimeBlock) -> Color {
        let classification = LoopInsights_SafetyGuardrails.classify(
            value: block.proposedValue, settingType: record.suggestion.settingType
        )
        switch classification {
        case .belowAbsolute, .aboveAbsolute:
            return .red
        case .belowRecommended, .aboveRecommended:
            return .orange
        case .withinRecommended:
            return block.proposedValue > block.currentValue ? .orange : .blue
        }
    }

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
        case .reverted: return .purple
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
