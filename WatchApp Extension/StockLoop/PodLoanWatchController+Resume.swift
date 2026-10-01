//
//  PodLoanWatchController+Resume.swift
//  WatchApp Extension
//
//  Bringing a live loan back after the app dies or the watch reboots.
//
//  An ACTIVE loan with saved pod state resumes exactly the way the phone resumes after its own
//  relaunch: no fingerprint, no age cap, no confirmation, no notification. Everything that cannot
//  be rebuilt falls back to the data-first drain instead — the records go home as a recovered
//  hand-back and the pod session is never resurrected.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import OmnipodKit
import WatchKit
import os.log

extension PodLoanWatchController {

    /// Rebuild the loan, at `.userInitiated` on the loan queue, with a background assertion held
    /// until it finishes. On a watch that has just powered up the rebuild otherwise makes no
    /// progress for many seconds at the queue's own QoS, and can then be suspended part-built
    /// until the next Bluetooth wake.
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

    /// Leave the resuming state: drop the main-readable mirror, release anything the loop parked
    /// waiting for a pump manager, and repaint. Runs on every exit from the rebuild, successful or
    /// not, so the UI can never sit on a resume that has already ended.
    func endResuming() {
        loanActiveMirrorLock.lock()
        _resumingMirror = false
        loanActiveMirrorLock.unlock()
        _ = loopManager.endAwaitingPumpManager()
        notifyUI()
    }

    /// Rebuild from what was persisted: therapy settings FIRST, then the pump manager. A pump
    /// without a basal schedule cannot dose, so unreadable settings — or unreadable pod state —
    /// discard the saved session and degrade to a recovered drain rather than coming back
    /// half-built.
    func resumeSavedLoanOnQueue(_ savedState: PumpManager.RawStateValue) {
        defer { endResuming() }

        guard let payload = defaults.dictionary(forKey: Keys.grantedTherapySettings),
              let raw = payload["raw"] as? Data,
              let settings = Self.decodeTherapySettings(raw: raw, supplement: payload["supplement"] as? Data),
              settings.basalRateSchedule != nil else {
            defaults.removeObject(forKey: Keys.pumpState)
            defaults.removeObject(forKey: Keys.grantedTherapySettings)
            phase = .recoveredDrain
            issueSessionEndedAlert()
            SportLog.event("loan", "RESUME failed — therapy settings unreadable; falling back to a recovered drain")
            return
        }

        SportLog.event("loan", "RESUME: building the pump manager from saved state")
        guard let manager = OmniPumpManager(rawState: savedState) else {
            defaults.removeObject(forKey: Keys.pumpState)
            defaults.removeObject(forKey: Keys.grantedTherapySettings)
            phase = .recoveredDrain
            issueSessionEndedAlert()
            SportLog.event("loan", "RESUME failed — saved pod state unreadable; falling back to a recovered drain")
            return
        }
        SportLog.event("loan", "RESUME: pump manager built")
        loopManager.settings = settings
        phoneSupportsInterimHandback = payload["interim"] as? Bool ?? false
        phoneSupportsOverrideRecords = payload["overrideRecords"] as? Bool ?? false
        deliveredAtTakeover = defaults.object(forKey: Keys.deliveredAtTakeover) as? Double
        manager.pumpManagerDelegate = self
        manager.delegateQueue = queue
        pumpManager = manager

        // Assigned through the property so didSet fires: init loads `.active` directly, which
        // does not run observers, leaving the main-safe mirrors the stock pages, the carb flow and
        // the IOB gate read still false.
        phase = .active
        loopManager.pumpManager = manager
        onLoanActiveChanged?(true)

        // Seed the dose store's reconciliation stamp from the restored pump's own `lastSync`, or
        // the first cycle after every resume refuses with "pump data too old".
        let lastSync = manager.lastSync
        let readingWaited = loopManager.endAwaitingPumpManager()
        Task { [loopManager] in
            if let lastSync { try? await loopManager.recordPumpEvents([], lastReconciliation: lastSync, replacePendingEvents: false) }
            loopManager.updateDisplayState()
            // A reading that arrived mid-rebuild found no pump and ran no cycle. Run it now rather
            // than losing the wrist's dosing for the rest of the five-minute grid.
            if readingWaited {
                SportLog.event("loan", "RESUME: a reading arrived while the pump manager was being built — running its cycle now")
                loopManager.checkPumpDataAndLoop()
            }
        }
        SportLog.event("loan", "RESUMED — epoch \(epoch ?? -1) rebuilt from saved pod state after a relaunch (R40(e): stock relaunch) · \(RuntimeStateLog.snapshot())")
    }

    /// Raised when a launch finds a session it cannot resume. It says the thing the user can act
    /// on — records may not have reached the phone yet — rather than claiming the loan is over.
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
