//
//  CurrentSetupViewModel.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

@MainActor
final class CurrentSetupViewModel: ObservableObject {
    @Published private(set) var history: SetupHistory?
    /// The change whose setup is being compared; the latest by default.
    @Published private(set) var selected: SetupChange?
    @Published private(set) var comparison: SetupComparison?
    /// Time in range for each change's setup, by change date.
    @Published private(set) var timeInRange: [Date: Double] = [:]
    @Published private(set) var isLoading = true

    private let loadHistory: () async throws -> SetupHistory
    private let glucoseStore: GlucoseStoreProtocol?
    private let insulinDeliveryHistory: ((Int) async throws -> InsulinDeliveryHistory)?
    private let cacheDuration: TimeInterval
    private let now: () -> Date

    private var samples: [StoredGlucoseSample] = []
    private var insulin: InsulinDeliveryHistory?

    init(selected: SetupChange?,
         loadHistory: @escaping () async throws -> SetupHistory,
         glucoseStore: GlucoseStoreProtocol?,
         insulinDeliveryHistory: ((Int) async throws -> InsulinDeliveryHistory)?,
         cacheDuration: TimeInterval = Bundle.main.localCacheDuration,
         now: @escaping () -> Date = { Date() }) {
        self.selected = selected
        self.loadHistory = loadHistory
        self.glucoseStore = glucoseStore
        self.insulinDeliveryHistory = insulinDeliveryHistory
        self.cacheDuration = cacheDuration
        self.now = now
    }

    var isCurrentSelected: Bool {
        selected != nil && selected == history?.latest
    }

    func load() async {
        defer { isLoading = false }
        guard let history = try? await loadHistory() else {
            return
        }
        self.history = history
        selected = history.latest
        let end = now()
        if let glucoseStore {
            samples = (try? await glucoseStore.getGlucoseSamples(start: end - cacheDuration, end: end))?
                .filter { !$0.isDisplayOnly && !$0.wasUserEntered } ?? []
        }
        insulin = try? await insulinDeliveryHistory?(Int((cacheDuration / .days(1)).rounded()))
        timeInRange = Dictionary(uniqueKeysWithValues: history.changes.compactMap { change in
            let stats = GlucoseStatistics(samples: samples, start: change.date, end: history.end(of: change) ?? end)
            return stats.timeInRange.isEmpty ? nil : (change.date, stats.timeInRange[.target, default: 0])
        })
        compare()
    }

    func select(_ change: SetupChange) {
        selected = change
        compare()
    }

    private func compare() {
        guard let selected, let history else {
            comparison = nil
            return
        }
        comparison = SetupComparison(change: selected, samples: samples, insulinHistory: insulin, now: now())
    }
}
