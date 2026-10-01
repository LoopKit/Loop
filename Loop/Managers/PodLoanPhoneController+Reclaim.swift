//
//  PodLoanPhoneController+Reclaim.swift
//  Loop
//
//  Part of PodLoanPhoneController (see PodLoanPhoneController.swift). Split by concern; stored
//  properties live in the core class.
//
//  Taking the pod back, and the persisted vocabulary the whole controller shares.
//
//  Taking it back politely means asking the watch to drain and hand over — the revoke ladder.
//  Taking it by force means giving up on that conversation, salvaging whatever the watch has
//  already streamed, and refusing to dose again until the pod's own delivery total says the
//  salvage was complete. A force reclaim is never a silent success: either the audit rules or
//  the loop opens.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {

    /// A request that repeats inside this window is the transport redelivering one the phone has
    /// already answered, not the user asking again. Acting on the copy runs the stale-state
    /// recovery path, force-reclaims the pod the phone just released and grants a second time,
    /// leaving the watch holding a grant for a pod that is back on the phone. A genuine retry
    /// carries a fresh request ID and is unaffected.
    static let requestDedupeWindow: TimeInterval = .minutes(2)

    /// How old a request may be and still be worth granting. The watch waits at most 60 s for an
    /// answer, so anything past this plus transit slack has a sender that has moved on — perhaps
    /// to starting the session itself. Granting to a queued ghost mints an epoch nobody will
    /// take up, which the phone then has to force-reclaim from itself.
    static let requestTTL: TimeInterval = 90

    /// The state of one polite take-back attempt.
    struct ReclaimLadder {
        enum Branch: String { case live = "LIVE", dead = "DEAD" }
        var branch: Branch
        let startedAt: Date

        /// When patience runs out. On the dead branch this is the start: there is nothing to
        /// wait for.
        var forceAt: Date

        /// Revokes sent, capped at two. A third would only delay the force.
        var attempts: Int

        var forced: Bool
        var phase: ReclaimProgress.Phase {
            if forced || branch == .dead { return .forcing }
            return .draining
        }
    }

    /// How recently the watch must have been heard from to count as alive. A watch holding the
    /// pod reports a completed cycle roughly every five minutes, so silence beyond that is the
    /// discriminator — not reachability, which reads false for a perfectly healthy backgrounded
    /// watch and is only ever admissible as a POSITIVE signal.
    static let watchContactLivenessWindow: TimeInterval = 330

    /// Live branch: one resend, then force. A hand-back that is going to happen answers in about
    /// a second; the resend exists for the tail, and two attempts cover it.
    private static let liveResendDelay: TimeInterval = 10
    private static let liveForceDelay: TimeInterval = 25

    /// What a drain costs when the watch is answering — the expectation the tile's progress is
    /// drawn against, not a deadline.
    static let liveHandoverExpectation: TimeInterval = 10

    /// Rungs use WALL deadlines. Dispatch's monotonic `.now() + delay` freezes while iOS
    /// suspends the app and appends the suspension afterwards, so a locked phone turns a
    /// 25-second force into a minute or more with the pod owned by nobody.
    ///
    /// `scheduler` is the test seam; production always takes the wall-deadline path.
    private func scheduleLadderRung(after delay: TimeInterval, label: String, execute work: DispatchWorkItem) {
        if let scheduler = scheduler {
            scheduler(delay, label, work)
        } else {
            queue.asyncAfter(wallDeadline: .now() + delay, execute: work)
        }
    }

    /// Everything the controller persists. The loan state machine has to survive a relaunch
    /// mid-loan — a phone that came back believing it owned the pod would dose beside the watch.
    enum Keys {
        static let state = "PodLoanPhoneController.state"
        static let epoch = "PodLoanPhoneController.epoch"
        static let cursor = "PodLoanPhoneController.cursor"
        static let pendingRevoke = "PodLoanPhoneController.pendingRevoke"
        /// The exactly-once record. Losing it would let a resend re-commit doses already booked.
        static let committedIDs = "PodLoanPhoneController.committedIDs"
        /// Start of the current loan's audit window, and the floor for every expectation over it.
        static let loanStartedAt = "PodLoanPhoneController.loanStartedAt"

        /// The pod's delivery total as the phone last saw it, read at the grant. The fallback
        /// audit origin when the watch's own takeover reading never arrived.
        static let deliveredAtGrant = "PodLoanPhoneController.deliveredAtGrant"

        /// The same total as the WATCH first read it. Preferred, because it is on the watch's
        /// side of the hand-over. It is cleared whenever a loan starts or is adopted: a reading
        /// left over from the previous loan would put that loan's delivery inside this one's
        /// unexplained window.
        static let deliveredAtTakeover = "PodLoanPhoneController.deliveredAtTakeover"

        /// The standing placeholder for insulin a lost watch never accounted for.
        static let gapBooking = "PodLoanPhoneController.gapBooking"

        /// A force-reclaim audit that has not ruled yet. Only this flavour persists — whether
        /// the loop closes again must depend on the pod's answer, not on whether the app
        /// happened to relaunch before it came.
        static let pendingForceAudit = "PodLoanPhoneController.pendingForceAudit"

        /// The last loan's delivered total as the PHONE measured it at the verified round-trip.
        static let deliveredAuthoritative = "PodLoanPhoneController.deliveredAuthoritative"

        /// Rolling diagnostic series. Nothing reads these back to change behaviour.
        static let residualHistory = "PodLoanPhoneController.residualHistory"

        /// Marks the one-time cleanup of force-reclaim residuals out of the series above.
        static let residualHistoryPurged = "PodLoanPhoneController.residualHistoryPurged.2026-08-13"

        /// Where the audit window currently starts — stored with the epoch that owns it.
        static let auditBase = "PodLoanPhoneController.auditBase"

        static let windowWorstHistory = "PodLoanPhoneController.windowResidualWorst"

        /// Whether the paired watch advertised that it can start a session on its own. Nothing
        /// dormant is sent to a watch that cannot use it.
        static let watchSupportsSeize = "PodLoanPhoneController.watchSupportsSeize"

        /// The standing credential the watch echoes back when it did start on its own. Its
        /// presence is also what makes a watch's claim to hold the pod believable at all.
        static let dormantSeizeToken = "PodLoanPhoneController.dormantSeizeToken"

        /// Persisted because the blackout it answers can include a phone reboot.
        static let yieldingToInferredLoan = "PodLoanPhoneController.yieldingToInferredLoan"
    }

    enum NotificationID {
        static let t1 = "podloan.t1"
        /// Retired. Kept only so an upgrade from a build that armed them can cancel them.
        static let duration = "podloan.6h"
        static let paused = "podloan.paused1h"

        static let openLoop = "podloan.openloop"

        /// One identifier per rung, so re-arming replaces its own rung and cancelling the
        /// ladder cannot silence anything else.
        static func placeholder(_ index: Int) -> String { "podloan.placeholder.\(index)" }
    }

    enum ReminderLadder {
        /// Both rungs sit inside the insulin action duration. Past it the placeholder has
        /// decayed out of IOB and correcting its timing changes nothing.
        static let placeholderRungs: [TimeInterval] = [.hours(2), .hours(4)]
        static let openLoopDelay: TimeInterval = .hours(1)
    }

    /// The pod has been offered but the watch has not confirmed holding it. Neither device is
    /// dosing in this window, which is why it has its own dead-man.
    var isPodTakeoverInProgress: Bool {
        return state == .grantOffered
    }

    /// DERIVED from the persisted state, never a flag of its own. A relaunch in any non-owner
    /// state therefore re-pauses dosing and re-arms the recovery affordance before a single
    /// message has arrived.
    var podIsOnLoan: Bool {
        switch state {
        case .owner: return yieldingToInferredLoan
        case .grantOffered, .loaned, .reconciling, .reclaimPending: return true
        }
    }

    /// The user's take-back, from the pod tile. This is the only thing that ends a loan against
    /// the watch's wishes — nothing in this controller takes the pod back on a timer.
    func reclaimNow() {
        queue.async {
            guard self.podIsOnLoan else { return }

            self.clearInferredLoanYield(reason: "pill tap — reclaimNow (the inherited exit)")
            self.reclaimDisplayAnchor = self.deps.now()

            // Hold background execution from the tap onward. Tap-and-pocket otherwise freezes
            // the ladder mid-flight with the pod released by the watch and not yet taken here.
            self.deps.beginReclaimBackgroundTask()
            self.pendingRevoke = true

            // Aim the revoke at the newest loan the watch has told us about, when that evidence
            // is fresh. A revoke naming our own stale epoch is correctly refused by the watch's
            // split-brain guard, and the ladder then reads that refusal as death and force-steals
            // a pod that would have drained politely.
            let revokeEpoch = self.supersededByLiveLoan(self.epoch)
                ? (self.newestForeignLoanEvidence?.epoch ?? self.epoch) : self.epoch
            if revokeEpoch != self.epoch {
                self.handbackDiag(self.epoch, "reclaim revoke AIMED at e\(revokeEpoch) — fresh evidence of a loan this phone never granted (mirror)")
            }
            self.sendMessage(.revoke(Revoke(epoch: revokeEpoch)))
            self.reclaimPodConnection()
            self.state = .reclaimPending
            self.armReclaimLadder()
        }
    }

    /// Chooses how long to wait for the watch to drain, from whether it looks alive.
    ///
    /// Either signal admits a watch to the LIVE branch; only their absence condemns it. The DEAD
    /// branch forces immediately and waits for nothing, because nothing that lands there can
    /// answer a revoke. The revoke is still SENT — it arms the split-brain guard on a watch that
    /// wakes up later believing it still holds the pod.
    private func armReclaimLadder() {
        cancelReclaimLadder()

        let reachable = deps.isWatchReachable()
        let lastContact = deps.lastWatchContactAt()
        let contactAge = lastContact.map { deps.now().timeIntervalSince($0) }
        let heardRecently = (contactAge ?? .greatestFiniteMagnitude) < Self.watchContactLivenessWindow
        let branch: ReclaimLadder.Branch = (reachable || heardRecently) ? .live : .dead

        let resendDelay: TimeInterval? = branch == .live ? Self.liveResendDelay : nil
        let forceDelay: TimeInterval = branch == .live ? Self.liveForceDelay : 0

        let started = deps.now()
        reclaimLadder = ReclaimLadder(branch: branch,
                                      startedAt: started,
                                      forceAt: started.addingTimeInterval(forceDelay),
                                      attempts: 1,
                                      forced: false)

        let ageText = contactAge.map { String(format: "%.1fs ago", $0) } ?? "never"
        let planText = branch == .live
            ? String(format: "resend +%.0fs, force +%.0fs", Self.liveResendDelay, Self.liveForceDelay)
            : "force NOW (dead branch waits for nothing; the revoke is fire-and-forget)"
        handbackDiag(epoch, String(format: "reclaim ladder %@ — last watch contact %@, reachable %d · %@",
                                   branch.rawValue, ageText, reachable ? 1 : 0, planText))

        scheduleRungs(resendIn: resendDelay, forceIn: forceDelay)
    }

    private func scheduleRungs(resendIn resendDelay: TimeInterval?, forceIn forceDelay: TimeInterval) {
        reclaimResendWork?.cancel()
        reclaimTimeoutWork?.cancel()

        if let resendDelay = resendDelay {
            let resend = DispatchWorkItem { [weak self] in
                guard let self = self, self.state == .reclaimPending,
                      var ladder = self.reclaimLadder, !ladder.forced else { return }

                // Two revokes in total, however they were triggered — this rung and a
                // reachability-driven resend draw on the same budget.
                guard ladder.attempts < 2 else { return }

                let resendEpoch = self.supersededByLiveLoan(self.epoch)
                    ? (self.newestForeignLoanEvidence?.epoch ?? self.epoch) : self.epoch
                self.sendMessage(.revoke(Revoke(epoch: resendEpoch)))
                ladder.attempts += 1
                self.reclaimLadder = ladder
                self.handbackDiag(self.epoch, "reclaim revoke RESENT (attempt \(ladder.attempts) of 2) — no drain yet on the \(ladder.branch.rawValue) branch")
            }
            reclaimResendWork = resend
            scheduleLadderRung(after: max(resendDelay, 0), label: "reclaim-resend", execute: resend)
        } else {
            reclaimResendWork = nil
        }

        // The force rung is always scheduled, on both branches — the dead branch simply has no
        // delay in front of it. There is no path where a reclaim waits forever.
        let force = DispatchWorkItem { [weak self] in
            guard let self = self, self.state == .reclaimPending, let ladder = self.reclaimLadder else { return }

            self.reclaimLadder?.forced = true

            let holding = self.supersededByLiveLoan(self.epoch)
                ? " (watch holds newer loan e\(self.newestForeignLoanEvidence?.epoch ?? 0) — refused, not silent)" : ""
            self.forceReclaimToOwner(reason: "reclaim ladder spent on the \(ladder.branch.rawValue) branch — \(ladder.attempts) revoke attempt(s), watch did not drain\(holding)")
        }
        reclaimTimeoutWork = force
        scheduleLadderRung(after: max(forceDelay, 0), label: "reclaim-force", execute: force)
    }

    /// Stands the ladder down. Called wherever the loan ends by another route — a drain that
    /// arrived, a retro-ack, an abandoned grant — so a rung cannot fire against a loan that has
    /// already closed.
    func cancelReclaimLadder() {
        reclaimResendWork?.cancel()
        reclaimResendWork = nil
        reclaimTimeoutWork?.cancel()
        reclaimTimeoutWork = nil
        reclaimLadder = nil
    }

    /// Take the pod back without the watch's cooperation: salvage what it already streamed,
    /// write it, and arm an audit against the pod's own delivery total.
    ///
    /// Automatic dosing does NOT resume here when that audit arms. Resuming on whatever happened
    /// to arrive is exactly the watch-battery-dies case — a delivered bolus that never streamed
    /// is invisible, and the loop would close on books missing real insulin.
    ///
    /// The order: defer behind any in-flight write, commit the salvage, arm the audit from the
    /// records while they are still staged, take the pod, open the settle window, and clear the
    /// staging area last. Clearing it earlier would leave the audit with nothing to build an
    /// expectation from, and every unexplained unit would read as unaccounted insulin.
    func forceReclaimToOwner(reason: String) {
        os_log("Force reclaim to OWNER: %{public}@", log: log, type: .default, reason)

        // Defer behind a write in flight. Running now would read a `committedIDs` set that the
        // write has not updated yet and re-commit the same records: insulin survives that on
        // raw-byte identity, but carbs have none and would double.
        if commitInFlight {
            handbackDiag(epoch, "force reclaim DEFERRED (#118) — a hand-back commit is writing; runs when it lands")
            pendingForceReclaimReason = reason
            return
        }
        cancelReclaimLadder()
        cancelNotification(id: NotificationID.paused)
        cancelNotification(id: NotificationID.duration)

        // Salvage: everything the watch streamed that has not been committed. It is treated as a
        // FINAL hand-back stamped now, because there will be no hand-back — whatever the watch
        // was still running is cut here.
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
                "force reclaim SALVAGE — %d staged event(s) → %d dose(s): %.3f U bolus + %d rate record(s) (%.3f U gross programmed), %d carb(s), %d delete(s); loop resumes CLOSED on these books (no odometer check — OBS-9)",
                events.count, outcome.doses.count, bolusUnits, outcome.doses.count - boluses.count,
                rateGross, outcome.carbs.count, outcome.deletedCarbs.count))
            deps.addPumpEvents(newPumpEvents(from: outcome.doses), deps.now()) { _ in }

            if let earliest = outcome.doses.map(\.startDate).min() {
                deps.insulinHistoryRewritten(earliest)
            }
            for carb in outcome.carbs { deps.addCarb(carb.entry, carb.eventID.uuidString) { _ in } }
            for gone in outcome.deletedCarbs {
                deps.deleteCarb(gone) { error in
                    self.handbackDiag(self.epoch, error == nil
                        ? String(format: "carb DELETE applied on phone (recovery) — %.0f g", gone.grams)
                        : String(format: "carb DELETE MISSED on phone (recovery) — %.0f g: %@", gone.grams, String(describing: error!)))
                }
            }

            committedIDs.formUnion(events.map(\.id))
            persistCommittedIDs()

            // Advance the cursor as well as the ID set. The watch only closes its loan when it
            // has nothing unacked left, and a cursor still at zero can never make that true —
            // the result is a resend loop that never ends. The watch caps whatever we send below
            // its own lowest withheld event, so an over-eager cursor cannot bury one.
            if let newCursor = events.map(\.seq).max() {
                committedCursor = max(committedCursor, newCursor)
            }

            deps.issueNotice(
                NSLocalizedString("Watch Session Ended Without Hand-Back", comment: "Phone notice title after a force reclaim salvaged staged records"),
                NSLocalizedString("Automatic dosing is paused while Loop checks the pod's insulin total. This usually takes seconds.", comment: "Phone notice body after a force reclaim salvaged staged records"))
        }

        let auditArmed = armForceReclaimAudit()

        reclaimPodConnection()
        pendingRevoke = false
        state = .owner

        // Dosing stays paused while an audit is owed; the verdict lifts it. When no audit could
        // be armed the pause is lifted here, but `armForceReclaimAudit` has already opened the
        // loop, so nothing doses automatically in that case either.
        if !auditArmed {
            deps.setAutomaticDosingPaused(false)
        }
        beginReclaimSettleWindow()
        // Clear the staging area only after the audit above has read it: the expectation is
        // computed from these records, not from what was committed.
        staged = [:]
        stagedTombstones = []
        persistStaged()
    }

    /// Works out what the salvaged records say the pod should have delivered, and leaves a
    /// verdict owed against the pod's own total. Returns whether the audit could be armed at all.
    ///
    /// Without a starting reading or a basal schedule there is nothing to compare, and "cannot
    /// verify" must never become "assume fine": the loop opens on principle and the user is told
    /// in the same words every other unverifiable session uses.
    @discardableResult
    private func armForceReclaimAudit() -> Bool {
        let start = loanStartedAt ?? deps.now().addingTimeInterval(-.hours(2))
        // Prefer the running audit base — accepted checkpoints have already reconciled
        // everything before it, so the verdict window is only the stretch still unexplained.
        let anchor: (units: Double, asOf: Date)?
        if let base = auditBase {
            anchor = (base.units, base.asOf)
        } else if let units = (UserDefaults.standard.object(forKey: Keys.deliveredAtTakeover) as? Double)
                            ?? (UserDefaults.standard.object(forKey: Keys.deliveredAtGrant) as? Double) {
            anchor = (units, start)
        } else {
            anchor = nil
        }
        guard let anchor = anchor, let schedule = deps.settings().basalRateSchedule else {
            handbackDiag(epoch, "** R37 force-reclaim audit IMPOSSIBLE — no start odometer/schedule; loop OPENS on principle (cannot verify => do not resume) **")
            deps.openLoopForUncertainReconciliation()
            armOpenLoopReminder()
            deps.issueUrgentNotice("Watch Session Unverified", Self.sessionUnverifiedBody)
            return false
        }
        let allEvents = staged.values.sorted { $0.seq < $1.seq }
        let expected = LoanReconciler.expectedInsulin(events: allEvents, schedule: schedule,
                                                      from: anchor.asOf, to: deps.now())

        // A second, whole-loan expectation for the drift tripwire in the verdict. Diagnostic:
        // the verdict itself is decided on the window above.
        let takeoverUnits = UserDefaults.standard.object(forKey: Keys.deliveredAtTakeover) as? Double
        let wholeLoanExpected = takeoverUnits.map {
            _ in LoanReconciler.expectedInsulin(events: allEvents, schedule: schedule, from: start, to: deps.now())
        }
        pendingHandbackAudit = PendingHandbackAudit(
            epoch: epoch, deliveredAtStart: anchor.units, expected: expected,
            loanMinutes: deps.now().timeIntervalSince(start) / 60, cycles: 0,
            watchLatest: nil, watchFreshened: false, flavor: .forceReclaim,
            takeoverUnits: takeoverUnits, wholeLoanExpected: wholeLoanExpected)

        handbackDiag(epoch, String(format:
            "R37 audit armed — expected %.3f U from %d record(s) + schedule fill over window since %@ (%d checkpoint(s)); verdict on the reclaim round-trip",
            expected, allEvents.count,
            checkpointsThisLoan > 0 ? String(format: "last sync %.0f min ago", deps.now().timeIntervalSince(anchor.asOf) / 60) : "takeover",
            checkpointsThisLoan))
        return true
    }

    /// A watch that comes back into reach mid-reclaim gets the revoke again immediately rather
    /// than waiting for the next rung. It spends one of the ladder's two attempts, so an
    /// intermittent link cannot keep the reclaim alive indefinitely.
    func watchDidBecomeReachable() {
        queue.async {
            guard self.pendingRevoke else { return }
            self.sendMessage(.revoke(Revoke(epoch: self.epoch)))
            if var ladder = self.reclaimLadder, self.state == .reclaimPending, !ladder.forced,
               ladder.attempts < 2 {
                ladder.attempts += 1
                self.reclaimLadder = ladder
            }
        }
    }

}
