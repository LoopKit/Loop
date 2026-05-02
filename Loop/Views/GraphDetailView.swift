//
//  GraphDetailView.swift
//  Loop
//
//  GraphDetailView — Detailed data popup for long-hold on glucose chart.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import SwiftUI

// MARK: - Data Model

struct GraphDetailData {
    var date: Date
    var glucoseValue: Double?
    var glucoseUnit: HKUnit = .milligramsPerDeciliter
    var insulinOnBoard: Double?
    var carbsOnBoard: Double?
    var activePreset: String?
    var recentBolus: (units: Double, date: Date)?
    var basalRate: Double?
    var heartRate: Double?
    var activeAutoPreset: String?
}

// MARK: - GraphDetailView

struct GraphDetailView: View {
    let data: GraphDetailData
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider().padding(.vertical, 6)
            dataRows
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: true)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Image(systemName: "chart.xyaxis.line")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data Rows

    private var dataRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let glucose = data.glucoseValue {
                dataRow(
                    icon: "drop.fill",
                    color: glucoseColor(glucose),
                    label: "Glucose",
                    value: formattedGlucose(glucose)
                )
            }

            if let iob = data.insulinOnBoard {
                dataRow(
                    icon: "syringe.fill",
                    color: .orange,
                    label: "IOB",
                    value: String(format: "%.2f U", iob)
                )
            }

            if let cob = data.carbsOnBoard {
                dataRow(
                    icon: "fork.knife",
                    color: .green,
                    label: "COB",
                    value: String(format: "%.0f g", cob)
                )
            }

            if let bolus = data.recentBolus {
                let offset = data.date.timeIntervalSince(bolus.date)
                let offsetStr = abs(offset) < 60 ? "at this time" : "\(Int(abs(offset) / 60)) min \(offset > 0 ? "before" : "after")"
                dataRow(
                    icon: "cross.vial.fill",
                    color: .blue,
                    label: "Bolus",
                    value: String(format: "%.2f U (%@)", bolus.units, offsetStr)
                )
            }

            if let basal = data.basalRate {
                dataRow(
                    icon: "waveform.path.ecg",
                    color: .teal,
                    label: "Basal",
                    value: String(format: "%.3f U/hr", basal)
                )
            }

            if let preset = data.activePreset {
                dataRow(
                    icon: "slider.horizontal.3",
                    color: .purple,
                    label: "Preset",
                    value: preset
                )
            }

            if let autoPreset = data.activeAutoPreset {
                dataRow(
                    icon: "figure.walk",
                    color: Color(red: 76/255, green: 175/255, blue: 80/255),
                    label: "AutoPreset",
                    value: autoPreset
                )
            }

            if let hr = data.heartRate {
                dataRow(
                    icon: "heart.fill",
                    color: .red,
                    label: "Heart Rate",
                    value: "\(Int(hr)) bpm"
                )
            }
        }
    }

    // MARK: - Row Helper

    private func dataRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
            Spacer()
        }
    }

    // MARK: - Formatting

    private var formattedDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(data.date) {
            formatter.dateFormat = "'Today' h:mm a"
        } else if calendar.isDateInYesterday(data.date) {
            formatter.dateFormat = "'Yesterday' h:mm a"
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: data.date)
    }

    private func formattedGlucose(_ value: Double) -> String {
        if data.glucoseUnit == .milligramsPerDeciliter {
            return "\(Int(value)) mg/dL"
        } else {
            return String(format: "%.1f mmol/L", value)
        }
    }

    private func glucoseColor(_ value: Double) -> Color {
        let mgdl = data.glucoseUnit == .milligramsPerDeciliter ? value : value * 18.0
        if mgdl < 70 { return .red }
        if mgdl > 180 { return .orange }
        return .green
    }
}

// MARK: - Observing Wrapper (updates as async data loads)

struct GraphDetailObservingView: View {
    @ObservedObject var viewModel: GraphDetailViewModel
    let onDismiss: () -> Void

    var body: some View {
        GraphDetailView(data: viewModel.data, onDismiss: onDismiss)
    }
}
