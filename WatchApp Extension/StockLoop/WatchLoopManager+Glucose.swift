//
//  WatchLoopManager+Glucose.swift
//  WatchApp Extension
//
//  The loop's reaction to readings the watch's `LoopDataManager` has stored: its own G7 reading
//  (from stock's `WatchCGMHost`) and, during a loan, the phone's relayed reading. Both run right after
//  the store's write, in arrival order.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import WatchConnectivity
import os.log

extension WatchLoopManager {
    /// The watch's own reading, from stock's `WatchCGMHost`, once `LoopDataManager` has stored it. As
    /// stock `DeviceDataManager.cgmManager(_:hasNew:)`: the glucose alerts see every delivered reading,
    /// and a cycle runs, at most every 4.2 minutes, only when the store took a reading it lacked.
    func didStoreDirectGlucose(_ samples: [NewGlucoseSample], storedNew: Bool) {
        guard let latest = samples.max(by: { $0.date < $1.date }) else { return }
        noteGlucoseSource(directG7: true)
        evaluateGlucoseAlerts(samples)

        let mgdl = Int(latest.quantity.doubleValue(for: .milligramsPerDeciliter).rounded())
        SportLog.event("glucose", "G7 reading \(mgdl) mg/dL, \(Int(self.now().timeIntervalSince(latest.date))) s old"
            + (samples.count > 1 ? ", with \(samples.count - 1) backfilled" : "") + (storedNew ? "" : ", already stored"))

        let now = self.now()
        if storedNew, claimCGMLoopTrigger(at: now) {
            log.default("Triggering loop from new CGM data at %{public}@", String(describing: now))
            checkPumpDataAndLoop()
        }
    }

    /// Stock `DeviceDataManager.receivedUnreliableCGMReading`: with the sensor's data unreliable, a
    /// temp above the scheduled basal is cancelled. Only while the watch holds the pod.
    func receivedUnreliableGlucose() {
        onLane {
            guard case .tempBasal(let tempBasal)? = self.pumpManager?.status.basalDeliveryState,
                  let scheduledBasalRate = self.settingsProvider.settings.basalRateSchedule?.value(at: tempBasal.startDate),
                  tempBasal.unitsPerHour > scheduledBasalRate else { return }
            SportLog.event("cgm", "sensor data unreliable; cancelling the high temp basal")
            await self.cancelActiveTempBasal(reason: .unreliableCGMData)
        }
    }

    /// Newest stored reading from either source; for the watch's own radio use `lastGlucoseSourceStamps.direct`.
    var latestGlucoseAge: TimeInterval? {
        return glucoseStore.latestGlucose.map { self.now().timeIntervalSince($0.startDate) }
    }

    /// The phone's reading during a loan, once `LoopDataManager` stored it as a gap-filler while the
    /// wrist owns the alarms. It goes to the glucose alerts too, as the watch's own readings do, unless
    /// the store already holds a newer one; it runs a cycle only once a pod is held.
    func didStorePhoneGlucose(_ sample: NewGlucoseSample) {
        if let latest = glucoseStore.latestGlucose?.startDate, latest > sample.date { return }
        let mgdl = Int(sample.quantity.doubleValue(for: .milligramsPerDeciliter))
        // Only a reading that actually filled a gap counts as the phone having delivered.
        noteGlucoseSource(directG7: false)
        evaluateGlucoseAlerts([sample])
        SportLog.event("glucose", "phone reading \(mgdl) mg/dL, \(Int(self.now().timeIntervalSince(sample.date))) s old, fills a gap in the watch's own readings")
        if claimCGMLoopTrigger(at: now()) {
            checkPumpDataAndLoop()
        }
    }


}

/// Alerts from the pump the watch holds, and from the wrist's glucose alerts; and the pump's device log.
extension WatchLoopManager: AlertIssuer, PersistedAlertStore {
    /// Device-log sink for the pump manager. While the watch holds the pod every line goes to stock's
    /// device log, as stock `DeviceDataManager` writes it (the watch has a pump only during a loan).
    /// The CGM's lines are `WatchCGMHost`'s.
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        log.default("Device %{public}@: %{public}@", deviceIdentifier ?? "unknown", message)

