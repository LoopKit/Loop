//
//  PodLoanWatchController+Resume.swift
//  WatchApp Extension
//
//  Bringing a live loan back after the app dies or the watch reboots, the way the phone
//  resumes after its own relaunch. What cannot be rebuilt falls back to a recovered drain.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController {

    /// At .userInitiated with a background assertion: at the queue's own QoS a freshly powered
    /// watch can stall the rebuild for many seconds.
    func resumeIfNeeded() {
        let rebuild = DispatchWorkItem(qos: .userInitiated, flags: .enforceQoS) {
            guard let saved = self.pendingResumeState else { return }
            self.pendingResumeState = nil
            self.resumeSavedLoanOnQueue(saved)
        }
        queue.async(execute: rebuild)
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Sport Mode resume") { expired in
            if !expired { rebuild.wait() }
        }
    }

    /// Every exit from the rebuild ends here, so the UI never sits on a finished resume.
    func endResuming() {
        loanActiveMirrorLock.lock()
        _resumingMirror = false
        loanActiveMirrorLock.unlock()
        notifyUI()
    }

    /// Settings first, then the pump manager; either unreadable degrades to a recovered drain.
    func resumeSavedLoanOnQueue(_ savedState: PumpManager.RawStateValue) {
        defer { endResuming() }

        // Before anything can fail: the phone still leaves the alarms here until the records land.
        let alertSettings = persisted.grantedSettings?.glucoseAlertSettings
        Task { @MainActor [loopManager] in loopManager.configureGlucoseAlerts(from: alertSettings) }

        guard let payload = persisted.grantedSettings,
              let settings = Self.decodeTherapySettings(raw: payload.therapySettingsRaw, supplement: payload.supplementRaw),
              settings.basalRateSchedule != nil else {
            pumpStateStore.wrappedValue = nil
            updateState { $0.grantedSettings = nil }
            phase = .recoveredDrain
            issueSessionEndedAlert()
            SportLog.event("loan", "RESUME failed — therapy settings unreadable; falling back to a recovered drain")
            return
        }

        SportLog.event("loan", "RESUME: building the pump manager from saved state")
        guard let manager = watchPumpManager(rawValue: savedState) else {
            pumpStateStore.wrappedValue = nil
            updateState { $0.grantedSettings = nil }
            phase = .recoveredDrain
            issueSessionEndedAlert()
            SportLog.event("loan", "RESUME failed — saved pump state unreadable (or saved before it carried its manager's identifier); falling back to a recovered drain")
            return
        }
        SportLog.event("loan", "RESUME: pump manager built")
        // The pod's total as this watch last read it, before anything reads the pod again.
        let lastReading = (manager as? PumpDeliveryOdometer)?.deliveredUnits

        // Off for longer than insulin's action time: the loan is stale and whatever another device gave
        // in that time cannot be timed, so the records go home and the watch does not resume.
        if let lastReading, now().timeIntervalSince(lastReading.at) > InsulinMath.defaultInsulinActivityDuration {
            // Built only to read the total: it connects at construction, so it lets the pod go.
            (manager as? ExclusiveDeviceControl)?.releaseControl()
            pumpStateStore.wrappedValue = nil
            updateState { $0.grantedSettings = nil }
            phase = .recoveredDrain
            issueSessionEndedAlert()
            SportLog.event("loan", String(format: "RESUME declined — the watch last read the pod %.1f h ago, past insulin's action time; records go home as a recovered hand-back",
                                          now().timeIntervalSince(lastReading.at) / 3600))
            return
        }

        loopManager.settings = settings
        loopManager.settingsProvider.history = payload.settingsHistory
        loopManager.restoreOverrideHistory()
        phoneSupportsInterimHandback = payload.supportsInterimHandback
        phoneSupportsOverrideRecords = payload.supportsOverrideRecords
        manager.pumpManagerDelegate = self
        manager.delegateQueue = queue
        pumpManager = manager

        // Through the property, so didSet updates the main-safe mirrors. The loop gets the pod only after
        // the check below: until then a cycle started by a reading finds no pod and does nothing.
        phase = .active
        onLoanActiveChanged?(true)

        // Seed the reconciliation stamp, or the first cycle refuses with "pump data too old".
        let lastSync = manager.lastSync
        Task { [loopManager] in
            if let lastSync { try? await loopManager.recordPumpEvents([], lastReconciliation: lastSync, replacePendingEvents: false) }
            // Before the first cycle: book what the pod delivered while this watch was off that its records cannot explain.
            await self.bookInsulinGivenWhileOff(manager: manager, lastReading: lastReading)
            self.queue.async {
                // The loan may have ended while the check ran.
                guard self.phase == .active, self.pumpManager === manager else { return }
                loopManager.pumpManager = manager
                loopManager.updateDisplayState()
                // As stock at launch: a cycle now, not at the next reading.
                loopManager.checkPumpDataAndLoop()
            }
        }
        SportLog.event("loan", "RESUMED — epoch \(epoch ?? -1) rebuilt from saved pod state after a relaunch (stock relaunch) · \(RuntimeStateLog.snapshot())")
    }

    /// The pod's total now against its total when this watch last read it, with what the watch's own
    /// records and the schedule explain; the rest, in practice a phone's doses while the watch was off,
    /// is booked. One read; if the pod does not answer, the check is skipped and logged.
    func bookInsulinGivenWhileOff(manager: PumpManager, lastReading: (units: Double, at: Date)?) async {
        guard let odometer = manager as? PumpDeliveryOdometer, let last = lastReading else {
            SportLog.event("loan", "resume check SKIPPED — no earlier pod total to compare against")
            return
        }
        let read = await odometer.refreshDeliveredUnits()
        guard read, let reading = odometer.deliveredUnits, reading.at > last.at, reading.units >= last.units else {
            SportLog.event("loan", "resume check SKIPPED — the pod did not answer with a newer total")
            return
        }
        guard let booked = await bookInsulinNotInRecords(from: last, to: reading, records: journal.doseRecords(),
                                                        pulseUnits: odometer.deliveryPulseUnits,
                                                        insulinType: manager.status.insulinType, context: "resume") else { return }
        let at = self.now()
        queue.async {
            self.startNote = (at, String(format: NSLocalizedString("%.2f U the watch had no record of — counted as insulin on board", comment: "Glance: unexplained insulin booked at takeover (1: units)"), booked))
            self.notifyUI()
        }
    }

    /// For a session that cannot resume: records may not have reached the phone yet.
    func issueSessionEndedAlert() {
        let title = NSLocalizedString("Sport Mode Ended", comment: "Watch alert title on relaunch after the app died mid-loan")
        let body = NSLocalizedString("The watch app restarted. Insulin and carb records may not be on the phone yet.", comment: "Watch alert body on relaunch after the app died mid-loan")
        Task { @MainActor in
            loopManager.issueAlert(Alert(
                identifier: Alert.Identifier(managerIdentifier: "PodLoan", alertIdentifier: "sessionEnded"),
                foregroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                backgroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                trigger: .immediate))
        }
    }
}
