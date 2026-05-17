//
//  BiometricIRDetailView.swift
//  Loop
//

import SwiftUI

enum BiometricTileType: String, CaseIterable, Identifiable {
    case sleep
    case steps
    case hrv
    case exercise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep: return NSLocalizedString("Sleep", comment: "Biometric tile label")
        case .steps: return NSLocalizedString("Steps", comment: "Biometric tile label")
        case .hrv: return NSLocalizedString("HRV", comment: "Biometric tile label")
        case .exercise: return NSLocalizedString("Exercise", comment: "Biometric tile label")
        }
    }

    var icon: String {
        switch self {
        case .sleep: return "moon.fill"
        case .steps: return "figure.walk"
        case .hrv: return "waveform.path.ecg"
        case .exercise: return "heart.fill"
        }
    }

    var unit: String {
        switch self {
        case .sleep: return NSLocalizedString("hr", comment: "Hours unit abbreviation")
        case .steps: return NSLocalizedString("steps", comment: "Steps unit")
        case .hrv: return NSLocalizedString("ms", comment: "Milliseconds unit abbreviation")
        case .exercise: return NSLocalizedString("min", comment: "Minutes unit abbreviation")
        }
    }

    func rawValue(from entry: AppleHealthIREntry) -> Double? {
        switch self {
        case .sleep: return entry.sleepHours
        case .steps: return entry.stepCount
        case .hrv: return entry.hrvSDNN
        case .exercise: return entry.exerciseMinutes
        }
    }

    func delta(from entry: AppleHealthIREntry) -> Double {
        switch self {
        case .sleep: return entry.sleepDelta
        case .steps: return entry.stepsDelta
        case .hrv: return entry.hrvDelta
        case .exercise: return entry.exerciseDelta
        }
    }
}

struct BiometricIRDetailView: View {
    let tileType: BiometricTileType
    let entry: AppleHealthIREntry?
    let allEntries: [AppleHealthIREntry]

    var body: some View {
        if #available(iOS 16, *) {
            baseView.presentationDetents([.medium, .large])
        } else {
            baseView
        }
    }

    @ViewBuilder private var baseView: some View {
        NavigationView {
            List {
                currentValueSection
                thresholdBandSection
                historySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(tileType.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var currentValueSection: some View {
        Section(header: Text(NSLocalizedString("Current", comment: "Section header"))) {
            if let entry = entry, let raw = tileType.rawValue(from: entry) {
                HStack {
                    Text(String(format: "%.1f %@", raw, tileType.unit))
                        .font(.title2)
                    Spacer()
                    let delta = tileType.delta(from: entry)
                    Text(String(format: "%+.1f%%", delta))
                        .foregroundColor(delta >= 0 ? .red : .green)
                }
            } else {
                Text(NSLocalizedString("No data", comment: "No biometric data available"))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var thresholdBandSection: some View {
        Section(header: Text(NSLocalizedString("Thresholds", comment: "Section header"))) {
            if let entry = entry {
                let t = entry.thresholdsSnapshot
                ForEach(bands(for: t), id: \.label) { band in
                    ThresholdRow(label: band.label, range: band.range, effect: band.effect)
                }
            }
        }
    }

    private var historySection: some View {
        Section(header: Text(NSLocalizedString("Last 24 Hours", comment: "Section header"))) {
            if allEntries.isEmpty {
                Text(NSLocalizedString("No history", comment: "No history entries"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(allEntries.reversed()) { entry in
                    HistoryRow(entry: entry, tileType: tileType)
                }
            }
        }
    }

    private struct BandInfo {
        let label: String
        let range: String
        let effect: Double
    }

    private func bands(for t: AppleHealthIRThresholds) -> [BandInfo] {
        switch tileType {
        case .sleep:
            return [
                BandInfo(label: "Severe", range: "< \(Int(t.sleepSevereThreshold))h", effect: t.sleepSevereEffect),
                BandInfo(label: "Mild", range: "\(Int(t.sleepSevereThreshold))–\(Int(t.sleepMildThreshold))h", effect: (t.sleepSevereEffect + t.sleepMildEffect) / 2),
                BandInfo(label: "Normal", range: "> \(Int(t.sleepMildThreshold))h", effect: t.sleepMildEffect),
            ]
        case .steps:
            return [
                BandInfo(label: "Low", range: "\(Int(t.stepsLowMin))–\(Int(t.stepsMediumMin))", effect: t.stepsLowEffect),
                BandInfo(label: "Medium", range: "\(Int(t.stepsMediumMin))–\(Int(t.stepsHighMin))", effect: t.stepsMediumEffect),
                BandInfo(label: "High", range: "> \(Int(t.stepsHighMin))", effect: t.stepsHighEffect),
            ]
        case .hrv:
            return [
                BandInfo(label: "Very Low", range: "< \(Int(t.hrvVeryLowMax))ms", effect: t.hrvVeryLowEffect),
                BandInfo(label: "Low", range: "\(Int(t.hrvVeryLowMax))–\(Int(t.hrvLowMax))ms", effect: t.hrvLowEffect),
                BandInfo(label: "Normal", range: "\(Int(t.hrvLowMax))–\(Int(t.hrvNormalMax))ms", effect: t.hrvNormalEffect),
                BandInfo(label: "High", range: "> \(Int(t.hrvNormalMax))ms", effect: t.hrvHighEffect),
            ]
        case .exercise:
            return [
                BandInfo(label: "Moderate", range: "\(Int(t.exerciseMinThreshold))–\(Int(t.exerciseModerateMax))min", effect: t.exerciseModerateEffect),
                BandInfo(label: "Substantial", range: "\(Int(t.exerciseModerateMax))–\(Int(t.exerciseSubstantialMax))min", effect: t.exerciseSubstantialEffect),
                BandInfo(label: "Heavy", range: "> \(Int(t.exerciseSubstantialMax))min", effect: t.exerciseHeavyEffect),
            ]
        }
    }

    private struct ThresholdRow: View {
        let label: String
        let range: String
        let effect: Double

        var body: some View {
            HStack {
                Text(label).frame(width: 80, alignment: .leading)
                Text(range).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%+.0f%%", effect))
                    .foregroundColor(effect >= 0 ? .red : .green)
            }
            .font(.subheadline)
        }
    }

    private struct HistoryRow: View {
        let entry: AppleHealthIREntry
        let tileType: BiometricTileType

        var body: some View {
            HStack {
                Text(entry.timestamp, style: .time)
                    .foregroundColor(.secondary)
                    .font(.caption)
                Spacer()
                let delta = tileType.delta(from: entry)
                Text(String(format: "%+.1f%%", delta))
                    .foregroundColor(delta >= 0 ? .red : .green)
                    .font(.caption)
                Text(entry.formattedMultiplier)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
