//
//  StockLoopStack.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  Assembles the watch's stores, override history and WatchLoopManager, and restores the CGM
//  manager the phone's configuration last built. The pump appears only with a loan.
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

    /// Stores, then the loop manager, then the CGM, whose delegate queue is the loop's device
    /// queue. nil: the stores could not be opened, so no Sport Mode.
    static func assemble() async -> Stack? {
        SportLog.event("session", "stack: assembling")
        guard let stores = await makeStores() else { return nil }

        let loopManager = WatchLoopManager(
            doseStore: stores.doseStore,
            glucoseStore: stores.glucoseStore,
            carbStore: stores.carbStore,
            overrideHistory: stores.overrideHistory
        )

        // The phone's next context brings a configuration if nothing was saved.
        if let saved = loopManager.cgmManagerState.wrappedValue, let restored = watchCGMManager(rawValue: saved) {
            loopManager.installCGMManager(restored, builtFrom: saved[WatchLoopManager.builtFromKey] as? [String: Any])
            SportLog.event("cgm", "CGM manager RESTORED (\(restored.pluginIdentifier))")
        } else {
            SportLog.event("cgm", "no saved CGM manager — the phone's next context brings its configuration")
        }
        SportLog.event("session", "stack: cgm wired")

        return Stack(loopManager: loopManager)
    }

    /// The watch's own stores. The directory name carries the LoopKit model version, since this
    /// and the stock watch app share a bundle id. Not read-only: this extension owns them.
    static func makeStores() async -> (doseStore: DoseStore, glucoseStore: GlucoseStore, carbStore: CarbStore, overrideHistory: TemporaryScheduleOverrideHistory)? {
        guard let documents = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            SportLog.event("session", "STACK UNAVAILABLE — no documents directory")
            return nil
        }

        let storeName = "com.loopkit.LoopKit.StockLoop.Modelv6"
        let cacheStore = PersistenceController(directoryURL: documents.appendingPathComponent(storeName), isReadOnly: false)
        SportLog.event("session", "stack: store \(storeName)")
        let provenanceIdentifier = HKSource.default().bundleIdentifier

        // One override history: a second would dose unscaled while the screens showed the override.
        let overrideHistory = TemporaryScheduleOverrideHistory()

        SportLog.event("session", "stack: opening stores")
        let doseStore = await DoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            provenanceIdentifier: provenanceIdentifier
        )

        let glucoseStore = await GlucoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(4),
            provenanceIdentifier: provenanceIdentifier
        )

        let carbStore = CarbStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: .hours(24),
            provenanceIdentifier: provenanceIdentifier
        )

        SportLog.event("session", "stack: stores open")
        return (doseStore, glucoseStore, carbStore, overrideHistory)
    }
}
