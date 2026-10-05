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
import os.log

/// Stock's `AlertStore` logs through the phone's `DiagnosticLog`, which forwards to logging
/// services the watch does not have; os_log under the same subsystem stands in.
typealias DiagnosticLog = OSLog

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
            overrideHistory: stores.overrideHistory,
            dosingDecisionStore: stores.dosingDecisionStore,
            alertStore: stores.alertStore,
            deviceLog: stores.deviceLog
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
    static func makeStores() async -> (doseStore: DoseStore, glucoseStore: GlucoseStore, carbStore: CarbStore, overrideHistory: TemporaryScheduleOverrideHistory, dosingDecisionStore: DosingDecisionStore, alertStore: AlertStore, deviceLog: PersistentDeviceLog)? {
        guard let documents = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            SportLog.event("session", "STACK UNAVAILABLE — no documents directory")
            return nil
        }

        let storeName = "com.loopkit.LoopKit.StockLoop.Modelv6"
        let cacheStore = PersistenceController(directoryURL: documents.appendingPathComponent(storeName), isReadOnly: false)
        SportLog.event("session", "stack: store \(storeName)")
        let provenanceIdentifier = HKSource.default().bundleIdentifier

        // One override history: a second would dose unscaled while the screens showed the override.
        let overrideHistory = makeOverrideHistory()

        // As stock `LoopAppManager` builds them, with the phone's `LoopLocalCacheDurationDays`.
        let localCacheDuration = Bundle.main.localCacheDuration

        SportLog.event("session", "stack: opening stores")
        let doseStore = await DoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            provenanceIdentifier: provenanceIdentifier
        )

        let glucoseStore = await GlucoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            provenanceIdentifier: provenanceIdentifier
        )

        let carbStore = CarbStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            provenanceIdentifier: provenanceIdentifier
        )

        // As stock `LoopAppManager` builds it.
        let dosingDecisionStore = DosingDecisionStore(store: cacheStore, expireAfter: localCacheDuration)

        // As stock `AlertManager` builds it, in the same place.
        let alertStoreDirectory = documents.appendingPathComponent("AlertStore")
        do {
            try FileManager.default.createDirectory(at: alertStoreDirectory, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        } catch {
            SportLog.event("session", "alert store directory NOT created — \(error.localizedDescription)")
        }
        let alertStore = AlertStore(storageDirectoryURL: alertStoreDirectory, expireAfter: Bundle.main.localCacheDuration)

        // As stock `LoopAppManager` builds it, in the same place.
        let deviceLogDirectory = documents.appendingPathComponent("DeviceLog")
        do {
            try FileManager.default.createDirectory(at: deviceLogDirectory, withIntermediateDirectories: true)
        } catch {
            SportLog.event("session", "STACK UNAVAILABLE — device log directory not created: \(error.localizedDescription)")
            return nil
        }
        let deviceLog = PersistentDeviceLog(storageFile: deviceLogDirectory.appendingPathComponent("Storage.sqlite"),
                                            maxEntryAge: Bundle.main.localCacheDuration)

        SportLog.event("session", "stack: stores open")
        return (doseStore, glucoseStore, carbStore, overrideHistory, dosingDecisionStore, alertStore, deviceLog)
    }

    /// Keeps ended overrides for the algorithm's lookback (about 18 h); the phone keeps 90 days.
    /// The window is a LoopKit static that only the phone's `TemporaryPresetsManager` sets otherwise.
    static func makeOverrideHistory() -> TemporaryScheduleOverrideHistory {
        TemporaryScheduleOverrideHistory.relevantTimeWindow = .hours(24)
        return TemporaryScheduleOverrideHistory()
    }
}
