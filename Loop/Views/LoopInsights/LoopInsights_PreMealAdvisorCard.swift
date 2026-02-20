//
//  LoopInsights_PreMealAdvisorCard.swift
//  Loop
//
//  LoopInsights — Compact card shown in CarbEntryView (via FoodFinder_EntryPoint)
//  when the user identifies a food they've eaten before. Shows historical stats
//  and async AI advice.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// "Personal Insight" card shown below food identification in FoodFinder.
struct LoopInsights_PreMealAdvisorCard: View {

    let advice: LoopInsights_PreMealAdvice
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
                    Text(NSLocalizedString("Personal Insight", comment: "Pre-meal advisor card header"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(red: 26/255, green: 138/255, blue: 158/255))
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Stats row
            if advice.averagePeakRise > 0 {
                HStack(spacing: 16) {
                    statPill(
                        label: NSLocalizedString("Meals", comment: "Pre-meal advisor meals count"),
                        value: "\(advice.mealCount)"
                    )
                    statPill(
                        label: NSLocalizedString("Peak Rise", comment: "Pre-meal advisor peak rise"),
                        value: String(format: "+%.0f", advice.averagePeakRise),
                        color: advice.averagePeakRise > 60 ? .orange : .green
                    )
                    statPill(
                        label: NSLocalizedString("Peak Time", comment: "Pre-meal advisor peak time"),
                        value: String(format: "%.0f min", advice.averageTimeToPeak)
                    )
                    statPill(
                        label: NSLocalizedString("Avg Carbs", comment: "Pre-meal advisor avg carbs"),
                        value: String(format: "%.0fg", advice.averageCarbs)
                    )
                }
            }

            // Summary text
            Text(advice.summaryText)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // AI advice (async loaded)
            if advice.isLoadingAI {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(NSLocalizedString("Getting personalized advice...", comment: "Pre-meal advisor loading AI"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let aiText = advice.aiAdvice {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(aiText)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 26/255, green: 138/255, blue: 158/255).opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 26/255, green: 138/255, blue: 158/255).opacity(0.2), lineWidth: 1)
        )
    }

    private func statPill(label: String, value: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption2.weight(.bold))
                .foregroundColor(color)
        }
    }
}
