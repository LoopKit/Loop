//
//  CurrentSetupViewModel.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopCore

@MainActor
final class CurrentSetupViewModel: ObservableObject {
    @Published private(set) var history: SetupHistory?
    /// The change whose setup is being compared; the latest by default.
    @Published private(set) var selected: SetupChange?
    @Published private(set) var comparison: SetupComparison?
    /// Time in range for each change's setup, by change date.
    @Published private(set) var timeInRange: [Date: Double] = [:]
    @Published private(set) var isLoading = true

    let outcomesPackageBuilder: OutcomesPackageBuilder?
    private let loadHistory: () async throws -> SetupHistory
    private let customChangeStore: CustomSetupChangeStore
    private let glucoseStore: GlucoseStoreProtocol?
    private let insulinDeliveryHistory: ((Int) async throws -> InsulinDeliveryHistory)?
    private let cacheDuration: TimeInterval
    private let now: () -> Date

    private var samples: [StoredGlucoseSample] = []
    private var insulin: InsulinDeliveryHistory?
    /// Taken before the data loads, so the data covers up to it
    private var loadedAt: Date?

    init(selected: SetupChange?,
         loadHistory: @escaping () async throws -> SetupHistory,
         glucoseStore: GlucoseStoreProtocol?,
         insulinDeliveryHistory: ((Int) async throws -> InsulinDeliveryHistory)?,
         outcomesPackageBuilder: OutcomesPackageBuilder? = nil,
         customChangeStore: CustomSetupChangeStore = CustomSetupChangeStore(),
         cacheDuration: TimeInterval = Bundle.main.localCacheDuration,
         now: @escaping () -> Date = { Date() }) {
        self.selected = selected
        self.outcomesPackageBuilder = outcomesPackageBuilder
        self.loadHistory = loadHistory
        self.customChangeStore = customChangeStore
        self.glucoseStore = glucoseStore
        self.insulinDeliveryHistory = insulinDeliveryHistory
        self.cacheDuration = cacheDuration
        self.now = now
    }

    var isCurrentSelected: Bool {
        selected != nil && selected == history?.latest
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let history = try? await loadHistory() else {
            return
        }
        self.history = history
        selected = history.latest
        let end = now()
        loadedAt = end
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

    /// The earliest date a marked change can have and still show results.
    var earliestCustomChangeDate: Date {
        now() - cacheDuration
    }

    func addCustomChange(date: Date, note: String) async {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        customChangeStore.add(CustomSetupChange(date: date, note: note.isEmpty ? nil : note))
        await load()
    }

    func removeCustomChanges(in change: SetupChange) async {
        change.customChanges.forEach { customChangeStore.remove(id: $0.id) }
        await load()
    }

    private func compare() {
        guard let selected, let history else {
            comparison = nil
            return
        }
        comparison = SetupComparison(change: selected, samples: samples, insulinHistory: insulin, now: loadedAt ?? now())
    }
}
