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

    /// At .userInitiated with a background assertion: at a lower QoS a freshly powered
    /// watch can stall the rebuild for many seconds.
    func resumeIfNeeded() {
        let rebuild = DispatchWorkItem(qos: .userInitiated, flags: .enforceQoS) {
            guard let saved = self.pendingResumeState else { return }
            self.pendingResumeState = nil
            self.resumeSavedLoan(saved)
        }
        DispatchQueue.main.async(execute: rebuild)
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Sport Mode resume") { expired in
            if !expired { rebuild.wait() }
        }
    }

    /// Ends the check a watch back from off makes before looping: at the hand to Loop, at any exit
    /// that does not resume, and when the loan ends (the phone's stop). The glance shows "Checking
    /// with your iPhone…" until then.
    func endResuming() {
        isResuming = false
        notifyUI()
    }

    /// Settings first; the pump manager after the phone has been asked. Either unreadable degrades to a
    /// recovered drain.
    func resumeSavedLoan(_ savedState: PumpManager.RawStateValue) {
        // Before anything can fail: the phone still leaves the alarms here until the records land.
        let alertSettings = persisted.grantedSettings?.glucoseAlertSettings
        loopManager.configureGlucoseAlerts(from: alertSettings)

        guard let payload = persisted.grantedSettings,
              let settings = Self.decodeTherapySettings(raw: payload.therapySettingsRaw, supplement: payload.supplementRaw),
              settings.basalRateSchedule != nil else {
            pumpStateStore.wrappedValue = nil
            updateState { $0.grantedSettings = nil }
            phase = .recoveredDrain
            issueSessionEndedAlert()
            SportLog.event("loan", "resume failed: therapy settings unreadable; sending the records home instead")
            endResuming()
            return
        }

        // Off for longer than insulin's action time: the loan is stale and whatever another device gave
        // in that time cannot be timed, so the records go home and the watch does not resume.
        if let last = persisted.ledgerLast, now().timeIntervalSince(last.at) > InsulinMath.defaultInsulinActivityDuration {
            pumpStateStore.wrappedValue = nil
            updateState { $0.grantedSettings = nil }
            phase = .recoveredDrain
            issueSessionEndedAlert()
            SportLog.event("loan", String(format: "resume declined: the pod was last read %.1f h ago, past insulin's action time; sending the records home",
                                          now().timeIntervalSince(last.at) / 3600))
            endResuming()
            return
        }

        loopManager.settings = settings
        loopManager.settingsProvider.history = payload.settingsHistory
        loopManager.restoreOverrideHistory()

        // Staged before ACTIVE, which starts them as a grant's would.
        LoanRemoteUploads.shared.stage(services: (payload.serviceConfigurations ?? []).compactMap(SharedDeviceConfiguration.init(propertyList:)),
                                       phoneCGMUploadsGlucose: payload.phoneCGMUploadsGlucose)

        // Through the property, so its observers run.
        phase = .active
        onLoanActiveChanged?(true)

        SportLog.event("loan", "resumed loan \(epoch ?? -1) after a relaunch; asking the phone before rebuilding the pump manager")

        // Rows 12, 13 and 19: `LoanControl` decides what a watch back from off does.
        let resumedEpoch = epoch
        switch LoanControl.decide(LoanControl.Situation(device: .watch, trigger: .backFromOff)) {
        case .query(let wait, let onSilence):
            // The wait for an answer starts when the question can actually go out: a message sent before
            // the link has started is lost, and the silence would be read as no phone.
            whenLinkActivated { [weak self] in
                guard let self = self, self.phase == .active, self.epoch == resumedEpoch, self.pumpManager == nil else { return }
                self.sendHoldsPodStatusReport(reason: "back from off, asking before looping")
                self.schedule(after: wait.seconds, label: "resume-ask") { [weak self] in
                    guard let self = self else { return }
                    // A phone that holds the pod answers with the stop, which stands this watch aside.
                    guard self.phase == .active, self.epoch == resumedEpoch, self.pumpManager == nil else {
                        SportLog.event("loan", "stood aside after the resume: the phone holds the pod")
                        return
                    }
                    SportLog.event("loan", "the phone did not say it holds the pod after the resume")
                    if case .carryOn = LoanControl.afterQuery(.silence, onSilence: onSilence) { self.buildAndHandPodToLoop(savedState) }
                }
            }
        default:
            buildAndHandPodToLoop(savedState)
        }
    }

    /// The pump manager is built only once the check has passed: built, it reaches the pod by itself,
    /// which it must not do while the phone may be looping the pod. Unreadable, it degrades to a drain.
    func buildAndHandPodToLoop(_ savedState: PumpManager.RawStateValue) {
        guard let manager = watchPumpManager(rawValue: savedState) else {
            pumpStateStore.wrappedValue = nil
            updateState { $0.grantedSettings = nil }
            phase = .recoveredDrain
            onLoanActiveChanged?(false)
            issueSessionEndedAlert()
            SportLog.event("loan", "resume failed: saved pump state unreadable; sending the records home instead")
            endResuming()
            return
        }
        SportLog.event("loan", "pump manager rebuilt; handing the pod to the loop")
        manager.pumpManagerDelegate = self
        manager.delegateQueue = .main
        pumpManager = manager
        handPodToLoop(manager)
    }

    /// Nothing doses before the pod reports: after a relaunch the loop's recency check refuses until the
    /// first report, and that report closes the ledger's open window, booking what the pod delivered
    /// while this watch was off, before it completes.
    func handPodToLoop(_ manager: PumpManager) {
        endResuming()
        loopManager.pumpManager = manager
        loopManager.updateDisplayState()
        // As at any launch: a cycle now, not at the next reading.
        loopManager.checkPumpDataAndLoop()
    }

    /// For a session that cannot resume: records may not have reached the phone yet.
    func issueSessionEndedAlert() {
        let title = NSLocalizedString("Sport Mode Ended", comment: "Watch alert title on relaunch after the app died mid-loan")
        let body = NSLocalizedString("The watch app restarted and couldn't resume looping. Nothing is looping until your iPhone gets the watch's records and takes over.", comment: "Watch alert body on relaunch after the app died mid-loan")
        Task { @MainActor in
            loopManager.issueAlert(Alert(
                identifier: Alert.Identifier(managerIdentifier: "PodLoan", alertIdentifier: "sessionEnded"),
                foregroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                backgroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                trigger: .immediate))
        }
    }
}
