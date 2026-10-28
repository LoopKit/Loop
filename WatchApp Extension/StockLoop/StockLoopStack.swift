//
//  StockLoopStack.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  Assembles the loop on the watch's stores (opened by its `LoopDataManager`), its override history
//  and WatchLoopManager. The pump appears only with a loan.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore

enum StockLoopStack {
    /// Outlives any loan. The CGM manager lives on the loop manager, which rebuilds it when the
    /// phone's configuration changes.
    struct Stack {
        let loopManager: WatchLoopManager
    }

    /// Stores, then the loop manager. nil: the stores could not be opened, so no Sport Mode.
    @MainActor
    static func assemble() async -> Stack? {
        guard let stores = await makeStores() else { return nil }

        let loopManager = WatchLoopManager(
            doseStore: stores.doseStore,
            glucoseStore: stores.glucoseStore,
            carbStore: stores.carbStore,
            overrideHistory: stores.overrideHistory,
            dosingDecisionStore: stores.dosingDecisionStore,
            alertStore: stores.alertStore,
            deviceLog: stores.deviceLog
        )

        return Stack(loopManager: loopManager)
    }

    /// The watch's stores, which its `LoopDataManager` opens for its screens and this loop alike.
    @MainActor
    static func makeStores() async -> (doseStore: DoseStore, glucoseStore: GlucoseStore, carbStore: CarbStore, overrideHistory: TemporaryScheduleOverrideHistory, dosingDecisionStore: DosingDecisionStore, alertStore: AlertStore, deviceLog: PersistentDeviceLog)? {
        guard let stores = await LoopDataManager.shared.openedStores() else { return nil }
        // One override history: a second would dose unscaled while the screens showed the override.
        let overrideHistory = makeOverrideHistory()
        let loop = stores.loopStores
        return (loop.doseStore, stores.glucoseStore, stores.carbStore, overrideHistory, loop.dosingDecisionStore, loop.alertStore, loop.deviceLog)
    }

    /// Keeps ended overrides for the algorithm's lookback (about 18 h); the phone keeps 90 days.
    /// The window is a LoopKit static that only the phone's `TemporaryPresetsManager` sets otherwise.
    static func makeOverrideHistory() -> TemporaryScheduleOverrideHistory {
        TemporaryScheduleOverrideHistory.relevantTimeWindow = .hours(24)
        return TemporaryScheduleOverrideHistory()
    }
}
