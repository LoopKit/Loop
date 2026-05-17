//
//  BiometricHomePanel.swift
//  Loop
//

import SwiftUI
import Combine

struct BiometricHomePanel: View {
    private let irService: AppleHealthIRServiceProtocol
    private let biometricsService: BiometricsServiceProtocol

    @State private var selectedTile: BiometricTileType?
    @State private var latestSnapshot: BiometricSnapshot?
    @State private var currentMultiplier: Double = 1.0

    init(irService: AppleHealthIRServiceProtocol, biometricsService: BiometricsServiceProtocol) {
        self.irService = irService
        self.biometricsService = biometricsService
    }

    // Subscriptions are managed with a class-level reference stored externally
    // to avoid SwiftUI re-creating the Set on each body evaluation.
    @State private var _cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(spacing: 0) {
            // Header row matching Loop chart row style
            HStack {
                Text(NSLocalizedString("Biometrics", comment: "Biometrics panel section title"))
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                IRBadge(multiplier: currentMultiplier)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Metric rows
            ForEach(BiometricTileType.allCases) { tile in
                MetricRow(
                    tile: tile,
                    snapshot: latestSnapshot,
                    entry: irService.latestEntry
                )
                .contentShape(Rectangle())
                .onTapGesture { selectedTile = tile }

                if tile != BiometricTileType.allCases.last {
                    Divider()
                        .padding(.leading, 36)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear(perform: subscribe)
        .onDisappear(perform: unsubscribe)
        .sheet(item: $selectedTile) { tile in
            BiometricIRDetailView(
                tileType: tile,
                entry: irService.latestEntry,
                allEntries: AppleHealthIREntry.load()
            )
        }
    }

    // MARK: - Sub-views

    private struct MetricRow: View {
        let tile: BiometricTileType
        let snapshot: BiometricSnapshot?
        let entry: AppleHealthIREntry?

        private var rawValue: Double? {
            guard let snapshot = snapshot else { return nil }
            switch tile {
            case .sleep: return snapshot.sleepHours
            case .steps: return snapshot.stepCount
            case .hrv: return snapshot.hrvSDNN
            case .exercise: return snapshot.exerciseMinutes
            case .rhr: return snapshot.heartRate
            }
        }

        private var delta: Double? {
            guard let entry = entry else { return nil }
            switch tile {
            case .sleep: return entry.sleepDelta
            case .steps: return entry.stepsDelta
            case .hrv: return entry.hrvDelta
            case .exercise: return entry.exerciseDelta
            case .rhr: return entry.rhrDelta
            }
        }

        private var formattedValue: String {
            guard let raw = rawValue else { return "--" }
            switch tile {
            case .steps:
                return String(format: "%.0f %@", raw, tile.unit)
            default:
                return String(format: "%.1f %@", raw, tile.unit)
            }
        }

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: tile.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 16)

                Text(tile.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(formattedValue)
                    .font(.subheadline.bold())
                    .foregroundColor(rawValue == nil ? .secondary : .primary)

                if let d = delta {
                    DeltaChip(delta: d)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityLabel(accessibilityLabel)
        }

        private var accessibilityLabel: String {
            let valueText = rawValue.map { String(format: "%.1f %@", $0, tile.unit) } ?? "no data"
            let deltaText = delta.map { String(format: ", delta %+.0f%%", $0) } ?? ""
            return "\(tile.displayName): \(valueText)\(deltaText)"
        }
    }

    private struct DeltaChip: View {
        let delta: Double

        var body: some View {
            Text(String(format: "%+.0f%%", delta))
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(delta >= 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                .foregroundColor(delta >= 0 ? .red : .green)
                .cornerRadius(4)
        }
    }

    private struct IRBadge: View {
        let multiplier: Double

        private var color: Color {
            if multiplier < 1.1 { return .green }
            if multiplier < 1.5 { return .yellow }
            return .red
        }

        var body: some View {
            Text(String(format: "IR \u{00D7}%.2f", multiplier))
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.2))
                .foregroundColor(color)
                .cornerRadius(8)
                .accessibilityLabel(
                    String(format: NSLocalizedString("Insulin resistance multiplier %.2f", comment: "IR badge accessibility label"), multiplier)
                )
        }
    }

    private func subscribe() {
        biometricsService.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] snapshot in latestSnapshot = snapshot }
            .store(in: &_cancellables)
        irService.multiplierPublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] m in currentMultiplier = m }
            .store(in: &_cancellables)
    }

    private func unsubscribe() {
        _cancellables.removeAll()
    }
}
