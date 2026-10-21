//
//  PodLoanPhoneController+Reclaim.swift
//  Loop
//
//  Taking the pod back: reach for the pod, then tell the watch to stop, import what it streamed
//  and hold dosing until the pod's own total rules. Also the persisted keys.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {

    /// A repeat inside this window is transport redelivery, not the user asking again.
    static let requestDedupeWindow: TimeInterval = .minutes(2)

    /// Older requests have a sender that has moved on (the watch waits 60 s).
    static let requestTTL: TimeInterval = 90

    /// How long a take-back waits for the pod's link before it refuses. Short on purpose: the pod is
    /// normally in reach at once, and a refusal costs the user one more tap. Shortened by tests.
    static var takeBackLinkLimit: TimeInterval = 5

    private static let takeBackPollInterval: TimeInterval = 0.25

    enum NotificationID {
        static let t1 = "podloan.t1"
        static let paused = "podloan.paused1h"


        /// One identifier per rung.
        static func placeholder(_ index: Int) -> String { "podloan.placeholder.\(index)" }
    }

    enum ReminderLadder {
        /// Within the insulin action duration.
        static let placeholderRungs: [TimeInterval] = [.hours(2), .hours(4)]
    }

    /// Offered, not yet confirmed: neither device is dosing.
    var isPodTakeoverInProgress: Bool {
        return state == .grantOffered
    }

    /// Derived from persisted state, so a relaunch re-pauses dosing at once.
    var podIsOnLoan: Bool {
        switch state {
        case .owner: return yieldingToInferredLoan
        case .grantOffered, .loaned, .reconciling, .reclaimPending: return true
        }
    }

    /// The user's take-back from the pod tile; nothing takes the pod back on a timer. One path:
    /// reach for the pod first. With the link up the phone holds the pod, so it tells the watch to
    /// stop and takes over; without it nothing has changed and the user is asked to try again.
    func reclaimNow(onSilence: Bool = false) {
        queue.async {
            // A hand-back already being written ends the loan by itself.
            guard self.podIsOnLoan, self.state != .reconciling, self.state != .reclaimPending else { return }
            self.takeBackOnSilence = onSilence
            self.beginTakeBack(from: self.state)
        }
    }

    /// `.reclaimPending` holds the phone's dosing for the attempt, while the pump is not released.
    func beginTakeBack(from previous: State) {
        let started = deps.now()
        takeBackStartedAt = started
        takeBackFrom = previous
        reclaimDisplayAnchor = started

        // Background time from the tap, so pocketing the phone cannot freeze the attempt.
        deps.beginReclaimBackgroundTask()
        handbackDiag(epoch, String(format: "take-back: reaching for the pod (limit %.0fs)", Self.takeBackLinkLimit))
        state = .reclaimPending
        reclaimPodConnection()
        awaitPodForTakeBack(started: started, tick: 0)
    }

    private func awaitPodForTakeBack(started: Date, tick: Int) {
        guard takeBackStartedAt == started, state == .reclaimPending else { return }
        let waited = Double(tick) * Self.takeBackPollInterval

        if deps.isConnectionReady() {
            readPodForTakeBack(started: started, waited: waited)
            return
        }

        // Giving up needs the pump to release; without one, keep holding.
        if waited >= Self.takeBackLinkLimit, let control = deps.pumpManager() as? ExclusiveDeviceControl {
            refuseTakeBack(control: control, why: String(format: "no pod link after %.1fs", waited),
                           notice: (NSLocalizedString("Couldn't Reach the Pod", comment: "Phone notice title when a take-back found the pod out of reach"),
                                    NSLocalizedString("Sport Mode is still running on the watch. Bring the phone close to the pod and try again.", comment: "Phone notice body when a take-back found the pod out of reach")))
            return
        }
        queue.asyncAfter(deadline: .now() + Self.takeBackPollInterval) { [weak self] in
            self?.awaitPodForTakeBack(started: started, tick: tick + 1)
        }
    }

    /// With the link up, the pod is read before the stop. Nobody takes the pod while it is giving a
    /// bolus (transfer T): a tapped take-back is refused, and a take-over on silence waits for the pod
    /// to finish, its link limit starting again after. The pod's own status says whether it is giving
    /// one; this phone's bolus state knows only its own. The pod has one connection, so the watch
    /// cannot start another bolus meanwhile.
    private func readPodForTakeBack(started: Date, waited: TimeInterval) {
        guard let pump = deps.pumpManager(), let odometer = pump as? PumpDeliveryOdometer else { return finishTakeBack(waited: waited) }
        Task { [weak self] in
            let read = await odometer.refreshDeliveredUnits()
            guard let self else { return }
            self.queue.async {
                guard self.takeBackStartedAt == started, self.state == .reclaimPending else { return }
                guard let endsAt = odometer.bolusUnderWayEndsAt else {
                    self.handbackDiag(self.epoch, read ? "take-back: pod read — no bolus being given" : "take-back: pod read FAILED — going ahead on the link")
                    self.finishTakeBack(waited: waited)
                    return
                }
                let left = max(1, endsAt.timeIntervalSince(self.deps.now())).rounded(.up)
                if self.takeBackOnSilence {
                    self.handbackDiag(self.epoch, String(format: "take-back: the pod is giving the watch's bolus, %.0f s left — waiting for it to finish", left))
                    self.queue.asyncAfter(deadline: .now() + min(left, 10) + 1) { [weak self] in
                        self?.awaitPodForTakeBack(started: started, tick: 0)
                    }
                } else if let control = pump as? ExclusiveDeviceControl {
                    self.refuseTakeBack(control: control, why: String(format: "the pod is giving the watch's bolus, %.0f s left", left),
                                        notice: (NSLocalizedString("Wait for the Bolus", comment: "Phone notice title when a take-back found the watch's bolus still being given"),
                                                 String(format: NSLocalizedString("A bolus is still being given. Try again in %.0f seconds.", comment: "Phone notice body when a take-back found the watch's bolus still being given"), left)))
                }
            }
        }
    }

    /// The link is up and the pod is free: tell the watch to stop and take over.
    private func finishTakeBack(waited: TimeInterval) {
        // Aim at the newest loan the watch reported; a stale-epoch revoke would be refused.
        let revokeEpoch = supersededByLiveLoan(epoch) ? (newestForeignLoanEvidence?.epoch ?? epoch) : epoch
        sendMessage(.revoke(Revoke(epoch: revokeEpoch)))
        handbackDiag(epoch, String(format: "take-back: pod link up +%.1fs — watch told to stop (revoke e%d)", waited, revokeEpoch))
        clearInferredLoanYield(reason: "take-back — this phone holds the pod")
        forceReclaimToOwner(reason: "take-back from the pod tile")
    }

    /// The pod did not answer, or is busy with a bolus: undo the reach and leave the loan exactly as
    /// it was. No revoke was sent and no record imported, so the watch carries on.
    private func refuseTakeBack(control: ExclusiveDeviceControl, why: String, notice: (title: String, body: String)) {
        let previous = takeBackFrom ?? (yieldingToInferredLoan ? .owner : .loaned)
        cancelTakeBackAttempt()
        reclaimDisplayAnchor = nil

        control.releaseControl()
        deps.pumpControlChanged(true)
        // Not through `state`: going back to `.owner` under a yield is not the pod coming home.
        updateState { $0.phase = previous }
        syncUIMirror()
        deps.ownershipDidChange()
        deps.endReclaimBackgroundTask()

        handbackDiag(epoch, "take-back REFUSED — \(why); loan unchanged (\(previous.rawValue)), nothing sent to the watch")
        deps.issueNotice(notice.title, notice.body)
    }

    /// Called wherever a loan ends by another route.
    func cancelTakeBackAttempt() {
        takeBackStartedAt = nil
        takeBackFrom = nil
    }

    /// Take the pod without waiting for the watch: commit what it streamed, arm an audit, take the
    /// link, open the settle, clear staging last. The armed audit holds automatic dosing until it rules.
    func forceReclaimToOwner(reason: String) {
        os_log("Force reclaim to OWNER: %{public}@", log: log, type: .default, reason)

        // Defer behind a write in flight, so the salvage does not re-commit what it is writing.
        if commitInFlight {
            handbackDiag(epoch, "force reclaim DEFERRED — a hand-back commit is writing; runs when it lands")
            pendingForceReclaimReason = reason
            return
        }
        cancelTakeBackAttempt()
        cancelNotification(id: NotificationID.paused)

        // Salvage everything uncommitted, as a final hand-back stamped now.
        let events = staged.values
            .filter { !stagedTombstones.contains($0.id) && !committedIDs.contains($0.id) }
            .sorted { $0.seq < $1.seq }
        if !events.isEmpty {
            let input = LoanReconciler.Input(
                events: events, schedule: deps.settings().basalRateSchedule,
                loanStart: loanStartedAt ?? deps.now().addingTimeInterval(-.hours(2)),
                loanEnd: deps.now())
            let outcome = LoanReconciler.reconcile(input)

            let boluses = outcome.doses.filter { $0.type == .bolus }
            let bolusUnits = boluses.reduce(0.0) { $0 + ($1.deliveredUnits ?? $1.programmedUnits) }
            let rateGross = outcome.doses.filter { $0.type != .bolus }.reduce(0.0) { $0 + $1.programmedUnits }
            handbackDiag(epoch, String(format:
                "force reclaim SALVAGE — %d staged event(s) → %d dose(s): %.3f U bolus + %d rate record(s) (%.3f U gross programmed), %d carb(s), %d delete(s)",
                events.count, outcome.doses.count, bolusUnits, outcome.doses.count - boluses.count,
                rateGross, outcome.carbs.count, outcome.deletedCarbs.count))
            deps.addPumpEvents(newPumpEvents(from: outcome.doses), deps.now()) { _ in }

            if let earliest = outcome.doses.map(\.startDate).min() {
                deps.insulinHistoryRewritten(earliest)
            }
            for carb in outcome.carbs { deps.addCarb(carb) { _ in } }
            for gone in outcome.deletedCarbs {
                deps.deleteCarb(gone) { error in
                    self.handbackDiag(self.epoch, error == nil
                        ? String(format: "carb DELETE applied on phone (recovery) — %.0f g", gone.grams)
                        : String(format: "carb DELETE MISSED on phone (recovery) — %.0f g: %@", gone.grams, String(describing: error!)))
                }
            }

            // Advance the cursor too, or the watch never closes its loan.
            let newCursor = events.map(\.seq).max()
            updateState {
                $0.committedIDs.formUnion(events.map(\.id))
                if let newCursor { $0.committedCursor = max($0.committedCursor, newCursor) }
            }
        }

        armForceReclaimAudit()

        reclaimPodConnection()
        state = .owner
        beginReclaimSettleWindow()
        // Clear staging only after the audit has read it.
        staged = [:]
        stagedTombstones = []
        persistStaged()
    }

    /// Arms the owed verdict over the window from the ledger's last reading: the watch's takeover
    /// reading, or the grant's before one arrived. With no reading or schedule there is nothing to check against.
    @discardableResult
    private func armForceReclaimAudit() -> Bool {
        let start = loanStartedAt ?? deps.now().addingTimeInterval(-.hours(2))
        guard let anchor = ledgerLast, let schedule = deps.settings().basalRateSchedule, let pulseUnits = pumpPulseUnits else {
            handbackDiag(epoch, "** force-reclaim audit IMPOSSIBLE — no start odometer/schedule/pump; session UNVERIFIED **")
            deps.issueUrgentNotice("Watch Session Unverified", Self.sessionUnverifiedBody)
            return false
        }
        let allEvents = staged.values.sorted { $0.seq < $1.seq }
        let expected = LoanReconciler.expectedInsulin(events: allEvents, schedule: schedule, pulseUnits: pulseUnits,
                                                      from: anchor.at, to: deps.now())
        pendingHandbackAudit = PendingHandbackAudit(
            epoch: epoch, deliveredAtStart: anchor.units, windowStart: anchor.at, expected: expected,
            loanMinutes: deps.now().timeIntervalSince(start) / 60, cycles: 0,
            watchLatest: nil, watchFreshened: false, flavor: .forceReclaim)

        handbackDiag(epoch, String(format:
            "force-reclaim audit armed — expected %.3f U from %d record(s) + schedule fill over %.0f min since takeover; verdict on the reclaim round-trip",
            expected, allEvents.count, deps.now().timeIntervalSince(anchor.at) / 60))
        return true
    }
}
