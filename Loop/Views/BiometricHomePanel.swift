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
    private var cancellables = Set<AnyCancellable>()

    init(irService: AppleHealthIRServiceProtocol, biometricsService: BiometricsServiceProtocol) {
        self.irService = irService
        self.biometricsService = biometricsService
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                IRBadge(multiplier: currentMultiplier)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(BiometricTileType.allCases) { tile in
                    BiometricTile(
                        tile: tile,
                        snapshot: latestSnapshot,
                        entry: irService.latestEntry
                    )
                    .onTapGesture { selectedTile = tile }
                }
            }
        }
        .frame(minHeight: 210)
        .padding()
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

    // Subscriptions are managed with a class-level reference stored externally
    // to avoid SwiftUI re-creating the Set on each body evaluation.
    @State private var _cancellables = Set<AnyCancellable>()

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

    // MARK: - Sub-views

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

    private struct BiometricTile: View {
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
            }
        }

        private var delta: Double? {
            guard let entry = entry else { return nil }
            switch tile {
            case .sleep: return entry.sleepDelta
            case .steps: return entry.stepsDelta
            case .hrv: return entry.hrvDelta
            case .exercise: return entry.exerciseDelta
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: tile.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(tile.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let raw = rawValue {
                    Text(String(format: "%.1f %@", raw, tile.unit))
                        .font(.subheadline.bold())
                } else {
                    Text("--")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                }
                if let d = delta {
                    DeltaChip(delta: d)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .accessibilityLabel(accessibilityLabel)
        }

        private var accessibilityLabel: String {
            let rawText = rawValue.map { String(format: "%.1f %@", $0, tile.unit) } ?? "no data"
            let deltaText = delta.map { String(format: ", delta %+.0f%%", $0) } ?? ""
            return "\(tile.displayName): \(rawText)\(deltaText)"
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
}
