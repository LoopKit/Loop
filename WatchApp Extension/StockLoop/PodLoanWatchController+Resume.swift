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

        // Off for longer than insulin's action time: the loan is stale and whatever another device gave
        // in that time cannot be timed, so the records go home and the watch does not resume.
        if let last = persisted.ledgerLast, now().timeIntervalSince(last.at) > InsulinMath.defaultInsulinActivityDuration {
            // Built only to read the total: it connects at construction, so it lets the pod go.
            (manager as? ExclusiveDeviceControl)?.releaseControl()
            pumpStateStore.wrappedValue = nil
            updateState { $0.grantedSettings = nil }
            phase = .recoveredDrain
            issueSessionEndedAlert()
            SportLog.event("loan", String(format: "RESUME declined — the watch last read the pod %.1f h ago, past insulin's action time; records go home as a recovered hand-back",
                                          now().timeIntervalSince(last.at) / 3600))
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

        // Through the property, so didSet updates the main-safe mirrors.
        phase = .active
        onLoanActiveChanged?(true)

        SportLog.event("loan", "RESUMED — epoch \(epoch ?? -1) rebuilt from saved pod state after a relaunch (stock relaunch) · \(RuntimeStateLog.snapshot())")

        // Rows 12, 13 and 19: `LoanControl` decides what a watch back from off does.
        switch LoanControl.decide(LoanControl.Situation(device: .watch, trigger: .backFromOff)) {
        case .query(let wait, let onSilence):
            // The wait for an answer starts when the question can actually go out (10-17 21:37: asked
            // before the link had started, the question was lost and silence was read as no phone).
            whenLinkActivated { [weak self] in
                guard let self = self, self.phase == .active, self.pumpManager === manager else { return }
                self.sendHoldsPodStatusReport(reason: "back from off — asking the phone before looping")
                self.schedule(after: wait.seconds, label: "resume-ask") { [weak self] in
                    guard let self = self else { return }
                    // A phone that holds the pod answers with the stop, which stands this watch aside.
                    guard self.phase == .active, self.pumpManager === manager else {
                        SportLog.event("loan", "resume: stood aside — the phone holds the pod")
                        return
                    }
                    SportLog.event("loan", "resume: no word that the phone holds the pod")
                    if case .carryOn = LoanControl.afterQuery(.silence, onSilence: onSilence) { self.handPodToLoop(manager) }
                }
            }
        default:
            handPodToLoop(manager)
        }
    }

    /// Nothing doses before the pod reports: after a relaunch the loop's recency check refuses until the
    /// first report, and that report closes the ledger's open window, booking what the pod delivered
    /// while this watch was off, before it completes.
    func handPodToLoop(_ manager: PumpManager) {
        loopManager.pumpManager = manager
        loopManager.updateDisplayState()
        // As at any launch: a cycle now, not at the next reading.
        loopManager.checkPumpDataAndLoop()
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
