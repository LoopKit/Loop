//
//  PodLoanWatchController+Delegates.swift
//  WatchApp Extension
//
//  Part of PodLoanWatchController (see PodLoanWatchController.swift). The pump-host duties: PumpManagerDelegate, PumpManagerStatusObserver, DeviceManagerDelegate.
//
//  For the length of a loan this controller is the pod's host: everything the phone's app would
//  do for the pump manager, it does. The one duty with teeth is the pump-event report, which
//  writes the insulin book AND mints the journal events, in that order.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import OmnipodKit
import WatchKit
import os.log

extension PodLoanWatchController: PumpManagerDelegate {
    /// The pod's raw state is written to defaults on EVERY update. Its presence under
    /// `Keys.pumpState` is what tells the next launch the loan was live, which is why clearing it
    /// is part of `teardownPump` rather than an afterthought.
    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        defaults.set(pumpManager.rawState, forKey: Keys.pumpState)
    }

    /// Book first, complete, then journal.
    ///
    /// The completion must be called promptly: the stock storage path blocks its session queue on
    /// it. On a failed write nothing is acked and nothing is journalled — the pod keeps the doses
    /// and re-reports them on its next session, so refusing loses nothing, while journalling an
    /// event whose dose is not in the book would put the wire ahead of the truth.
    ///
    /// An EMPTY report still goes through. It carries `lastReconciliation`, and a status read that
    /// found nothing new is exactly what advances the recency gate dosing is allowed under.
    func pumpManager(_ pumpManager: PumpManager, hasNewPumpEvents events: [NewPumpEvent], lastReconciliation: Date?, replacePendingEvents: Bool, completion: @escaping (Error?) -> Void) {
        let loopManager = self.loopManager
        Task {
            do {
                try await loopManager.recordPumpEvents(events, lastReconciliation: lastReconciliation, replacePendingEvents: replacePendingEvents)
                completion(nil)
                self.queue.async { self.journalPumpEvents(events) }
            } catch {
                SportLog.event("book", "** pump events NOT stored — \(String(describing: error)) — \(events.count) event(s) held back by the pod for the next report **")
                completion(error)
            }
        }
    }

    /// The wrist keeps no reservoir history, so the reading is handed straight back and declared
    /// NOT continuous — nothing downstream may treat it as a series it can interpolate across.
    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date, completion: @escaping (Swift.Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) -> Void) {
        struct SimpleReservoirValue: ReservoirValue {
            let startDate: Date
            let unitVolume: Double
        }
        completion(.success((newValue: SimpleReservoirValue(startDate: date, unitVolume: units),
                             lastValue: nil, areStoredValuesContinuous: false)))
    }

    /// The watch's own dose store decides how far back the pod should re-report from, exactly as
    /// the phone's does — the loan seeds that store, so the boundary is already in the right place.
    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        return loopManager.doseStore.pumpEventQueryAfterDate
    }

    /// Nothing to do: the wrist's cycle is driven by CGM readings and its own timers, not by the
    /// pod's heartbeat.
    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
    }

    /// No. Background runtime on the watch comes from the workout keepalive, not from pod BLE
    /// wakes, so the pump is never asked to carry one.
    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool {
        return false
    }

    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {
        os_log("PumpManager error: %{public}@", log: log, type: .error, String(describing: error))
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {
        loopManager.doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
    }

    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        os_log("Pump clock adjusted by %f", log: log, type: .default, adjustment)
    }

    /// Refused. The basal schedule is frozen to the grant's snapshot for the whole loan, and the
    /// phone's reconciliation of this loan computes expected insulin against that same frozen
    /// schedule — a mid-loan change would make its arithmetic wrong with nothing to notice it.
    func pumpManager(_ pumpManager: PumpManager, didRequestBasalRateScheduleChange basalRateSchedule: BasalRateSchedule, completion: @escaping (Error?) -> Void) {
        completion(WatchLoopError.configurationError("basal schedule changes are phone-only"))
    }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        os_log("PumpManager will deactivate", log: log, type: .default)
    }

    func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager) {
        os_log("Pump was replaced", log: log, type: .default)
    }

    /// The wrist has no trusted second clock to compare against, so it never asserts an offset;
    /// a pod clock adjustment is logged above rather than corrected here.
    var detectedSystemTimeOffset: TimeInterval {
        return 0
    }

    /// Only a live loan counts. A watch mid-takeover or mid-drain is not dosing automatically.
    var automaticDosingEnabled: Bool {
        return phase == .active
    }

    /// What the pod should say about the running program, judged against the OVERRIDE-APPLIED
    /// basal schedule. Netting against the raw schedule while an override is up reports "neutral"
    /// with the pod running well above the intended basal.
    var automatedTreatmentState: AutomatedTreatmentState? {
        guard phase == .active else { return nil }
        guard let dose = loopManager.runningTempBasal() else { return .neutralNoOverride }
        let scheduled = loopManager.basalRateScheduleApplyingOverrideHistory?.value(at: now()) ?? 0
        if dose.unitsPerHour == 0 { return .minimumDelivery }
        if dose.unitsPerHour > scheduled { return .increasedInsulin }
        if dose.unitsPerHour < scheduled { return .decreasedInsulin }
        return .neutralNoOverride
    }
}

