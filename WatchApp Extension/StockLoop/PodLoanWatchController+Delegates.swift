//
//  PodLoanWatchController+Delegates.swift
//  WatchApp Extension
//
//  The controller as the pod's host during a loan: PumpManagerDelegate, status observer and
//  DeviceManagerDelegate. The pump-event report writes the book, then the journal.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController: PumpManagerDelegate {
    /// Saved on every update; its presence tells the next launch the loan was live.
    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        pumpStateStore.wrappedValue = pumpManager.watchRawValue
        savePumpLocalState(of: pumpManager)
        reportPumpFaultOnce()
    }

    /// The phone hears of a fault once per loan, without waiting to be asked.
    func reportPumpFaultOnce() {
        guard pumpFaultDescription != nil, phase == .active, let current = epoch, faultReportedEpoch != current else { return }
        faultReportedEpoch = current
        sendHoldsPodStatusReport(reason: "pump fault")
    }

    /// Book, complete, then journal. On a failed write nothing is acked or journaled; the pod
    /// re-reports. An empty report still advances the recency gate.
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

    /// No reservoir history on the wrist; declared not continuous.
    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date, completion: @escaping (Swift.Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) -> Void) {
        struct SimpleReservoirValue: ReservoirValue {
            let startDate: Date
            let unitVolume: Double
        }
        completion(.success((newValue: SimpleReservoirValue(startDate: date, unitVolume: units),
                             lastValue: nil, areStoredValuesContinuous: false)))
    }

    /// The loan-seeded dose store sets the boundary, as on the phone.
    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        return loopManager.doseStore.pumpEventQueryAfterDate
    }

    /// Cycles run on CGM readings, not the pod's heartbeat.
    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
    }

    /// Runtime comes from the workout keepalive.
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

    /// Refused: the schedule is frozen to the grant, and the phone's audit uses the same one.
    func pumpManager(_ pumpManager: PumpManager, didRequestBasalRateScheduleChange basalRateSchedule: BasalRateSchedule, completion: @escaping (Error?) -> Void) {
        completion(WatchLoopError.configurationError("basal schedule changes are phone-only"))
    }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        os_log("PumpManager will deactivate", log: log, type: .default)
    }

    func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager) {
        os_log("Pump was replaced", log: log, type: .default)
    }

    /// No trusted second clock on the wrist.
    var detectedSystemTimeOffset: TimeInterval {
        return 0
    }

    /// Only a live loan counts. A watch mid-takeover or mid-drain is not dosing automatically.
    var automaticDosingEnabled: Bool {
        return phase == .active
    }

    /// Judged against the override-applied schedule.
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

extension PodLoanWatchController {
    /// The loaned pump, for an alert it raised, while the loan is live.
    func pumpAlertResponder(for managerIdentifier: String) async -> AlertResponder? {
        await withCheckedContinuation { continuation in
            queue.async {
                let pump = self.phase == .active ? self.pumpManager : nil
                continuation.resume(returning: pump?.pluginIdentifier == managerIdentifier ? pump : nil)
            }
        }
    }
}

extension PodLoanWatchController: PumpManagerStatusObserver {
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        os_log("Pump status: %{public}@", log: log, type: .default, String(describing: status.basalDeliveryState))
        loopManager.bolusStateDidChange(to: status.bolusState, from: oldStatus.bolusState, pumpManager: pumpManager)
    }
}

extension PodLoanWatchController: DeviceManagerDelegate {
    /// Forwards the manager: this delegate serves both the CGM and the pump.
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

    /// The pump's link is up and it has answered; arrives on the controller's queue.
    func deviceManagerControlDidBecomeReady(_ manager: DeviceManager) {
        guard (manager as AnyObject) === (pumpManager as AnyObject?) else { return }
        pumpControlDidBecomeReady()
    }
}

extension LoanGrant {
    /// A dormant grant is issued expired; a seize re-stamps the epoch and lease.
    func withEpoch(_ newEpoch: Int, leaseUntil: Date) -> LoanGrant {
        LoanGrant(epoch: newEpoch, expiresAt: leaseUntil, pumpConfiguration: pumpConfiguration,
                  podAddress: podAddress, therapySettingsRaw: therapySettingsRaw,
                  settingsTimeZoneID: settingsTimeZoneID, doseHistory: doseHistory,
                  supportsInterimHandback: supportsInterimHandback,
                  supportsOverrideRecords: supportsOverrideRecords,
                  integralRetrospectiveCorrectionEnabled: integralRetrospectiveCorrectionEnabled,
                  phoneClosedLoopEnabled: phoneClosedLoopEnabled, carbHistory: carbHistory,
                  glucoseHistory: glucoseHistory, predictionSnapshot: predictionSnapshot,
                  activeOverrideRaw: activeOverrideRaw,
                  therapySettingsSupplementRaw: therapySettingsSupplementRaw,
                  lastLoopCompleted: lastLoopCompleted,
                  glucoseAlertSettings: glucoseAlertSettings,
                  overrideHistoryRaw: overrideHistoryRaw,
                  settingsHistory: settingsHistory)
    }
}
