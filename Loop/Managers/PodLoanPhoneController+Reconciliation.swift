//
//  PodLoanPhoneController+Reconciliation.swift
//  Loop
//
//  Part of PodLoanPhoneController (see PodLoanPhoneController.swift). Split by concern; stored
//  properties live in the core class.
//
//  Getting the watch's insulin into the phone's books, and judging whether it is all there.
//
//  Two doors into the dose store, used together on every hand-back: pump events, which is how
//  doses normally arrive, and an identified upsert that can land records behind the store's
//  immutable boundary. Both must agree on identity, or one physical dose becomes two.
//
//  The verdict is deliberately asymmetric. Insulin the pod delivered that our records do not
//  contain stops automatic dosing; records claiming more than the pod delivered only warn.
//  Where no verdict is possible at all, the loop opens and a placeholder keeps IOB conservative
//  until the real records arrive.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    /// Wraps doses for the ordinary pump-event door.
    ///
    /// Identity lives in `raw`, hex-decoded, and nowhere else: LoopKit discards an incoming
    /// `DoseEntry.syncIdentifier` on this path and derives identity from `raw` instead. Seeding
    /// `raw` with the identifier's own bytes gives one physical dose two identities — hex and
    /// hex-of-hex — which blinds every dedup layer underneath and echoes the dose into IOB.
    func newPumpEvents(from doses: [DoseEntry]) -> [NewPumpEvent] {
        doses.compactMap { dose in
            guard let syncID = dose.syncIdentifier else { return nil }

            return NewPumpEvent(date: dose.startDate,
                                dose: dose,
                                raw: LoanSeedIdentity.raw(forSyncIdentifier: syncID),
                                title: Self.pumpEventTitle(for: dose.type))
        }
    }

    /// Cuts each rate record at the start of the next one, the way the store's own
    /// reconciliation would.
    ///
    /// The upsert this feeds bypasses that reconciliation, so it has to do the work itself: an
    /// untruncated span would REPLACE the already-truncated row and inflate IOB, and it would do
    /// so on every hand-back. Boluses pass through untouched — they do not supersede anything.
    func truncatingOverlaps(_ doses: [DoseEntry]) -> [DoseEntry] {
        var out: [DoseEntry] = []
        var lastRate: DoseEntry?
        for dose in doses.sorted(by: { $0.startDate < $1.startDate }) {
            guard dose.type != .bolus else {
                out.append(dose)
                continue
            }
            if let last = lastRate {
                let end = Swift.min(last.endDate, dose.startDate)
                if end > last.startDate {
                    if let trimmed = last.trimmed(from: nil, to: end, syncIdentifier: last.syncIdentifier) {
                        out.append(trimmed)
                    }
                }
            }
            lastRate = dose
        }

        if let last = lastRate, last.endDate > last.startDate { out.append(last) }
        return out
    }

    /// What a finished loan dose actually delivered, for records that did not carry it.
    /// A mutable dose is still running and has no answer yet; leaving it nil is correct.
    private static func resolvedDeliveredUnits(for dose: DoseEntry) -> Double? {
        guard !dose.isMutable else { return nil }
        switch dose.type {
        case .bolus:     return dose.programmedUnits
        case .tempBasal: return dose.unitsInDeliverableIncrements
        default:         return nil
        }
    }

    /// Restates doses in the identity the DOSE STORE uses, for the backfill door.
    ///
    /// That door is needed because the pump-event path cannot land a basal-shaped dose behind
    /// the delivery store's last immutable basal end date. After a force reclaim, a journal that
    /// arrives late therefore writes its pump-event rows while none of its temps reach the
    /// books: the bolus survives, the temps vanish, and IOB under-counts.
    ///
    /// The identifier is the same bytes the pump-event path ends up with, rendered as hex, so
    /// both doors name one dose the same way. `deliveredUnits` is stamped here for the same
    /// reason the truncation above happens here — this path does none of the store's own tidying.
    func storeIdentifiedDoses(from doses: [DoseEntry]) -> [DoseEntry] {
        doses.compactMap { dose in
            guard let syncID = dose.syncIdentifier else { return nil }
            return DoseEntry(type: dose.type,
                             startDate: dose.startDate,
                             endDate: dose.endDate,
                             value: dose.unit == .unitsPerHour ? dose.unitsPerHour : dose.programmedUnits,
                             unit: dose.unit,
                             decisionId: dose.decisionId,
                             deliveredUnits: dose.deliveredUnits ?? Self.resolvedDeliveredUnits(for: dose),
                             description: dose.description,
                             syncIdentifier: LoanSeedIdentity.raw(forSyncIdentifier: syncID).hexadecimalString,
                             scheduledBasalRate: dose.scheduledBasalRate,
                             insulinType: dose.insulinType,
                             automatic: dose.automatic,
                             manuallyEntered: dose.manuallyEntered,
                             isMutable: dose.isMutable,
                             wasProgrammedByPumpUI: dose.wasProgrammedByPumpUI)
        }
    }

    static func pumpEventTitle(for type: DoseType) -> String {
        switch type {
        case .bolus:     return "Bolus"
        case .tempBasal: return "Temp Basal"
        case .basal:     return "Basal"
        case .suspend:   return "Suspend"
        case .resume:    return "Resume"
        }
    }

    /// Blocking read of the live progress. Anything drawing the tile must use
    /// `reclaimProgressForUI`, which reads the mirror and never waits.
    var reclaimProgress: ReclaimProgress? {
        return Self.reclaimProgress(from: queue.sync { uiSnapshot() }, now: deps.now())
    }

    /// Insulin the pod delivered that our records cannot account for. Beyond this the loop
    /// OPENS: there is insulin in the body the algorithm cannot see, and a closed loop would
    /// stack more on top of it.
    private static let openLoopPositiveResidual: Double = 0.20

    /// Records claiming more delivery than the pod made. This direction only warns. It is
    /// phantom IOB — self-limiting, it decays out within the insulin action duration, and it
    /// makes the loop cautious. Opening the loop here would make the real failure, which is
    /// under-treatment, worse.
    private static let warnNegativeResidual: Double = 0.20

    /// The verdict after a clean hand-back. Both directions speak on the time-sensitive channel
    /// even though only one stops dosing: a plain notification can be swallowed by a Focus mode,
    /// leaving a recording failure with no witness at all.
    ///
    /// No placeholder is booked here, unlike after a force reclaim. The watch's records did
    /// arrive, so a residual is a disagreement between two measurements rather than insulin
    /// missing from the books.
    func applyReconciliationVerdict(residual: Double, epoch: Int) {
        if residual > Self.openLoopPositiveResidual {
            handbackDiag(epoch, String(format:
                "** R32 OPEN LOOP — residual %+.3f U exceeds +%.2f: the pod delivered insulin our records do not contain. Automatic dosing STOPPED. **",
                residual, Self.openLoopPositiveResidual))
            deps.openLoopForUncertainReconciliation()
            armOpenLoopReminder()

            deps.issueUrgentNotice("Loop Open — Unexplained Insulin",
                             String(format: "The pod delivered %.2f U more than the watch session's records account for. Automatic dosing is off until you turn it back on. Check your insulin on board before dosing.", residual))
        } else if residual < -Self.warnNegativeResidual {
            handbackDiag(epoch, String(format:
                "** R32 WARN — residual %+.3f U beyond -%.2f: records claim more delivery than the pod made (phantom IOB). Still looping — this direction under-doses and decays out. **",
                residual, Self.warnNegativeResidual))

            deps.issueUrgentNotice("Insulin On Board May Be Overstated",
                             String(format: "The watch session's records account for %.2f U more than the pod delivered. Automatic dosing continues; expect it to run cautious until this clears.", -residual))
        }
    }

    /// The verdict after a force reclaim. Same bands and same channel as a clean hand-back; the
    /// difference is that this is where the pause held since the reclaim is lifted, and that an
    /// unexplained positive gets a placeholder booked for it as well as an open loop.
    func applyForceReclaimVerdict(residual: Double, epoch: Int) {
        deps.setAutomaticDosingPaused(false)
        if residual > Self.openLoopPositiveResidual {
            handbackDiag(epoch, String(format:
                "** R37 OPEN LOOP — force-reclaim residual %+.3f U exceeds +%.2f: the pod delivered insulin the records cannot explain (watch died mid-session?). Automatic dosing STOPPED. **",
                residual, Self.openLoopPositiveResidual))
            deps.openLoopForUncertainReconciliation()
            armOpenLoopReminder()

            var body = String(format:
                "%.2f U on the pod isn't in the watch's records, so automatic dosing is OFF.", residual)
            if Self.bookUnattributedInsulinOnForceReclaim {
                bookGapDose(units: residual, epoch: epoch)
                body += " It's booked as a bolus to keep IOB conservative; the watch's real records replace it about 2 min after the phone sees the watch again."
            } else {
                body += " Check your insulin on board before dosing."
            }
            deps.issueUrgentNotice("Loop Open — Unverified Insulin", body)
        } else if residual < -Self.warnNegativeResidual {
            handbackDiag(epoch, String(format:
                "** R37 WARN — force-reclaim residual %+.3f U beyond -%.2f: records claim more than the pod delivered (phantom IOB). Looping resumes — this direction under-doses and decays out. **",
                residual, Self.warnNegativeResidual))

            deps.issueUrgentNotice("Insulin On Board May Be Overstated",
                             String(format: "After the watch session ended abruptly, records account for %.2f U more than the pod delivered. Automatic dosing resumes; expect it to run cautious until this clears.", -residual))
        } else {
            handbackDiag(epoch, String(format:
                "R37 audit CLEAN — residual %+.3f U within ±%.2f; automatic dosing resumes", residual, Self.openLoopPositiveResidual))
        }
    }

    /// Books the unexplained insulin as a placeholder so IOB accounts for it while the real
    /// records are missing.
    ///
    /// MANUALLY ENTERED, and stamped at the reclaim instant. Manual doses keep the identifier
    /// they are given as their store identity — pump events overwrite it — and that is the only
    /// reason this can be found and deleted later. "Now" gives it zero decay, so IOB
    /// over-counts rather than under-counts until the truth arrives.
    func bookGapDose(units: Double, epoch: Int) {
        let now = deps.now()
        let sync = Self.gapSyncIdentifier(epoch: epoch)
        let entry = DoseEntry(type: .bolus, startDate: now, endDate: now,
                              value: units, unit: .units, decisionId: nil, deliveredUnits: units,
                              syncIdentifier: sync, manuallyEntered: true)
        deps.bookGapDose(entry) { [weak self] ok in
            guard let self = self else { return }
            self.queue.async {
                if ok {
                    UserDefaults.standard.set(["epoch": epoch, "units": units,
                                               "bookedAt": now.timeIntervalSince1970],
                                              forKey: Keys.gapBooking)

                    self.armPlaceholderReminders(units: units, bookedAt: now)
                    self.handbackDiag(epoch, String(format: "R37 gap BOOKED — %.2f U bolus @ reclaim (sync %@); retired if the watch returns", units, sync))
                } else {
                    self.handbackDiag(epoch, String(format: "** R37 gap booking FAILED to save — %.2f U is NOT in the books. Loop is open; dose by hand with that in mind. **", units))
                }
            }
        }
    }

    /// One placeholder per loan, findable by epoch alone — the delete has nothing else to go on.
    private static func gapSyncIdentifier(epoch: Int) -> String { "PODLOAN-ODOGAP-e\(epoch)" }

    /// Launch-time retry for a placeholder whose delete failed AFTER the real records landed.
    func retryPersistedGapDeleteIfAny() {
        guard let gap = UserDefaults.standard.dictionary(forKey: Keys.gapBooking),
              let gapEpoch = gap["epoch"] as? Int, let booked = gap["units"] as? Double else { return }

        // A standing placeholder is left alone. Only a failed delete earns a retry: otherwise
        // every launch quietly removes a conservative IOB booking that nothing has replaced —
        // and having lost the watch for good is exactly when that margin matters most.
        guard gap["deleteFailedAfterRecords"] as? Bool == true else {
            handbackDiag(gapEpoch, String(format: "R37 gap placeholder STANDS — %.2f U still unexplained; the watch never returned, so the booking is left in place", booked))
            return
        }
        let sync = Self.gapSyncIdentifier(epoch: gapEpoch)
        handbackDiag(gapEpoch, String(format: "R37 gap DELETE retrying at launch — %.2f U placeholder (sync %@) was unretired last session", booked, sync))
        deps.deleteGapDose(sync) { [weak self] ok in
            guard let self = self else { return }
            self.queue.async {
                if ok {
                    UserDefaults.standard.removeObject(forKey: Keys.gapBooking)

                    if let bookedAt = (gap["bookedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) {
                        self.deps.insulinHistoryRewritten(bookedAt)
                    }
                    self.cancelPlaceholderReminders()
                    self.handbackDiag(gapEpoch, String(format: "R37 gap RETIRED on launch retry — %.2f U placeholder cleared", booked))
                } else {
                    self.handbackDiag(gapEpoch, String(format: "** R37 gap DELETE FAILED AGAIN at launch — %.2f U placeholder still stands; will retry next launch or the next matching offer **", booked))
                }
            }
        }
    }

    /// Retires the placeholder once the watch's real records for THAT loan have been written.
    ///
    /// Called after the commit, never before. A moment where both the estimate and the real
    /// doses are booked over-states IOB briefly, which is survivable; a moment where neither is
    /// booked is not. A failed delete is recorded so the next launch can try again.
    func retireGapBookingIfExplained(offerEpoch: Int, dosesJustCommitted: [DoseEntry], carbsJustCommitted: Int) {
        guard let gap = UserDefaults.standard.dictionary(forKey: Keys.gapBooking),
              let gapEpoch = gap["epoch"] as? Int, gapEpoch == offerEpoch,
              let booked = gap["units"] as? Double else { return }
        // An offer that committed nothing is not evidence that the watch's records arrived — an
        // empty drain would otherwise retire a booking that still stands for real insulin.
        guard !dosesJustCommitted.isEmpty else { return }

        let boluses = dosesJustCommitted.filter { $0.type == .bolus }
        let bolusUnits = boluses.reduce(0.0) { $0 + ($1.deliveredUnits ?? $1.programmedUnits) }
        let rateCount = dosesJustCommitted.count - boluses.count
        let rateGross = dosesJustCommitted.filter { $0.type != .bolus }.reduce(0.0) { $0 + $1.programmedUnits }
        let sync = Self.gapSyncIdentifier(epoch: gapEpoch)
        deps.deleteGapDose(sync) { [weak self] ok in
            guard let self = self else { return }
            self.queue.async {
                if ok {
                    UserDefaults.standard.removeObject(forKey: Keys.gapBooking)

                    if let bookedAt = (gap["bookedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) {
                        self.deps.insulinHistoryRewritten(bookedAt)
                    }
                    self.handbackDiag(gapEpoch, String(format:
                        "R37 gap RETIRED — the watch returned with %d real dose(s): %.2f U bolus + %d rate record(s) (%.2f U gross programmed, pre-truncation) and %d carb(s); the %.2f U estimate is replaced by actual timing",
                        dosesJustCommitted.count, bolusUnits, rateCount, rateGross, carbsJustCommitted, booked))

                    self.cancelPlaceholderReminders()
                    self.deps.issueUrgentNotice("Watch Records Recovered",
                                          String(format: "The watch is back. Its records (%d doses, %d carbs) replaced the estimated %.2f U bolus — your IOB and COB now reflect actual timing.",
                                                 dosesJustCommitted.count, carbsJustCommitted, booked))
                } else {
                    var marked = gap
                    marked["deleteFailedAfterRecords"] = true
                    UserDefaults.standard.set(marked, forKey: Keys.gapBooking)
                    self.handbackDiag(gapEpoch, String(format:
                        "** R37 gap DELETE FAILED — the %.2f U placeholder AND the real records are both booked; IOB is over-counted until this retries **", booked))
                }
            }
        }
    }

    /// Keeps a rolling series of hand-back residuals in the log. DIAGNOSTICS ONLY: nothing reads
    /// it back to change a threshold, and it must not ask anyone to review bounds that have
    /// already been settled. Callers bank clean hand-backs alone.
    func bankResidual(_ residual: Double, worstWindow: Double, epoch: Int) {
        // A bounded window of recent loans. Long enough to see a trend, short enough that an old
        // build's behaviour does not colour the current one.
        var history = (UserDefaults.standard.array(forKey: Keys.residualHistory) as? [Double]) ?? []
        history.append(residual)
        if history.count > 40 { history.removeFirst(history.count - 40) }
        UserDefaults.standard.set(history, forKey: Keys.residualHistory)

        var windows = (UserDefaults.standard.array(forKey: Keys.windowWorstHistory) as? [Double]) ?? []
        windows.append(worstWindow)
        if windows.count > 40 { windows.removeFirst(windows.count - 40) }
        UserDefaults.standard.set(windows, forKey: Keys.windowWorstHistory)

        let mean = history.reduce(0, +) / Double(history.count)
        let worst = history.map(abs).max() ?? 0
        handbackDiag(epoch, String(format:
            "residual bank: n=%d mean=%+.3f worst=|%.3f| min=%+.3f max=%+.3f · window-worst this loan |%.3f| (series n=%d max |%.3f|) — diagnostics only, R32 closed 2026-08-27 (window verdict ±%.2f U)",
            history.count, mean, worst, history.min() ?? 0, history.max() ?? 0,
            worstWindow, windows.count, windows.map(abs).max() ?? 0,
            Self.openLoopPositiveResidual))
    }

    /// Blocking reads of the live state. Safe from a message-handling context; never from the
    /// controller's own queue, which deadlocks, and never from a UI draw path, which would
    /// freeze behind a stalled settle. The tile reads the mirror instead.
    var isPodLoanedOut: Bool {
        return queue.sync { state != .owner || yieldingToInferredLoan }
    }

    var isReclaimSettling: Bool {
        return queue.sync {
            guard state == .owner, let started = reclaimStartedAt else { return false }
            if deps.now().timeIntervalSince(started) >= Self.reclaimSettleTimeout { return false }

            return reclaimVerifiedAt == nil
        }
    }

    /// Where the audit window currently starts: a pod delivery total and the instant it was
    /// read. It describes ONE loan and is consumed when that loan is judged.
    struct AuditBase {
        let units: Double
        let asOf: Date
    }

    /// Same band as the final verdict, so a window that would have been acceptable at the end is
    /// acceptable mid-loan.
    static let checkpointBand: Double = 0.20

    /// Tries to close off the stretch of loan since the last base, using an odometer reading the
    /// watch sent mid-session. A window that reconciles advances the base, which narrows what
    /// the final verdict has to explain; one that does not is CARRIED — the base stays put and
    /// the unreconciled stretch remains inside the window.
    func considerCheckpoint(_ snap: LoanOdometerSnapshot, context: String) {
        guard let asOf = snap.asOf else { return }
        guard let base = auditBase else { return }
        // A reading no newer than the base closes no window.
        guard asOf > base.asOf else { return }
        // A total that has gone backwards is not a reading of this pod's progress; advancing the
        // base onto it would hide real delivery.
        guard snap.deliveredLatest >= base.units else {
            PhoneLog.event("loan", String(format: "e%d [checkpoint] REJECTED (%@): odometer regressed %.3f → %.3f",
                                          epoch, context, base.units, snap.deliveredLatest))
            return
        }
        // The whole staged set, committed or not: the expectation is about what the pod was
        // asked to deliver over this window, not about what the phone has written down.
        let events = staged.values
            .filter { !stagedTombstones.contains($0.id) }
            .sorted { $0.seq < $1.seq }
        // A bolus stamped exactly at this interior boundary belongs to the NEXT window: the pod
        // had not metered it when this reading was taken, and counting it in both windows would
        // double it.
        let expected = LoanReconciler.expectedInsulin(events: events, schedule: deps.settings().basalRateSchedule,
                                                      from: base.asOf, to: asOf,
                                                      includingBolusesAtEnd: false)
        let delivered = snap.deliveredLatest - base.units

        // Quantize to milli-units before comparing, so the band turns on the pulse grid rather
        // than on binary rounding dust.
        let residual = ((delivered - expected) * 1000).rounded() / 1000
        if abs(residual) <= Self.checkpointBand {
            checkpointsThisLoan += 1
            worstWindowThisLoan = max(worstWindowThisLoan, abs(residual))
            auditBase = AuditBase(units: snap.deliveredLatest, asOf: asOf)
            os_log("Checkpoint ACCEPTED (%{public}@): window %.1f min reconciled (delivered %.3f expected %.3f residual %+.3f) — base → %.3f U",
                   log: log, type: .default, context, asOf.timeIntervalSince(base.asOf) / 60,
                   delivered, expected, residual, snap.deliveredLatest)
            PhoneLog.event("loan", String(format: "e%d [checkpoint] #%d ACCEPTED (%@): %.1f min window, residual %+.3f — base %.3f U",
                                          epoch, checkpointsThisLoan, context,
                                          asOf.timeIntervalSince(base.asOf) / 60, residual, snap.deliveredLatest))
        } else {
            os_log("Checkpoint CARRIED (%{public}@): window residual %+.3f exceeds ±%.2f (delivered %.3f expected %.3f) — base stays at %.3f U",
                   log: log, type: .error, context, residual, Self.checkpointBand,
                   delivered, expected, base.units)
            PhoneLog.event("loan", String(format: "e%d [checkpoint] CARRIED (%@): residual %+.3f beyond ±%.2f — window stays open",
                                          epoch, context, residual, Self.checkpointBand))
        }
    }

    /// A verdict owed against the pod's own delivery total, waiting for the reclaim round-trip
    /// that can read it.
    struct PendingHandbackAudit {
        /// `.handback` came from the watch's final offer; `.forceReclaim` from the phone taking
        /// the pod without one. Only the latter survives a relaunch, and only the latter books a
        /// placeholder for what it cannot explain.
        enum Flavor: String { case handback, forceReclaim }
        let epoch: Int
        /// Start of the VERDICT window, which accepted checkpoints may have moved well past the
        /// start of the loan.
        let deliveredAtStart: Double
        let expected: Double
        let loanMinutes: Double
        let cycles: Int
        let watchLatest: Double?
        let watchFreshened: Bool
        var flavor: Flavor = .handback

        /// The whole loan, start to end, for the drift tripwire. Reported, never acted on.
        var takeoverUnits: Double? = nil
        var wholeLoanExpected: Double? = nil
    }

}
