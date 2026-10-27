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
    @Published private(set) var setupChange: SetupChange?
    @Published private(set) var comparison: SetupComparison?
    @Published private(set) var isLoading = true

    private let loadSetupChange: () async throws -> SetupChange?
    private let glucoseStore: GlucoseStoreProtocol?
    private let insulinDeliveryHistory: ((Int) async throws -> InsulinDeliveryHistory)?
    private let now: () -> Date

    init(setupChange: SetupChange?,
         loadSetupChange: @escaping () async throws -> SetupChange?,
         glucoseStore: GlucoseStoreProtocol?,
         insulinDeliveryHistory: ((Int) async throws -> InsulinDeliveryHistory)?,
         now: @escaping () -> Date = { Date() }) {
        self.setupChange = setupChange
        self.loadSetupChange = loadSetupChange
        self.glucoseStore = glucoseStore
        self.insulinDeliveryHistory = insulinDeliveryHistory
        self.now = now
    }

    func load() async {
        defer { isLoading = false }
        if let change = try? await loadSetupChange() {
            setupChange = change
        }
        guard let change = setupChange, !change.isLowerBound, let glucoseStore else {
            return
        }
        let end = now()
        let start = max(change.date - SetupComparison.beforeDuration, change.previousDate ?? .distantPast)
        let samples = (try? await glucoseStore.getGlucoseSamples(start: start, end: end))?
            .filter { !$0.isDisplayOnly && !$0.wasUserEntered } ?? []
        let days = Int((end.timeIntervalSince(start) / .days(1)).rounded(.up)) + 1
        let insulin = try? await insulinDeliveryHistory?(days)
        comparison = SetupComparison(change: change, samples: samples, insulinHistory: insulin, now: end)
    }
}
