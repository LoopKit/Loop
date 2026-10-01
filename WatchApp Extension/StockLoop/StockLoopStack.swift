//
//  StockLoopStack.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  The single assembly point for the watch's own closed loop: three LoopKit stores, one
//  override history, the stock G7 CGM manager, and the WatchLoopManager that joins them.
//
//        G7CGMManager (stock G7SensorKit — parse, dedup, reliability gating, clamping)
//            │ CGMManagerDelegate, on WatchLoopManager.deviceQueue
//            ▼
//        WatchLoopManager — prediction, recommendation, and the enact seam
//            │ GlucoseStore ── CarbStore ── DoseStore, on one PersistenceController
//
//  Nothing here starts a radio or doses. StockLoopSession owns the assembled graph, and the
//  pump only appears when a loan is granted. The CGM is the exception: it is restored at launch
//  and runs whether or not a loan exists, because glucose is useful either way.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import G7SensorKit

enum StockLoopStack {
    /// The two long-lived objects. Both outlive any loan: the loop manager holds the stores and
    /// the insulin book, and the CGM manager holds the sensor identity across sessions.
    struct Stack {
        let cgmManager: G7CGMManager
        let loopManager: WatchLoopManager
    }

    /// Stores first, then the loop manager that owns them, then the CGM — the CGM's delegate
    /// callbacks arrive as soon as it is wired, so it must be last and its delegate queue is the
    /// loop's own device queue, not main.
    ///
    /// nil means the stores could not be opened, and the caller must treat that as no Sport Mode
    /// at all. Every step logs, because this runs at launch where a failure is otherwise visible
    /// only as an app that quietly does nothing.
    static func assemble() async -> Stack? {
        SportLog.event("session", "stack: assembling")
        guard let stores = await makeStores() else { return nil }

        let loopManager = WatchLoopManager(
            doseStore: stores.doseStore,
            glucoseStore: stores.glucoseStore,
            carbStore: stores.carbStore,
            overrideHistory: stores.overrideHistory
        )

        // Restoring a persisted sensor identity makes the stack auto-connect to THAT sensor, so
        // the past-its-life escape has to run on this launch path and not only on the live one.
        // An identity restored past its expiry never gets another chance to be dropped: the
        // watch auth-fails against a dead sensor indefinitely, taking zero direct readings,
        // invisible for as long as the phone's relay covers it. Discarding costs one acquisition.
        let cgmManager: G7CGMManager
        if let raw = UserDefaults.standard.dictionary(forKey: WatchLoopManager.cgmStateDefaultsKey),
           let restored = G7CGMManager(rawState: raw),
           !WatchLoopManager.persistedSensorIsPastLife(restored.sensorActivatedAt) {
            cgmManager = restored
            SportLog.event("cgm", "G7 state RESTORED — sensor \(restored.sensorName ?? "none"), activated \(restored.sensorActivatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown")")
        } else {
            cgmManager = G7CGMManager()
            if let raw = UserDefaults.standard.dictionary(forKey: WatchLoopManager.cgmStateDefaultsKey),
               let stale = G7CGMManager(rawState: raw) {
                UserDefaults.standard.removeObject(forKey: WatchLoopManager.cgmStateDefaultsKey)
                SportLog.event("cgm", "G7 state DISCARDED at launch — sensor \(stale.sensorName ?? "none") is past its life; acquisition will run instead of auth-failing against a dead identity")
            } else {
                SportLog.event("cgm", "G7 state fresh — no persisted sensor; acquisition will run (new install or pre-#101 build)")
            }
        }
        SportLog.event("session", "stack: cgm wired")
        cgmManager.delegateQueue = loopManager.deviceQueue
        cgmManager.cgmManagerDelegate = loopManager

        loopManager.g7Manager = cgmManager

        return Stack(cgmManager: cgmManager, loopManager: loopManager)
    }

    /// The watch's own stores, separate from the stock watch app's, on one PersistenceController.
    ///
    /// The directory name carries the LoopKit MODEL VERSION and must keep doing so. This build
    /// and the app it is derived from ship under the same bundle id, so installing one over the
    /// other inherits the other's store — and reading a row written under a different model
    /// through this model's accessors traps on the glucose INGEST path, which means every few
    /// minutes, with no way back into the app. Bumping the name strands the old directory, which
    /// is safe: everything in here is a cache, and the loan's durable record is the journal,
    /// which lives elsewhere.
    ///
    /// `isReadOnly: false` is deliberate. LoopCore opens its controller store read-only inside an
    /// app extension, because on the phone an extension is a sidecar to the app that owns the
    /// data; this extension owns its store outright, and inheriting that heuristic made every
    /// save a silent no-op.
    static func makeStores() async -> (doseStore: DoseStore, glucoseStore: GlucoseStore, carbStore: CarbStore, overrideHistory: TemporaryScheduleOverrideHistory)? {
        guard let documents = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            SportLog.event("session", "STACK UNAVAILABLE — no documents directory")
            return nil
        }

        let storeName = "com.loopkit.LoopKit.StockLoop.Modelv6"
        let cacheStore = PersistenceController(directoryURL: documents.appendingPathComponent(storeName), isReadOnly: false)
        SportLog.event("session", "stack: store \(storeName)")
        let provenanceIdentifier = HKSource.default().bundleIdentifier

        // ONE override history for the whole stack. It is both where an override is recorded and
        // what every schedule is resolved through, so a second instance would leave the wrist
        // dosing against unscaled basal, ISF and carb ratio while every screen showed the
        // override applied — which reads exactly like an IOB bug.
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