        if let deviceLog, manager is PumpManager || pumpManager != nil {
            deviceLog.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: deviceIdentifier, type: type, message: message, completion: completion)
        } else {
            completion?(nil)
        }
    }

    // MARK: - Alerts
    // Presented on the wrist, and recorded in stock's `AlertStore` as stock's `AlertManager`
    // records them: an issue only while the watch holds the pod, so the store holds the loans'
    // alerts; an acknowledgement or retraction whenever its record is there. The lookups answer
    // from the store, as stock's do.

    /// The watch is the only device hearing the pump during a loan.
    func issueAlert(_ alert: LoopKit.Alert) {
        SportLog.event("alert", "alert \(alert.identifier.value) issued: \(alert.backgroundContent.title)")
        WatchAlertPresenter.present(alert)
        guard pumpManager != nil else { return }
        recordAlert { await $0.recordIssued(alert: alert) }
    }

    /// Withdraw it. A driver retracts when the condition clears, and an alarm left standing after
    /// the pod recovered costs the next one its weight.
    func retractAlert(identifier: LoopKit.Alert.Identifier) {
        SportLog.event("alert", "alert \(identifier.value) retracted")
        WatchAlertPresenter.retract(identifier)
        recordAlert { try? await $0.recordRetraction(of: identifier) }
    }

    /// Every alert from one manager still standing on the wrist, withdrawn.
    func retractStandingAlerts(managerIdentifier: String) async {
        let standing = (try? await lookupAllUnretracted(managerIdentifier: managerIdentifier)) ?? []
        for persisted in standing { await retractAlert(identifier: persisted.alert.identifier) }
    }

    /// The wrist's OK or dismissal, recorded as stock `AlertManager.acknowledgeAlert` records it,
    /// whatever the alert's manager made of it.
    func recordAlertAcknowledgement(_ identifier: LoopKit.Alert.Identifier) {
        recordAlert { try? await $0.recordAcknowledgement(of: identifier) }
    }

    func doesIssuedAlertExist(identifier: LoopKit.Alert.Identifier) async throws -> Bool {
        guard let alertStore = await settledAlertStore() else { return false }
        return try await !alertStore.lookupAllMatching(identifier: identifier).isEmpty
    }

    func lookupAllUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        guard let alertStore = await settledAlertStore() else { return [] }
        return try await alertStore.lookupAllUnretracted(managerIdentifier: managerIdentifier).compactMap(Self.persistedAlert)
    }

    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        guard let alertStore = await settledAlertStore() else { return [] }
        return try await alertStore.lookupAllUnacknowledgedUnretracted(managerIdentifier: managerIdentifier).compactMap(Self.persistedAlert)
    }

    func recordRetractedAlert(_ alert: LoopKit.Alert, at date: Date) {
        log.default("Retracted alert recorded: %{public}@", alert.identifier.value)
        guard pumpManager != nil else { return }
        recordAlert { try? await $0.recordRetractedAlert(alert, at: date) }
    }

    /// Runs after every record asked for before it.
    func recordAlert(_ record: @escaping (AlertStore) async -> Void) {
        guard let alertStore else { return }
        let previous = alertRecords
        alertRecords = Task {
            await previous?.value
            await record(alertStore)
        }
    }

    /// The store, once every record asked for so far has landed.
    func settledAlertStore() async -> AlertStore? {
        await alertRecords?.value
        return alertStore
    }

    /// Stock `AlertManager`'s mapping for the lookups.
    static func persistedAlert(_ stored: StoredAlert) throws -> PersistedAlert? {
        guard let alert = try LoopKit.Alert(from: stored, adjustedForStorageTime: false) else { return nil }
        return PersistedAlert(alert: alert, issuedDate: stored.issuedDate, retractedDate: stored.retractedDate,
                              acknowledgedDate: stored.acknowledgedDate)
    }
}

extension WatchLoopManager: DoseStoreDelegate {
    /// The store nets basal-relative doses against this, so it must be the GRANT's schedule —
    /// the same one the algorithm runs on — and not anything the wrist derived locally.
    /// Asked from the store's own queue; the provider answers there.
    nonisolated func scheduledBasalHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        try await settingsProvider.getBasalHistory(startDate: start, endDate: end)
    }

    /// Deliberately empty. Stock uses this to trigger a remote upload; the wrist has no upload
    /// services, and its pump events travel home in the loan journal instead.
    nonisolated func doseStoreHasUpdatedPumpEventData(_ doseStore: DoseStore) {
    }
}
