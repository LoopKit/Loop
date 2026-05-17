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
    case rhr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep: return NSLocalizedString("Sleep", comment: "Biometric tile label")
        case .steps: return NSLocalizedString("Steps", comment: "Biometric tile label")
        case .hrv: return NSLocalizedString("HRV", comment: "Biometric tile label")
        case .exercise: return NSLocalizedString("Exercise", comment: "Biometric tile label")
        case .rhr: return NSLocalizedString("Resting HR", comment: "Biometric tile label")
        }
    }

    var icon: String {
        switch self {
        case .sleep: return "moon.fill"
        case .steps: return "figure.walk"
        case .hrv: return "waveform.path.ecg"
        case .exercise: return "heart.fill"
        case .rhr: return "heart.circle.fill"
        }
    }

    var unit: String {
        switch self {
        case .sleep: return NSLocalizedString("hr", comment: "Hours unit abbreviation")
        case .steps: return NSLocalizedString("steps", comment: "Steps unit")
        case .hrv: return NSLocalizedString("ms", comment: "Milliseconds unit abbreviation")
        case .exercise: return NSLocalizedString("min", comment: "Minutes unit abbreviation")
        case .rhr: return NSLocalizedString("bpm", comment: "Beats per minute unit")
        }
    }

    func rawValue(from entry: AppleHealthIREntry) -> Double? {
        switch self {
        case .sleep: return entry.sleepHours
        case .steps: return entry.stepCount
        case .hrv: return entry.hrvSDNN
        case .exercise: return entry.exerciseMinutes
        case .rhr: return entry.heartRate
        }
    }

    func delta(from entry: AppleHealthIREntry) -> Double {
        switch self {
        case .sleep: return entry.sleepDelta
        case .steps: return entry.stepsDelta
        case .hrv: return entry.hrvDelta
        case .exercise: return entry.exerciseDelta
        case .rhr: return entry.rhrDelta
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
                BandInfo(label: "Zone 1", range: "< \(format(t.sleepT1))h", effect: t.sleepE1),
                BandInfo(label: "Zone 2", range: "\(format(t.sleepT1))–\(format(t.sleepT2))h", effect: t.sleepE2),
                BandInfo(label: "Zone 3", range: "\(format(t.sleepT2))–\(format(t.sleepT3))h", effect: t.sleepE3),
                BandInfo(label: "Zone 4", range: "\(format(t.sleepT3))–\(format(t.sleepT4))h", effect: t.sleepE4),
            ]
        case .steps:
            return [
                BandInfo(label: "Zone 1", range: "< \(Int(t.stepsT1))", effect: t.stepsE1),
                BandInfo(label: "Zone 2", range: "\(Int(t.stepsT1))–\(Int(t.stepsT2))", effect: t.stepsE2),
                BandInfo(label: "Zone 3", range: "\(Int(t.stepsT2))–\(Int(t.stepsT3))", effect: t.stepsE3),
                BandInfo(label: "Zone 4", range: "\(Int(t.stepsT3))–\(Int(t.stepsT4))", effect: t.stepsE4),
            ]
        case .hrv:
            return [
                BandInfo(label: "Zone 1", range: "< \(Int(t.hrvT1))ms", effect: t.hrvE1),
                BandInfo(label: "Zone 2", range: "\(Int(t.hrvT1))–\(Int(t.hrvT2))ms", effect: t.hrvE2),
                BandInfo(label: "Zone 3", range: "\(Int(t.hrvT2))–\(Int(t.hrvT3))ms", effect: t.hrvE3),
                BandInfo(label: "Zone 4", range: "\(Int(t.hrvT3))–\(Int(t.hrvT4))ms", effect: t.hrvE4),
            ]
        case .exercise:
            return [
                BandInfo(label: "Zone 1", range: "< \(Int(t.exerciseT1))min", effect: t.exerciseE1),
                BandInfo(label: "Zone 2", range: "\(Int(t.exerciseT1))–\(Int(t.exerciseT2))min", effect: t.exerciseE2),
                BandInfo(label: "Zone 3", range: "\(Int(t.exerciseT2))–\(Int(t.exerciseT3))min", effect: t.exerciseE3),
                BandInfo(label: "Zone 4", range: "\(Int(t.exerciseT3))–\(Int(t.exerciseT4))min", effect: t.exerciseE4),
            ]
        case .rhr:
            return [
                BandInfo(label: "Zone 1", range: "< \(Int(t.rhrT1))bpm", effect: 0.0),
                BandInfo(label: "Zone 2", range: "\(Int(t.rhrT1))–\(Int(t.rhrT2))bpm", effect: t.rhrE1),
                BandInfo(label: "Zone 3", range: "\(Int(t.rhrT2))–\(Int(t.rhrT3))bpm", effect: t.rhrE2),
                BandInfo(label: "Zone 4", range: "\(Int(t.rhrT3))–\(Int(t.rhrT4))bpm", effect: t.rhrE3),
                BandInfo(label: "Zone 5", range: "≥ \(Int(t.rhrT4))bpm", effect: t.rhrE4),
            ]
        }
    }

    private func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
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
