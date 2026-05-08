//
//  LoopInsights_MealDebriefCard.swift
//  Loop
//
//  LoopInsights — Expandable card showing predicted vs actual glucose,
//  AI interpretation, effective carbs badge, and learnings.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Expandable debrief section shown inside a meal card when the meal is ≥2h old.
struct LoopInsights_MealDebriefCard: View {

    let event: LoopInsightsMealEvent
    let readiness: LoopInsights_DebriefReadiness
    let debrief: LoopInsights_MealDebrief?
    let isLoading: Bool
    let errorMessage: String?
    let isExpanded: Bool
    let onToggle: () -> Void
    let unitContext: LoopInsights_GlucoseUnitContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            debriefHeader
            if isExpanded {
                debriefContent
            }
        }
    }

    // MARK: - Header

    private var debriefHeader: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                readinessIcon
                Text(headerText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if canExpand {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canExpand)
    }

    private var readinessIcon: some View {
        Group {
            switch readiness {
            case .ready, .readyToGenerate:
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            case .tooRecent:
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.orange)
            case .noSnapshot:
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .featureDisabled:
                EmptyView()
            }
        }
    }

    private var headerText: String {
        switch readiness {
        case .ready, .readyToGenerate:
            return NSLocalizedString("AI Meal Debrief", comment: "LoopInsights debrief header")
        case .tooRecent(let mins):
            return String(format: NSLocalizedString("Debrief ready in %d min", comment: "LoopInsights debrief countdown"), mins)
        case .noSnapshot:
            return NSLocalizedString("No prediction data captured", comment: "LoopInsights no snapshot")
        case .featureDisabled:
            return ""
        }
    }

    private var canExpand: Bool {
        switch readiness {
        case .ready, .readyToGenerate:
            return true
        default:
            return false
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var debriefContent: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(NSLocalizedString("Generating debrief...", comment: "LoopInsights generating debrief"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } else if let error = errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if let debrief = debrief {
            VStack(alignment: .leading, spacing: 10) {
                // Mini chart: predicted vs actual
                predictedVsActualChart(debrief: debrief)

                // Effective carbs badge
                if let effectiveCarbs = debrief.effectiveCarbsEstimate {
                    effectiveCarbsBadge(effectiveCarbs: effectiveCarbs, enteredCarbs: event.carbs)
                }

                // AI interpretation
                Text(debrief.aiInterpretation)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Learnings
                if !debrief.learnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Key Takeaways", comment: "LoopInsights debrief learnings header"))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                        ForEach(debrief.learnings, id: \.self) { learning in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Text(learning)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Peak comparison
                if let predPeak = debrief.predictedPeakGlucose,
                   let actPeak = debrief.actualPeakGlucose {
                    peakComparisonRow(predicted: predPeak, actual: actPeak, timingDelta: debrief.peakTimingDeltaMinutes)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Predicted vs Actual Chart

    private func predictedVsActualChart(debrief: LoopInsights_MealDebrief) -> some View {
        // Find the prediction snapshot for timeline data
        let snapshot = LoopInsights_PredictionSnapshotStore.snapshot(forMealID: debrief.mealRecordID)

        return VStack(alignment: .leading, spacing: 4) {
            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Rectangle().fill(Color.blue.opacity(0.5))
                        .frame(width: 16, height: 2)
                        .overlay(
                            Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .foregroundColor(.blue)
                        )
                    Text(NSLocalizedString("Predicted", comment: "LoopInsights chart predicted"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Rectangle().fill(Color.green).frame(width: 16, height: 2)
                    Text(NSLocalizedString("Actual", comment: "LoopInsights chart actual"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Chart
            GeometryReader { geo in
                let width = geo.size.width
                let height: CGFloat = 80

                // Build data points for 0-4h
                let actualPoints = event.glucoseTimeline.filter { $0.minutesAfter >= 0 && $0.minutesAfter <= 240 }
                let predictedPoints: [(Int, Double)] = {
                    guard let snap = snapshot else { return [] }
                    var pts: [(Int, Double)] = []
                    for (i, v) in snap.predictedValues.enumerated() {
                        let min = Int(Double(i) * snap.intervalSeconds / 60)
                        if min <= 240 { pts.append((min, v)) }
                    }
                    return pts
                }()

                // Find global min/max for scale
                let allValues = actualPoints.map(\.glucose) + predictedPoints.map(\.1)
                let minVal = (allValues.min() ?? 70) - 10
                let maxVal = (allValues.max() ?? 200) + 10
                let valRange = max(maxVal - minVal, 1)

                ZStack {
                    // Grid lines at 70 and 180
                    ForEach([70.0, 180.0], id: \.self) { threshold in
                        if threshold >= minVal && threshold <= maxVal {
                            let y = height * (1 - CGFloat((threshold - minVal) / valRange))
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: width, y: y))
                            }
                            .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        }
                    }

                    // Predicted line (dashed blue)
                    if predictedPoints.count >= 2 {
                        Path { path in
                            for (i, pt) in predictedPoints.enumerated() {
                                let x = width * CGFloat(pt.0) / 240
                                let y = height * (1 - CGFloat((pt.1 - minVal) / valRange))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }

                    // Actual line (solid green)
                    if actualPoints.count >= 2 {
                        Path { path in
                            for (i, pt) in actualPoints.enumerated() {
                                let x = width * CGFloat(pt.minutesAfter) / 240
                                let y = height * (1 - CGFloat((pt.glucose - minVal) / valRange))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.green, lineWidth: 2)
                    }

                    // Time labels
                    HStack {
                        Text("0h").font(.system(size: 8)).foregroundColor(.secondary)
                        Spacer()
                        Text("1h").font(.system(size: 8)).foregroundColor(.secondary)
                        Spacer()
                        Text("2h").font(.system(size: 8)).foregroundColor(.secondary)
                        Spacer()
                        Text("3h").font(.system(size: 8)).foregroundColor(.secondary)
                        Spacer()
                        Text("4h").font(.system(size: 8)).foregroundColor(.secondary)
                    }
                    .offset(y: height / 2 + 6)
                }
            }
            .frame(height: 96)
        }
    }

    // MARK: - Effective Carbs Badge

    private func effectiveCarbsBadge(effectiveCarbs: Double, enteredCarbs: Double) -> some View {
        let delta = effectiveCarbs - enteredCarbs
        let color: Color = abs(delta) <= 5 ? .green : (delta > 0 ? .orange : .blue)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Effective Carbs", comment: "LoopInsights effective carbs label"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(String(format: "~%.0fg", effectiveCarbs))
                        .font(.caption.weight(.bold))
                        .foregroundColor(color)
                    Text(NSLocalizedString("vs", comment: "LoopInsights vs label"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0fg entered", enteredCarbs))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if abs(delta) > 2 {
                Text(String(format: "%+.0fg", delta))
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .cornerRadius(6)
            }
        }
    }

    // MARK: - Peak Comparison

    private func peakComparisonRow(predicted: Double, actual: Double, timingDelta: Double?) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Predicted Peak", comment: "LoopInsights predicted peak"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(unitContext.formatMgdl(predicted))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Actual Peak", comment: "LoopInsights actual peak"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(unitContext.formatMgdl(actual))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.green)
            }
            if let delta = timingDelta, abs(delta) > 5 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Peak Timing", comment: "LoopInsights peak timing"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%+.0f min", delta))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(delta > 0 ? .orange : .blue)
                }
            }
            Spacer()
        }
    }
}