extension PodLoanWatchController: PumpManagerStatusObserver {
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        os_log("Pump status: %{public}@", log: log, type: .default, String(describing: status.basalDeliveryState))
    }
}

extension PodLoanWatchController: DeviceManagerDelegate {
    /// Forwards the `manager` itself, not just the device identifier: this delegate is shared by
    /// the CGM and the pump, and attributing by device name alone files pod errors under a CGM
    /// heading.
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        loopManager.deviceManager(manager, logEventForDeviceIdentifier: deviceIdentifier, type: type, message: message, completion: completion)
    }

    func issueAlert(_ alert: LoopKit.Alert) {
        loopManager.issueAlert(alert)
    }

    func retractAlert(identifier: LoopKit.Alert.Identifier) {
        loopManager.retractAlert(identifier: identifier)
    }

    func doesIssuedAlertExist(identifier: LoopKit.Alert.Identifier) async throws -> Bool {
        try await loopManager.doesIssuedAlertExist(identifier: identifier)
    }

    func lookupAllUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        try await loopManager.lookupAllUnretracted(managerIdentifier: managerIdentifier)
    }

    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        try await loopManager.lookupAllUnacknowledgedUnretracted(managerIdentifier: managerIdentifier)
    }

    func recordRetractedAlert(_ alert: LoopKit.Alert, at date: Date) {
        loopManager.recordRetractedAlert(alert, at: date)
    }
}

extension LoanGrant {
    /// Re-stamp a stored credential with a new epoch and a fresh lease, for a seize.
    ///
    /// A dormant grant is issued already expired — the phone sets its `expiresAt` to its issue
    /// time by contract — so it can never be activated verbatim: its lease would be long gone by
    /// the first ladder read. The lease bounds the HANDSHAKE, not the credential.
    func withEpoch(_ newEpoch: Int, leaseUntil: Date) -> LoanGrant {
        LoanGrant(epoch: newEpoch, expiresAt: leaseUntil, pumpManagerRawState: pumpManagerRawState,
                  podAddress: podAddress, therapySettingsRaw: therapySettingsRaw,
                  settingsTimeZoneID: settingsTimeZoneID, doseHistory: doseHistory,
                  supportsInterimHandback: supportsInterimHandback,
                  supportsOverrideRecords: supportsOverrideRecords,
                  integralRetrospectiveCorrectionEnabled: integralRetrospectiveCorrectionEnabled,
                  phoneClosedLoopEnabled: phoneClosedLoopEnabled, carbHistory: carbHistory,
                  glucoseHistory: glucoseHistory, predictionSnapshot: predictionSnapshot,
                  activeOverrideRaw: activeOverrideRaw,
                  therapySettingsSupplementRaw: therapySettingsSupplementRaw,
                  lastLoopCompleted: lastLoopCompleted)
    }
}
