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
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController: PumpManagerDelegate {
    /// A driver released by a teardown can still report, when the release let its last command finish:
    /// the controller stays its delegate (the driver treats none as impossible) and drops what it says.
    func isCurrentDriver(_ manager: PumpManager) -> Bool {
        (manager as AnyObject) === (pumpManager as AnyObject?)
    }

    /// Saved on every update; its presence tells the next launch the loan was live.
    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        // The pod's handle is saved after the loan too: a release can still drop one that never connected.
        savePumpLocalState(of: pumpManager)
        guard isCurrentDriver(pumpManager) else { return }
        pumpStateStore.wrappedValue = pumpManager.watchRawValue
        reportPumpFaultOnce()
    }

    /// The phone hears of a fault once per loan, without waiting to be asked.
    func reportPumpFaultOnce() {
        guard pumpFaultDescription != nil, phase == .active, let current = epoch, faultReportedEpoch != current else { return }
        faultReportedEpoch = current
        sendHoldsPodStatusReport(reason: "the pod faulted")
    }

    /// Book, close the ledger's window, complete, then journal. On a failed write nothing is acked or
    /// journaled; the pod re-reports. An empty report still advances the recency gate. The window
    /// closes before the completion, so the cycle this report feeds sees anything it books.
    func pumpManager(_ pumpManager: PumpManager, hasNewPumpEvents events: [NewPumpEvent], lastReconciliation: Date?, replacePendingEvents: Bool, completion: @escaping (Error?) -> Void) {
        guard isCurrentDriver(pumpManager) else {
            SportLog.event("loan", "ignored \(events.count) pump event(s) from a released pod driver")
            completion(nil)
            return
        }
        let loopManager = self.loopManager
        let odometer = pumpManager as? PumpDeliveryOdometer
        let reading = odometer?.deliveredUnits
        let insulinType = pumpManager.status.insulinType
        Task {
            do {
                try await loopManager.recordPumpEvents(events, lastReconciliation: lastReconciliation, replacePendingEvents: replacePendingEvents)
                if let odometer, let reading {
                    await self.checkOwnPumpTotal(reading: reading, pulseUnits: odometer.deliveryPulseUnits, insulinType: insulinType)
                }
                completion(nil)
                DispatchQueue.main.async { self.journalPumpEvents(events) }
            } catch {
                SportLog.event("book", "could not store \(events.count) pump event(s); the pod reports them again: \(String(describing: error))")
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

    /// Runtime comes from the sensor's and the pod's own Bluetooth wakes.
    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool {
        return false
    }

    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {
        log.error("PumpManager error: %{public}@", String(describing: error))
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {
        loopManager.doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
    }

    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        log.default("Pump clock adjusted by %f", adjustment)
    }

    /// Refused: the schedule is frozen to the grant, and the phone's audit uses the same one.
    func pumpManager(_ pumpManager: PumpManager, didRequestBasalRateScheduleChange basalRateSchedule: BasalRateSchedule, completion: @escaping (Error?) -> Void) {
        // Basal schedule changes are the phone's; the closest stock error.
        completion(LoopError.configurationError(.basalRateSchedule))
    }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        log.default("PumpManager will deactivate")
    }

    func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager) {
        log.default("Pump was replaced")
    }

    /// No trusted second clock on the wrist.
    var detectedSystemTimeOffset: TimeInterval {
        return 0
    }

    /// Stock returns `dosingEnabled`; here, the wrist's loop switch during a live loan. A watch
    /// mid-takeover or mid-drain is not dosing automatically.
    var automaticDosingEnabled: Bool {
        return phase == .active && loopManager.closedLoopEnabled
    }

    /// Judged against the override-applied schedule. Simpler than stock's: only MockKit's phone UI
    /// reads this, and nothing reads it on the watch.
    var automatedTreatmentState: AutomatedTreatmentState? {
        guard phase == .active else { return nil }
        guard let dose = loopManager.pumpManager?.status.basalDeliveryState?.currentTempBasal else { return .neutralNoOverride }
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
            DispatchQueue.main.async {
                let pump = self.phase == .active ? self.pumpManager : nil
                continuation.resume(returning: pump?.pluginIdentifier == managerIdentifier ? pump : nil)
            }
        }
    }
}

extension PodLoanWatchController: PumpManagerStatusObserver {
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        guard isCurrentDriver(pumpManager) else { return }
        log.default("Pump status: %{public}@", String(describing: status.basalDeliveryState))
        // As stock `DeviceDataManager.pumpManager(_:didUpdate:oldStatus:)`.
        loopManager.doseStore.device = status.device
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
                  therapySettingsRaw: therapySettingsRaw,
                  settingsTimeZoneID: settingsTimeZoneID, doseHistory: doseHistory,
                  integralRetrospectiveCorrectionEnabled: integralRetrospectiveCorrectionEnabled,
                  glucoseBasedApplicationFactorEnabled: glucoseBasedApplicationFactorEnabled,
                  guardAndRunwayEnabled: guardAndRunwayEnabled,
                  volatilityBaseline: volatilityBaseline,
                  phoneClosedLoopEnabled: phoneClosedLoopEnabled, carbHistory: carbHistory,
                  glucoseHistory: glucoseHistory,
                  activeOverrideRaw: activeOverrideRaw,
                  therapySettingsSupplementRaw: therapySettingsSupplementRaw,
                  lastLoopCompleted: lastLoopCompleted,
                  glucoseAlertSettings: glucoseAlertSettings,
                  overrideHistoryRaw: overrideHistoryRaw,
                  settingsHistory: settingsHistory)
    }
}
