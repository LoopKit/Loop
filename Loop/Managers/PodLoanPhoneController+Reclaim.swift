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

extension PodLoanPhoneController {

    /// A repeat inside this window is transport redelivery, not the user asking again.
    static let requestDedupeWindow: TimeInterval = .minutes(2)

    /// Older requests have a sender that has moved on: past its wait, the watch may already have
    /// started without this phone.
    static let requestTTL: TimeInterval = LoanControl.Wait.onScreen.seconds

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
        // A hand-back already being written ends the loan by itself.
        guard self.podIsOnLoan, self.state != .reconciling, self.state != .reclaimPending else { return }
        self.takeBackOnSilence = onSilence
        self.beginTakeBack(from: self.state)
    }

    /// `.reclaimPending` holds the phone's dosing for the attempt, while the pump is not released.
    func beginTakeBack(from previous: State) {
        let started = deps.now()
        takeBackStartedAt = started
        takeBackFrom = previous
        reclaimDisplayAnchor = started

        // Background time from the tap, so pocketing the phone cannot freeze the attempt.
        deps.beginReclaimBackgroundTask()
        handbackDiag(epoch, String(format: "take-back: reaching for the pod, giving up after %.0f s", Self.takeBackLinkLimit))
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
            refuseTakeBack(control: control, why: String(format: "no pod link after %.1f s", waited),
                           notice: (NSLocalizedString("Couldn't Reach the Pod", comment: "Phone notice title when a take-back found the pod out of reach"),
                                    NSLocalizedString("The watch is still looping. Try again.", comment: "Phone notice body when a take-back found the pod out of reach")))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.takeBackPollInterval) { [weak self] in
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
            DispatchQueue.main.async {
                guard self.takeBackStartedAt == started, self.state == .reclaimPending else { return }
                guard let endsAt = odometer.bolusUnderWayEndsAt else {
                    if !read { self.handbackDiag(self.epoch, "take-back: the pod read failed; going ahead on the link") }
                    self.finishTakeBack(waited: waited)
                    return
                }
                let left = max(1, endsAt.timeIntervalSince(self.deps.now())).rounded(.up)
                if self.takeBackOnSilence {
                    self.handbackDiag(self.epoch, String(format: "take-back: waiting for the watch's bolus to finish, %.0f s left", left))
                    DispatchQueue.main.asyncAfter(deadline: .now() + min(left, 10) + 1) { [weak self] in
                        self?.awaitPodForTakeBack(started: started, tick: 0)
                    }
                } else if let control = pump as? ExclusiveDeviceControl {
                    self.refuseTakeBack(control: control, why: String(format: "the pod is giving the watch's bolus, %.0f s left", left),
                                        notice: (NSLocalizedString("Wait for the Bolus", comment: "Phone notice title when a take-back found the watch's bolus still being given"),
                                                 LoanControl.bolusRefusal(LoanControl.BolusUnderWay(endsAt: endsAt), now: self.deps.now())))
                }
            }
        }
    }

    /// The link is up and the pod is free: tell the watch to stop and take over.
    private func finishTakeBack(waited: TimeInterval) {
        // Aim at the newest loan the watch reported; a stale-epoch revoke would be refused.
        let revokeEpoch = supersededByLiveLoan(epoch) ? (newestForeignLoanEvidence?.epoch ?? epoch) : epoch
        sendMessage(.revoke(Revoke(epoch: revokeEpoch)))
        handbackDiag(epoch, String(format: "take-back: pod link up after %.1f s, telling the watch to stop e%d", waited, revokeEpoch))
        clearInferredLoanYield(reason: "take-back, this phone holds the pod")
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
        deps.ownershipDidChange()
        deps.endReclaimBackgroundTask()

        handbackDiag(epoch, "take-back refused: \(why); the loan is unchanged and nothing was sent to the watch")
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
        log.default("taking the pod back without a hand-back: %{public}@", reason)

        // Defer behind a write in flight, so the salvage does not re-commit what it is writing.
        if commitInFlight {
            handbackDiag(epoch, "take-back waits for the hand-back being saved")
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
                "take-back: saving %d staged records as %d doses, %.3f U of bolus and %d rate records programming %.3f U, %d carbs, %d carb deletes",
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
                        ? String(format: "carb delete from the watch applied: %.0f g", gone.grams)
                        : String(format: "carb delete from the watch failed: %.0f g at %@: %@",
                                 gone.grams, String(describing: gone.startDate), String(describing: error!)))
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
            handbackDiag(epoch, "take-back check impossible: no starting pod total, basal schedule or pump")
            deps.issueUrgentNotice(Self.sessionUnverifiedTitle, Self.sessionUnverifiedBody)
            return false
        }
        let allEvents = staged.values.sorted { $0.seq < $1.seq }
        let expected = LoanReconciler.expectedInsulin(events: allEvents, schedule: schedule, pulseUnits: pulseUnits,
                                                      from: anchor.at, to: deps.now())
        pendingHandbackAudit = PendingHandbackAudit(
            epoch: epoch, deliveredAtStart: anchor.units, windowStart: anchor.at, expected: expected,
            loanMinutes: deps.now().timeIntervalSince(start) / 60,
            watchLatest: nil, flavor: .forceReclaim)

        handbackDiag(epoch, String(format:
            "take-back check armed: expected %.3f U from %d records and the schedule over %.0f min",
            expected, allEvents.count, deps.now().timeIntervalSince(anchor.at) / 60))
        return true
    }
}
