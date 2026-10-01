//
//  PodLoanPhoneController+Records.swift
//  Loop
//
//  Part of PodLoanPhoneController (see PodLoanPhoneController.swift). Split by concern; stored
//  properties live in the core class.
//
//  Taking in what the watch dosed. Records arrive twice: streamed cycle by cycle into the
//  staging area, and again in the hand-back offer that ends the loan.
//
//  Three invariants hold the whole path together.
//
//  The store is written BEFORE the ack. An ack is the watch's permission to forget, so a write
//  that failed must not be acked — the watch's resend is the retry.
//
//  Exactly one commit is in flight at a time. Offers that arrive mid-write are coalesced, never
//  dropped, and never allowed to replace a stored final with an interim.
//
//  Deduplication is by EVENT ID. Cursor position cannot serve: the watch withholds events it has
//  not classified yet, so cursors legitimately have gaps and a late-classified event would be
//  discarded on sight.
//
//  Nothing is ever dropped quietly. Every refusal on this path says what it dropped and how it
//  can still come home.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    /// A cycle's worth of records from a live loan. These are staged, not committed: the watch
    /// may still supersede an open temp, and the commit happens at the hand-back.
    func handleBatch(_ batch: DoseRecordBatch) {
        // `.reclaimPending` counts as well as `.loaned`: the watch goes on dosing and reporting
        // until it drains, and records it sends during a revoke are the ones a force reclaim
        // would otherwise have to salvage.
        guard batch.epoch == epoch, state == .loaned || state == .reclaimPending else {
            handbackDiag(batch.epoch, "batch DROPPED — \(batch.events.count) event(s) ev=\(batch.epoch) vs phone ev=\(epoch), state=\(state.rawValue) (recovered via the offer path if the watch still resends)")

            if batch.epoch > epoch, newestForeignLoanEvidence.map({ batch.epoch >= $0.epoch }) ?? true {
                newestForeignLoanEvidence = (batch.epoch, deps.now())
            }

            // A batch from a FUTURE epoch is the watch telling us, in the only words it has,
            // that it is running a session this phone never granted.
            if state == .owner, batch.epoch > epoch,
               UserDefaults.standard.string(forKey: Keys.dormantSeizeToken) != nil {
                engageInferredLoanYield(evidence: "future-epoch batch e\(batch.epoch) at .owner (live seized loan streaming)")
            }

            // Records for a session this phone has closed: the watch still believes it holds the
            // pod. Re-send the revoke so it stands down, throttled so a resend loop on its side
            // does not become one on ours.
            if state == .owner, batch.epoch <= epoch,
               lastClosedSessionRevokeAt.map({ deps.now().timeIntervalSince($0) >= 20 }) ?? true {
                lastClosedSessionRevokeAt = deps.now()
                handbackDiag(batch.epoch, "records from a CLOSED session — the watch still thinks it holds the pod; revoke e\(batch.epoch) sent again")
                sendMessage(.revoke(Revoke(epoch: batch.epoch)))
            }
            return
        }
        noteHoldRenewal(sentAt: batch.sentAt)
        stage(events: batch.events, tombstones: batch.tombstones)

        // A mid-loan odometer reading is a chance to close off everything before it, which
        // narrows what the final verdict has to explain.
        if let snap = batch.odometer {
            considerCheckpoint(snap, context: "batch")
        }
    }

    /// Supplies the phone's half of the periodic pod-link census. Both devices log their view of
    /// the link on a fixed cadence and unconditionally on loan state: the link is otherwise only
    /// recorded as a side effect of sending something, which leaves the record silent exactly
    /// where nothing was sent.
    func installPodLinkCensus() {
        WatchDataManager.podLinkCensus = { [weak self] in
            guard let self, let lendable = self.deps.pumpManager() as? PumpConnectionLendable else {
                return "no pump manager"
            }
            return "released=\(lendable.isConnectionReleased) \(lendable.connectionDiagnostics() ?? "no diagnostics")"
        }
    }

    /// The loan's running commentary, written to the phone's OWN file as well as echoed to the
    /// watch. The watch-bound copy queues until the watch comes back — which is exactly the
    /// dead-watch case that most needs the line — so the phone has to keep its own account of
    /// whether it released the pod.
    func handbackDiag(_ epoch: Int, _ text: String) {
        os_log("HANDBACK-DIAG e%d: %{public}@", log: log, type: .default, epoch, text)

        PhoneLog.event("loan", "e\(epoch) \(text)")
        sendMessage(.diag(LoanDiag(epoch: epoch, text: text)))
    }

    /// The watch offering the pod back, or reporting in mid-loan.
    ///
    /// One function for three shapes, distinguished by `released` and by epoch: an INTERIM drain
    /// (the watch is still dosing), a FINAL hand-back, and a STALE offer for a loan that has
    /// already closed. Everything downstream branches on `isFinal` and `isStale`.
    ///
    /// The order is the contract. Adopt a seized loan if this offer proves one; establish that
    /// the epoch is one we can speak for; coalesce if a write is already running; refuse a final
    /// hand-back we could not honour; take custody of the loan's closing facts; stage the
    /// records; let an interim reading close off an audit window; choose what is committable;
    /// write; ack; apply carbs and overrides; re-write the loan window by store identity; retire
    /// any placeholder the real records have now explained; and only then take the next
    /// coalesced offer.
    ///
    /// Nothing below the write may fail silently, and nothing above it may change state the
    /// phone cannot undo if the write fails.
    func handleHandbackOffer(_ offer: HandbackOffer) {
        // Retro-acknowledge a session the watch started alone. Only from .owner or
        // .reclaimPending: a grant in flight or a live granted loan must never be stomped by a
        // duplicated credential. Token match and a higher epoch are both required.
        if let token = offer.seizeToken, state == .owner || state == .reclaimPending, offer.epoch > epoch,
           token.uuidString == UserDefaults.standard.string(forKey: Keys.dormantSeizeToken) {
            if state == .reclaimPending {
                cancelReclaimLadder()
                handbackDiag(offer.epoch, "[seize] retro-ack arrived MID-RECLAIM — ladder stood down; the aimed revoke got its drain")
            }
            handbackDiag(offer.epoch, "[seize] RETRO-ACK — offer for a SEIZED loan (token …\(String(token.uuidString.suffix(8)))); adopting epoch \(epoch)→\(offer.epoch) as .loaned, reconciling on the normal path")

            clearInferredLoanYield(reason: "retro-ack — the inferred loan is now the adopted loan e\(offer.epoch)")
            epoch = offer.epoch
            state = .loaned
            holdRenewedAt = offer.handedBackAt
            holdLapseNoticedAt = nil

            auditBase = nil
            checkpointsThisLoan = 0
            worstWindowThisLoan = 0
            UserDefaults.standard.removeObject(forKey: Keys.deliveredAtTakeover)

            // Anchor the adopted loan at its OWN era — the earliest record it brought — with a
            // floor six hours back. Leaving it nil hands the audit a generic default window,
            // and a five-minute seized session then gets judged over the whole morning.
            let anchor = max(offer.events.map(\.record.startDate).min() ?? offer.handedBackAt,
                             deps.now().addingTimeInterval(-.hours(6)))
            loanStartedAt = anchor
            UserDefaults.standard.set(anchor, forKey: Keys.loanStartedAt)
        }

        // An offer from AHEAD of this phone cannot be honoured: the phone has no epoch to commit
        // it under and no way to reach that loan's books. Say so loudly — the loan is stranded
        // until a reclaim or a fresh request resets both sides.
        let isStale = offer.epoch < epoch
        guard offer.epoch == epoch || isStale else {
            os_log("Hand-back offer DROPPED: offer.epoch %d > phone.epoch %d — watch ahead of phone; loan may be stranded (needs reclaim or new request)",
                   log: log, type: .error, offer.epoch, epoch)
            handbackDiag(offer.epoch, "offer DROPPED epoch \(offer.epoch) > phone \(epoch) — phone behind, loan stranded")
            return
        }
        handbackDiag(offer.epoch, "offer RX ev=\(offer.events.count) released=\(offer.released.map { $0 ? "final" : "interim" } ?? "nil") stale=\(isStale) state=\(state.rawValue)")

        // One commit at a time. A duplicate arriving mid-write would otherwise start its own
        // write against a `committedIDs` set the first has not updated yet, and each copy
        // amplifies the next. Coalesce by epoch instead — but never let an interim overwrite a
        // FINAL already waiting, or the loan's closing records become a mid-loan snapshot.
        if commitInFlight {
            let storedIsFinal = coalescedOffers[offer.epoch]?.released == true
            if !(storedIsFinal && offer.released != true) {
                coalescedOffers[offer.epoch] = offer
            }
            handbackDiag(offer.epoch, "offer COALESCED behind the in-flight write (#118) — \(coalescedOffers.count) waiting")
            return
        }

        // A missing `released` comes from a build that predates interim drains, where every
        // offer was the end of the loan. Defaulting it to final is what keeps that reading
        // correct.
        let isFinal = offer.released ?? true
        // An interim drain is also the watch checking in, so it renews the silence watchdog.
        if !isStale, !isFinal { noteHoldRenewal(sentAt: offer.handedBackAt) }
        // `.grantOffered` is included: a watch can take the pod, loop and hand it straight back
        // faster than its takeover confirmation reaches this phone.
        let canTransition = state == .loaned || state == .reclaimPending || state == .grantOffered
        // Refuse at the FIRST offer if this phone's Bluetooth is off: it would own a pod it
        // cannot reach while a watch that was looping fine stands down. WatchConnectivity runs
        // over WiFi, so this phone is the only device that can see the problem. Nothing has been
        // committed and no state has changed at this point, so the refusal costs nothing.
        if !isStale, canTransition, deps.isBluetoothPoweredOff() {
            handbackDiag(offer.epoch, "hand-back REFUSED — this phone's Bluetooth is off, so it could not reclaim the pod; the watch keeps the loan")
            sendMessage(.denied(LoanDenied(reason: NSLocalizedString("iPhone Bluetooth is off — still running", comment: "Hand-back refused: shown on the watch glance"))))
            return
        }
        // .reconciling is the phone owing an ack. The watch will not release the pod until one
        // arrives, so the loan is not over until the write below lands.
        if !isStale, isFinal, canTransition {
            state = .reconciling

            handbackDiag(offer.epoch, "commit done — ACKing now; the watch cannot release the pod until this lands")
            // The wrist's loop mode and loop recency come home with the pod: both describe the
            // system, and the phone resuming in a different mode from the one the user left the
            // session in would be a therapy change nobody made.
            if let watchClosed = offer.watchClosedLoopEnabled {
                deps.noteWatchClosedLoop(watchClosed)
                handbackDiag(offer.epoch, "loop mode INHERITED from the wrist — phone will resume \(watchClosed ? "CLOSED" : "OPEN")")
            }

            if let watchLoop = offer.lastLoopCompleted {
                deps.noteWatchLoopCompleted(watchLoop)
                handbackDiag(offer.epoch, String(format: "loop recency INHERITED from the wrist — last cycle %.0fs ago", deps.now().timeIntervalSince(watchLoop)))
            }
        }

        // Captured before staging changes anything: only a live, final offer that actually moved
        // this phone into reconciling is entitled to leave a verdict owed.
        let auditThisOffer = !isStale && isFinal && state == .reconciling

        stage(events: offer.events, tombstones: offer.tombstones)

        // An INTERIM drain may advance the audit base; a final offer must not. The final
        // snapshot is the endpoint the verdict is about, and moving the base onto it would
        // collapse the verdict window to nothing.
        if !isStale, offer.epoch == epoch, offer.released == false, let snap = offer.odometer {
            considerCheckpoint(snap, context: "interim-offer")
        }

        // A stale offer speaks only for ITS OWN events. Draining the whole staged set under a
        // dead loan's hand-back stamp writes records from the live loan clamped to a time before
        // they started, which the store rejects as a batch — and a rejected batch takes the
        // context down with it, failing every later write too.
        let ownEventIDs = isStale ? Set(offer.events.map(\.id)) : nil
        // What to commit now: everything staged, minus what the watch retracted and what is
        // already in the books. Membership of `committedIDs` is the only dedup test.
        let events = staged.values
            .filter { !stagedTombstones.contains($0.id) && !committedIDs.contains($0.id) }
            .filter { ownEventIDs?.contains($0.id) ?? true }
            .sorted { $0.seq < $1.seq }

        // The whole loan, including records already committed. The expectation and the backfill
        // both need the complete picture, not just the new arrivals.
        let allStagedEvents = staged.values
            .filter { !stagedTombstones.contains($0.id) }
            .sorted { $0.seq < $1.seq }

        // A loan with no recorded start is one whose anchors were lost; the fallback bounds the
        // window rather than letting it run back to the beginning of the stores.
        let loanStart = loanStartedAt ?? offer.handedBackAt.addingTimeInterval(-.hours(2))
        let input = LoanReconciler.Input(
            events: events,
            schedule: deps.settings().basalRateSchedule,
            loanStart: loanStart,
            loanEnd: offer.handedBackAt,

            isFinalHandback: isFinal)
        let outcome = LoanReconciler.reconcile(input)

        if auditThisOffer {
            let expected = LoanReconciler.expectedInsulin(events: allStagedEvents, schedule: deps.settings().basalRateSchedule,
                                                          from: loanStart, to: offer.handedBackAt)

            // Provisional, from the WATCH's own reading of the pod. It is reported, not ruled
            // on: the verdict waits for this phone to read the pod itself.
            let delivered = offer.odometer.map { $0.deliveredLatest - $0.deliveredAtStart }
            // This drain's total read two ways: continuous, and floored to whole pod pulses.
            // The gap between them is the quantization the expectation models, so having both
            // in the log tells a real discrepancy apart from pulse arithmetic.
            let drainCont = outcome.doses.reduce(0.0) { $0 + $1.programmedUnits }
            let drainFloor = outcome.doses.reduce(0.0) { $0 + (($1.programmedUnits * 20).rounded(.down) / 20) }
            let loanMin = offer.handedBackAt.timeIntervalSince(loanStart) / 60
            handbackDiag(offer.epoch, String(format:
                "reconcile[provisional]: delivered=%@ expected=%.3f residual=%@ (tol 0.05) · thisDrain cont=%.3f floor=%.3f · loanMin=%.0f cycles=%d fresh=%@",
                delivered.map { String(format: "%.3f", $0) } ?? "n/a", expected,
                delivered.map { String(format: "%+.3f", $0 - expected) } ?? "n/a",
                drainCont, drainFloor,
                loanMin, allStagedEvents.count, offer.odometer?.freshenSucceeded == true ? "Y" : "N"))

            // Leave a verdict owed. It cannot be settled from the watch's own numbers: the
            // reading that decides it has to come from the pod once this phone can reach it.
            // Accepted checkpoints narrow the window to the last unreconciled stretch.
            if isFinal, let start = offer.odometer?.deliveredAtStart {
                let windowStart = auditBase?.units ?? start
                let windowExpected = auditBase.map {
                    LoanReconciler.expectedInsulin(events: allStagedEvents, schedule: deps.settings().basalRateSchedule,
                                                   from: $0.asOf, to: offer.handedBackAt)
                } ?? expected
                if checkpointsThisLoan > 0 {
                    handbackDiag(offer.epoch, String(format:
                        "[checkpoint] verdict window narrowed by %d checkpoint(s): anchor %.3f U (loan start %.3f), window expected %.3f (loan %.3f)",
                        checkpointsThisLoan, windowStart, start, windowExpected, expected))
                }
                pendingHandbackAudit = PendingHandbackAudit(
                    epoch: offer.epoch, deliveredAtStart: windowStart, expected: windowExpected,
                    loanMinutes: loanMin, cycles: allStagedEvents.count,
                    watchLatest: offer.odometer?.deliveredLatest,
                    watchFreshened: offer.odometer?.freshenSucceeded == true,
                    takeoverUnits: start, wholeLoanExpected: expected)
            }
        }

        let doses = outcome.doses

        // The interim's still-open rate record is acked but NOT marked committed, so it drains
        // again at the end and lands finished. Decoupling the ack cursor from `committedIDs` is
        // what lets the watch finalize while the phone still owes that record a real write.
        let committable = events.filter { $0.id != outcome.openEventID }

        // Drop impossible doses INDIVIDUALLY and name what went. An atomic batch failure teaches
        // nothing and wedges the store context, while a dose with a slightly wrong duration
        // validates cleanly and corrupts IOB in silence.
        let sane = doses.filter { $0.endDate >= $0.startDate }
        if sane.count != doses.count {
            let bad = doses.filter { $0.endDate < $0.startDate }
            handbackDiag(offer.epoch, "** DROPPED \(bad.count) impossible dose(s) (end before start) — writing \(sane.count) of \(doses.count). First: \(bad[0].type) \(bad[0].startDate) -> \(bad[0].endDate) **")
        }

        let writeStart = deps.now()
        handbackDiag(offer.epoch, "write START \(sane.count) dose(s) (final=\(isFinal))")

        // The write. No ack is sent from the failure paths below: staying in .reconciling with
        // nothing acked leaves the watch's own resend as the retry, which is the behaviour we
        // want — never dose on records that only half landed.
        commitInFlight = true
        deps.addPumpEvents(newPumpEvents(from: sane), offer.handedBackAt) { [weak self] error in
            guard let self = self else { return }
            self.queue.async {
                if let error = error {
                    self.commitInFlight = false
                    self.handbackDiag(offer.epoch, "write FAILED: \(String(describing: error))")
                    os_log("Reconcile write failed: %{public}@", log: self.log, type: .fault, String(describing: error))

                    if let reason = self.pendingForceReclaimReason {
                        self.pendingForceReclaimReason = nil
                        self.forceReclaimToOwner(reason: reason)
                    }
                    return
                }

                var backfillEarliestStart: Date? = nil

                let finishCommit: (Error?) -> Void = { [weak self] backfillError in
                    guard let self = self else { return }
                    self.queue.async {
                        // Releasing the latch is the first thing every exit from here does,
                        // including the failure paths — a latch left set stops the phone
                        // committing anything for the rest of the session.
                        self.commitInFlight = false
                        if let backfillError = backfillError {
                            self.handbackDiag(offer.epoch, "backfill FAILED: \(String(describing: backfillError))")
                            os_log("Loan dose backfill failed: %{public}@", log: self.log, type: .fault, String(describing: backfillError))

                            if let reason = self.pendingForceReclaimReason {
                                self.pendingForceReclaimReason = nil
                                self.forceReclaimToOwner(reason: reason)
                            }
                            return
                        }

                        if !isStale {
                            for carb in outcome.carbs {
                                self.deps.addCarb(carb.entry, carb.eventID.uuidString) { _ in }
                            }

                            for gone in outcome.deletedCarbs {
                                self.handbackDiag(offer.epoch, String(format: "carb DELETE from wrist — %.0f g @ %@ sync=%@", gone.grams, String(describing: gone.startDate), gone.syncIdentifier.map { String($0.prefix(8)) } ?? "nil"))
                                self.deps.deleteCarb(gone) { error in

                                    self.handbackDiag(offer.epoch, error == nil
                                        ? String(format: "carb DELETE applied on phone — %.0f g", gone.grams)
                                        : String(format: "carb DELETE MISSED on phone — %.0f g: %@", gone.grams, String(describing: error!)))
                                }
                            }
                        } else if !outcome.carbs.isEmpty {
                            // Carbs are gated on the loan being live, unlike insulin. A carb
                            // entry carries no identity of its own and the store mints a fresh
                            // one per add, so this gate is the only thing standing between a
                            // replay and a duplicate meal — and a duplicate mirrors into every
                            // later grant as phantom carbs on board.
                            self.handbackDiag(offer.epoch, "stale offer — \(outcome.carbs.count) carb(s) NOT committed (a dead loan cannot add carbs)")
                        }

                        // Overrides apply on interim drains too: an override the user set on the
                        // wrist should follow the pod home as soon as it is known, not only when
                        // the loan ends.
                        if !isStale, let change = outcome.overrideChange {
                            self.applyWatchOverride(change, epoch: offer.epoch, isFinal: isFinal)
                        }

                        let newCursor = events.map(\.seq).max() ?? self.committedCursor
                        if !isStale {
                            self.committedCursor = max(self.committedCursor, newCursor)
                            self.committedIDs.formUnion(committable.map(\.id))
                            self.persistCommittedIDs()
                            // The ack, and only now that the store has it.
                            self.sendMessage(.handbackAck(HandbackAck(epoch: self.epoch, committedCursor: self.committedCursor)))
                            self.handbackDiag(self.epoch, String(format: "write DONE %.0fms → ACK cursor %d", self.deps.now().timeIntervalSince(writeStart) * 1000, self.committedCursor))
                            if isFinal, self.state == .reconciling {
                                self.finishLoanAfterCommit()
                            } else if !isFinal {
                                os_log("Interim drain committed to cursor %d — watch still dosing", log: self.log, type: .default, self.committedCursor)
                            }
                        } else {
                            // A stale offer is acked so the watch can let go of a loan the
                            // phone has already closed, but nothing about the current loan's
                            // dedup state moves.
                            self.sendMessage(.handbackAck(HandbackAck(epoch: offer.epoch, committedCursor: newCursor, stale: true)))
                        }

                        // Outside the staleness gate deliberately: ANY back-dated insulin write
                        // invalidates the counteraction memo from its earliest dose onward. That
                        // memo is append-only, so without this the bins over the loan window go
                        // on attributing the watch's insulin to unexplained glucose movement,
                        // and carb absorption over-attributes until the app restarts. The
                        // backfill door posts no store notification at all, so nothing else
                        // would tell the algorithm its history changed.
                        if let earliest = (sane.map(\.startDate) + (backfillEarliestStart.map { [$0] } ?? [])).min() {
                            self.deps.insulinHistoryRewritten(earliest)
                        }

                        self.retireGapBookingIfExplained(
                            offerEpoch: offer.epoch,
                            dosesJustCommitted: sane,
                            carbsJustCommitted: isStale ? 0 : outcome.carbs.count)
                        self.drainAfterCommit()
                    }
                }

                // The second door. Pump events cannot land a basal-shaped dose behind the
                // delivery store's immutable boundary, so the loan window is re-written here by
                // store identity, truncated first because this path bypasses the store's own
                // reconciliation. A stale offer SKIPS it entirely: a dead loan may only speak
                // for its own records, never rewrite the window.
                let backfillOutcome = LoanReconciler.reconcile(LoanReconciler.Input(
                    events: allStagedEvents,
                    schedule: self.deps.settings().basalRateSchedule,
                    loanStart: loanStart,
                    loanEnd: offer.handedBackAt,
                    isFinalHandback: isFinal))
                let backfill = self.storeIdentifiedDoses(from: self.truncatingOverlaps(
                    backfillOutcome.doses.filter { $0.endDate >= $0.startDate }))
                if isStale || backfill.isEmpty {
                    if isStale {
                        self.handbackDiag(offer.epoch, "backfill SKIPPED — a stale offer speaks only for its own records (#102)")
                    }
                    finishCommit(nil)
                } else {
                    self.handbackDiag(offer.epoch, "backfill \(backfill.count) loan-window dose(s) by store identity (e44 boundary)")
                    backfillEarliestStart = backfill.map(\.startDate).min()
                    self.deps.backfillDoses(backfill, finishCommit)
                }
            }
        }
    }

    /// Runs once a write has landed and `commitInFlight` is clear: first anything that deferred
    /// behind it, then one coalesced offer. The recursion through `handleHandbackOffer` is how
    /// the queue empties, one commit at a time.
    func drainAfterCommit() {
        if let reason = pendingForceReclaimReason {
            pendingForceReclaimReason = nil
            forceReclaimToOwner(reason: reason)
        }
        if let next = coalescedOffers.popFirst()?.value {
            handleHandbackOffer(next)
        }
    }

    /// Applies an override the user set or cleared on the wrist.
    ///
    /// Idempotent by the override's OWN identifier, because a drained record can be replayed —
    /// applying it twice would restart a timed override. And a clear is skipped when the phone
    /// holds none: replayed, it would cancel an override the user set here after the loan ended.
    private func applyWatchOverride(_ change: LoanReconciler.OverrideChange, epoch: Int, isFinal: Bool) {
        let current = deps.scheduleOverride()
        let phase = isFinal ? "final" : "interim"
        switch change {
        case .set(let override):
            guard current?.syncIdentifier != override.syncIdentifier else {
                os_log("[override] from watch: SKIPPED — %{public}@ already applied (sync %{public}@)",
                       log: log, type: .default, Self.overrideNameForLog(override), override.syncIdentifier.uuidString)
                handbackDiag(epoch, "[override] SKIPPED (already applied) \(Self.overrideNameForLog(override))")
                return
            }
            deps.applyScheduleOverride(override)
            let ends = override.duration.isInfinite ? "indefinite" : ISO8601DateFormatter().string(from: override.scheduledEndDate)
            os_log("[override] from watch: APPLIED %{public}@ · insulin needs %.0f%% · target %{public}@ · ends %{public}@ · sync %{public}@ (%{public}@ drain)",
                   log: log, type: .default, Self.overrideNameForLog(override),
                   override.settings.effectiveInsulinNeedsScaleFactor * 100,
                   Self.targetForLog(override), ends, override.syncIdentifier.uuidString, phase)
            handbackDiag(epoch, String(format: "[override] APPLIED %@ · needs %.0f%% · target %@ · ends %@ (%@ drain)",
                                       Self.overrideNameForLog(override),
                                       override.settings.effectiveInsulinNeedsScaleFactor * 100,
                                       Self.targetForLog(override), ends, phase))
        case .cleared:
            guard current != nil else {
                os_log("[override] from watch: SKIPPED clear — the phone holds no override", log: log, type: .default)
                handbackDiag(epoch, "[override] SKIPPED clear (phone already has none)")
                return
            }
            deps.applyScheduleOverride(nil)
            os_log("[override] from watch: CLEARED %{public}@ — phone schedules resolve unscaled again (%{public}@ drain)",
                   log: log, type: .default, current.map(Self.overrideNameForLog) ?? "—", phase)
            handbackDiag(epoch, "[override] CLEARED \(current.map(Self.overrideNameForLog) ?? "—") (\(phase) drain)")
        }
    }

    static func overrideNameForLog(_ override: TemporaryScheduleOverride) -> String {
        switch override.context {
        case .preMeal: return "pre-meal"
        case .activity(let preset): return "\(preset.activityType.symbol) \(preset.activityType.name)"
        case .preset(let preset): return "\(preset.symbol) \(preset.name)"
        case .custom: return "custom"
        }
    }

    private static func targetForLog(_ override: TemporaryScheduleOverride) -> String {
        guard let range = override.settings.targetRange else { return "unchanged" }
        return String(format: "%.0f-%.0f",
                      range.lowerBound.doubleValue(for: .milligramsPerDeciliter),
                      range.upperBound.doubleValue(for: .milligramsPerDeciliter))
    }

    /// Closes the loan once its final records are in the books: the phone takes the pod link
    /// back, resumes dosing, and clears the staging area.
    private func finishLoanAfterCommit() {
        cancelReclaimLadder()
        cancelNotification(id: NotificationID.duration)
        cancelNotification(id: NotificationID.paused)

        // A close that finds fresh evidence of a NEWER live loan commits its books but does not
        // resume custody. This is an old loan's final offer arriving late while its successor is
        // already streaming; taking the pod here would reclaim it out from under a watch that is
        // mid-session and cancel the temp it is running.
        if supersededByLiveLoan(epoch) {
            let liveEpoch = newestForeignLoanEvidence?.epoch ?? epoch + 1
            pendingRevoke = false
            state = .owner
            staged = [:]
            stagedTombstones = []
            persistStaged()
            pendingHandbackAudit = nil
            clearAuditAnchors()
            PhoneLog.event("mirror", "drain e\(epoch) closed UNDER live e\(liveEpoch) — books committed, audit moot, custody NOT resumed [mirror]")
            engageInferredLoanYield(evidence: "superseding loan e\(liveEpoch) streamed during the e\(epoch) drain")
            return
        }
        // The ordinary close: take the radio back, resume dosing, and let the state's own
        // observer open the settle window that proves the pod is really here.
        reclaimPodConnection()
        pendingRevoke = false
        state = .owner
        deps.setAutomaticDosingPaused(false)
        staged = [:]
        stagedTombstones = []
        persistStaged()

        UserDefaults.standard.removeObject(forKey: Keys.deliveredAtGrant)
    }

}
