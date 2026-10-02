//
//  PodLoanPhoneController+Reconciliation.swift
//  Loop
//
//  Getting the watch's insulin into the phone's books and judging it. Unexplained delivery
//  opens the loop; over-claimed records only warn.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    /// Identity lives only in `raw` on this path; seeding it with the identifier's bytes would
    /// give one dose two identities.
    func newPumpEvents(from doses: [DoseEntry]) -> [NewPumpEvent] {
        doses.compactMap { dose in
            guard let syncID = dose.syncIdentifier else { return nil }

            return NewPumpEvent(date: dose.startDate,
                                dose: dose,
                                raw: LoanSeedIdentity.raw(forSyncIdentifier: syncID),
                                title: Self.pumpEventTitle(for: dose.type))
        }
    }

    /// Cuts each rate record at the next one's start, as the store's reconciliation would; the
    /// upsert path skips that reconciliation.
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

    /// A still-running dose has no delivered answer yet.
    private static func resolvedDeliveredUnits(for dose: DoseEntry) -> Double? {
        guard !dose.isMutable else { return nil }
        switch dose.type {
        case .bolus:     return dose.programmedUnits
        case .tempBasal: return dose.unitsInDeliverableIncrements
        default:         return nil
        }
    }

    /// Doses in the dose store's identity, for the upsert path; the pump-event path cannot land
    /// basal doses behind the immutable boundary.
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

    /// Blocking; the tile uses `reclaimProgressForUI`.
    var reclaimProgress: ReclaimProgress? {
        return Self.reclaimProgress(from: queue.sync { uiSnapshot() }, now: deps.now())
    }

    /// Unexplained delivery beyond this opens the loop.
    private static let openLoopPositiveResidual: Double = 0.20

    /// Over-claimed records beyond this only warn: phantom IOB is self-limiting.
    private static let warnNegativeResidual: Double = 0.20

    /// Clean hand-back verdict; both directions notify time-sensitive. No placeholder: the
    /// records arrived.
    func applyReconciliationVerdict(residual: Double, epoch: Int) {
        if residual > Self.openLoopPositiveResidual {
            handbackDiag(epoch, String(format:
                "** OPEN LOOP — residual %+.3f U exceeds +%.2f: the pod delivered insulin our records do not contain. Automatic dosing STOPPED. **",
                residual, Self.openLoopPositiveResidual))
            deps.openLoopForUncertainReconciliation()
            armOpenLoopReminder()

            deps.issueUrgentNotice("Loop Open — Unexplained Insulin",
                             String(format: "The pod delivered %.2f U more than the watch session's records account for. Automatic dosing is off until you turn it back on. Check your insulin on board before dosing.", residual))
        } else if residual < -Self.warnNegativeResidual {
            handbackDiag(epoch, String(format:
                "** WARN — residual %+.3f U beyond -%.2f: records claim more delivery than the pod made (phantom IOB). Still looping — this direction under-doses and decays out. **",
                residual, Self.warnNegativeResidual))

            deps.issueUrgentNotice("Insulin On Board May Be Overstated",
                             String(format: "The watch session's records account for %.2f U more than the pod delivered. Automatic dosing continues; expect it to run cautious until this clears.", -residual))
        }
    }

    /// Force-reclaim verdict: lifts the reclaim pause, and books a placeholder for unexplained insulin.
    func applyForceReclaimVerdict(residual: Double, epoch: Int) {
        deps.setAutomaticDosingPaused(false)
        if residual > Self.openLoopPositiveResidual {
            handbackDiag(epoch, String(format:
                "** OPEN LOOP — force-reclaim residual %+.3f U exceeds +%.2f: the pod delivered insulin the records cannot explain (watch died mid-session?). Automatic dosing STOPPED. **",
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
                "** WARN — force-reclaim residual %+.3f U beyond -%.2f: records claim more than the pod delivered (phantom IOB). Looping resumes — this direction under-doses and decays out. **",
                residual, Self.warnNegativeResidual))

            deps.issueUrgentNotice("Insulin On Board May Be Overstated",
                             String(format: "After the watch session ended abruptly, records account for %.2f U more than the pod delivered. Automatic dosing resumes; expect it to run cautious until this clears.", -residual))
        } else {
            handbackDiag(epoch, String(format:
                "force-reclaim audit CLEAN — residual %+.3f U within ±%.2f; automatic dosing resumes", residual, Self.openLoopPositiveResidual))
        }
    }

    /// Placeholder for unexplained insulin, booked as a manual dose at the reclaim instant so it
    /// keeps its identifier and does not decay.
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
                    self.updateState { $0.gapBooking = .init(epoch: epoch, units: units, bookedAt: now) }

                    self.armPlaceholderReminders(units: units, bookedAt: now)
                    self.handbackDiag(epoch, String(format: "force-reclaim gap BOOKED — %.2f U bolus @ reclaim (sync %@); retired if the watch returns", units, sync))
                } else {
                    self.handbackDiag(epoch, String(format: "** force-reclaim gap booking FAILED to save — %.2f U is NOT in the books. Loop is open; dose by hand with that in mind. **", units))
                }
            }
        }
    }

    /// One placeholder per loan, findable by epoch alone — the delete has nothing else to go on.
    private static func gapSyncIdentifier(epoch: Int) -> String { "LOAN-AUDIT-GAP-e\(epoch)" }

    /// Launch-time retry for a placeholder whose delete failed AFTER the real records landed.
    func retryPersistedGapDeleteIfAny() {
        guard let gap = persisted.gapBooking else { return }
        let gapEpoch = gap.epoch, booked = gap.units

        // Retry only after a failed delete; a standing placeholder stays.
        guard gap.deleteFailedAfterRecords else {
            handbackDiag(gapEpoch, String(format: "force-reclaim gap placeholder STANDS — %.2f U still unexplained; the watch never returned, so the booking is left in place", booked))
            return
        }
        let sync = Self.gapSyncIdentifier(epoch: gapEpoch)
        handbackDiag(gapEpoch, String(format: "force-reclaim gap DELETE retrying at launch — %.2f U placeholder (sync %@) was unretired last session", booked, sync))
        deps.deleteGapDose(sync) { [weak self] ok in
            guard let self = self else { return }
            self.queue.async {
                if ok {
                    self.updateState { $0.gapBooking = nil }
                    if let bookedAt = gap.bookedAt { self.deps.insulinHistoryRewritten(bookedAt) }
                    self.cancelPlaceholderReminders()
                    self.handbackDiag(gapEpoch, String(format: "force-reclaim gap RETIRED on launch retry — %.2f U placeholder cleared", booked))
                } else {
                    self.handbackDiag(gapEpoch, String(format: "** force-reclaim gap DELETE FAILED AGAIN at launch — %.2f U placeholder still stands; will retry next launch or the next matching offer **", booked))
                }
            }
        }
    }

    /// Removes the placeholder after the real records are written, never before.
    func retireGapBookingIfExplained(offerEpoch: Int, dosesJustCommitted: [DoseEntry], carbsJustCommitted: Int) {
        guard let gap = persisted.gapBooking, gap.epoch == offerEpoch else { return }
        let gapEpoch = gap.epoch, booked = gap.units
        // An empty drain proves nothing.
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
                    self.updateState { $0.gapBooking = nil }
                    if let bookedAt = gap.bookedAt { self.deps.insulinHistoryRewritten(bookedAt) }
                    self.handbackDiag(gapEpoch, String(format:
                        "force-reclaim gap RETIRED — the watch returned with %d real dose(s): %.2f U bolus + %d rate record(s) (%.2f U gross programmed, pre-truncation) and %d carb(s); the %.2f U estimate is replaced by actual timing",
                        dosesJustCommitted.count, bolusUnits, rateCount, rateGross, carbsJustCommitted, booked))

                    self.cancelPlaceholderReminders()
                    self.deps.issueNotice("Watch Records Recovered",
                                    String(format: "The watch is back. Its records (%d doses, %d carbs) replaced the estimated %.2f U bolus — your IOB and COB now reflect actual timing.",
                                           dosesJustCommitted.count, carbsJustCommitted, booked))
                } else {
                    self.updateState { $0.gapBooking?.deleteFailedAfterRecords = true }
                    self.handbackDiag(gapEpoch, String(format:
                        "** force-reclaim gap DELETE FAILED — the %.2f U placeholder AND the real records are both booked; IOB is over-counted until this retries **", booked))
                }
            }
        }
    }

    /// The phone loop's dosing gate: the pod is lent out, or a force reclaim's audit has not
    /// ruled. Never blocks: it reads the pump and the locked state.
    var holdsAutomaticDosing: Bool {
        (deps.pumpManager() as? ExclusiveDeviceControl)?.isControlReleased == true
            || persisted.pendingForceAudit != nil
    }

    /// Blocking; never from the controller's queue or a UI draw path.
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

    /// The audit window's start; consumed when the loan is judged.
    struct AuditBase {
        let units: Double
        let asOf: Date
    }

    /// Same band as the final verdict.
    static let checkpointBand: Double = 0.20

    /// The lent pump's delivery pulse; nil with no pump, which no audit can be judged without.
    var pumpPulseUnits: Double? { (deps.pumpManager() as? PumpDeliveryOdometer)?.deliveryPulseUnits }

    /// Reconciles the stretch since the last base using a mid-loan reading; a match advances
    /// the base, a mismatch is carried.
    func considerCheckpoint(_ snap: LoanOdometerSnapshot, context: String) {
        guard let asOf = snap.asOf else { return }
        guard let base = auditBase, let pulseUnits = pumpPulseUnits else { return }
        // A reading no newer than the base closes no window.
        guard asOf > base.asOf else { return }
        // A total that went backwards is not a reading of this pod.
        guard snap.deliveredLatest >= base.units else {
            PhoneLog.event("loan", String(format: "e%d [checkpoint] REJECTED (%@): odometer regressed %.3f → %.3f",
                                          epoch, context, base.units, snap.deliveredLatest))
            return
        }
        // All staged records: what the pod was asked to deliver.
        let events = staged.values
            .filter { !stagedTombstones.contains($0.id) }
            .sorted { $0.seq < $1.seq }
        // A bolus exactly at the boundary belongs to the next window.
        let expected = LoanReconciler.expectedInsulin(events: events, schedule: deps.settings().basalRateSchedule,
                                                      pulseUnits: pulseUnits, from: base.asOf, to: asOf,
                                                      includingBolusesAtEnd: false)
        let delivered = snap.deliveredLatest - base.units

        // Milli-units, so float error cannot decide the band.
        let residual = ((delivered - expected) * 1000).rounded() / 1000
        if abs(residual) <= Self.checkpointBand {
            checkpointsThisLoan += 1
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

    /// A verdict waiting for the reclaim round-trip to read the pod.
    struct PendingHandbackAudit {
        /// Only `.forceReclaim` survives a relaunch and books a placeholder.
        enum Flavor: String { case handback, forceReclaim }
        let epoch: Int
        /// Start of the verdict window, possibly moved by checkpoints.
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
