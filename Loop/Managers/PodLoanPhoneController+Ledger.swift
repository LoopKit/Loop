//
//  PodLoanPhoneController+Ledger.swift
//  Loop
//
//  The insulin ledger: the pod's total at the last reading, and the estimates standing in the dose
//  store. A reading at a change of custody ends one window and starts the next; the device that held
//  the pod in a window explains it with its records and the schedule; what it cannot explain is
//  booked once, named by the window, and retired by that window's own late records. Automatic
//  dosing continues either way. Also the helpers that turn the watch's records into the phone's writes.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import LoopAlgorithm
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

    /// The phone loop's dosing gate: the pod is lent out, a take-back is reaching for it, or a
    /// take-back's audit has not ruled. Never blocks: it reads the pump and the locked state.
    var holdsAutomaticDosing: Bool {
        let saved = persisted
        return (deps.pumpManager() as? ExclusiveDeviceControl)?.isControlReleased == true
            || saved.phase == .reclaimPending || saved.pendingForceAudit != nil
    }

    /// Blocking; never from the controller's queue or a UI draw path.
    var isPodLoanedOut: Bool {
        return queue.sync { state != .owner || yieldingToInferredLoan }
    }

    /// The lent pump's delivery pulse; nil with no pump, which no audit can be judged without.
    var pumpPulseUnits: Double? { (deps.pumpManager() as? PumpDeliveryOdometer)?.deliveryPulseUnits }

    // MARK: - Readings and windows

    /// The pod delivered this much more than the records explain: reported, and booked when the
    /// records are missing.
    static let unexplainedInsulinBand: Double = 0.20

    /// Records claim this much more than the pod delivered: reported. Phantom IOB is self-limiting.
    static let warnNegativeResidual: Double = 0.20

    /// Every estimate's sync identifier starts with this: the delete finds it by that alone, and no
    /// window's records include one.
    static let estimateSyncPrefix = "LOAN-AUDIT-GAP"

    /// The open window's start.
    var ledgerLast: PodLoanPhoneState.Ledger.Reading? { persisted.ledger.last }

    /// A reading at a change of custody: the window from the last reading closes here, and the next opens.
    func noteReading(units: Double, at: Date) {
        updateState { $0.ledger.last = .init(units: units, at: at) }
    }

    static func isEstimate(_ dose: DoseEntry) -> Bool {
        dose.syncIdentifier?.hasPrefix(estimateSyncPrefix) ?? false
    }

    /// This phone's records over a window, as loan records. A dose that began before the window can
    /// still run into it; an estimate stands for insulin given before it was booked, so none is in any window.
    func ownRecords(from start: Date, completion: @escaping ([LoanDoseRecord]) -> Void) {
        deps.doseHistory(start.addingTimeInterval(-.hours(1))) { doses in
            completion(doses.filter { !Self.isEstimate($0) }.compactMap(Self.loanRecord(from:)))
        }
    }

    /// The watch's first reading of the pod: the window until then was this phone's, whose last
    /// program the pod ran on. Logged, never acted on (grid 9.5). The watch's window starts here,
    /// unless this phone read the pod after it: the latest reading starts the window, so the phone's
    /// own doses after the watch's takeover stay the phone's.
    func noteTakeoverReading(units: Double, at: Date) {
        let last = ledgerLast
        if let last, at <= last.at {
            PhoneLog.event("loan", String(format: "window start kept — this phone read the pod after the watch took over: %.2f U at %@",
                                          last.units, ISO8601DateFormatter().string(from: last.at)))
            return
        }
        noteReading(units: units, at: at)
        guard let last, units >= last.units, let pulseUnits = pumpPulseUnits else { return }
        let schedule = deps.settings().basalRateSchedule
        ownRecords(from: last.at) { records in
            let residual = LoanReconciler.insulinNotInRecords(totalThen: last.units, then: last.at, totalNow: units, now: at,
                                                              records: records, schedule: schedule, pulseUnits: pulseUnits)
            PhoneLog.event("loan", String(format: "[odometer] (own) %.1f min until the watch took over: pump total %.2f → %.2f, residual %+.3f",
                                          at.timeIntervalSince(last.at) / 60, last.units, units, residual))
        }
    }

    /// A gap this long without reading the pump, on a phone a watch could start without, means the
    /// watch may have had the pod: the check then acts (see `applyGapVerdict`).
    static let ownPumpGapForCheck: TimeInterval = .minutes(10)

    /// Called every phone cycle. While this phone holds the pump, each reading closes the open window
    /// against its own records. Logged each cycle; acted on after a gap, on a phone set up for Sport
    /// Mode started away from it. Not while a reclaim's verdict is owed: that closes the watch's window.
    func checkOwnPumpTotal() {
        queue.async {
            guard self.state == .owner, self.pendingHandbackAudit == nil,
                  let pump = self.deps.pumpManager() as? PumpDeliveryOdometer,
                  (pump as? ExclusiveDeviceControl)?.isControlReleased != true,
                  let reading = pump.deliveredUnits else { return }
            guard let last = self.ledgerLast else {
                self.noteReading(units: reading.units, at: reading.at)
                return
            }
            guard reading.at > last.at else { return }
            self.noteReading(units: reading.units, at: reading.at)
            // A lower total is a different pod: start again from it.
            guard reading.units >= last.units else { return }
            let gap = reading.at.timeIntervalSince(last.at)
            let acts = gap >= Self.ownPumpGapForCheck && self.persisted.seizeToken != nil
            let schedule = self.deps.settings().basalRateSchedule
            let pulseUnits = pump.deliveryPulseUnits
            self.ownRecords(from: last.at) { records in
                let residual = LoanReconciler.insulinNotInRecords(totalThen: last.units, then: last.at,
                                                                  totalNow: reading.units, now: reading.at,
                                                                  records: records, schedule: schedule, pulseUnits: pulseUnits)
                PhoneLog.event("loan", String(format: "[odometer] (own) %.1f min: pump total %.2f → %.2f, residual %+.3f",
                                              gap / 60, last.units, reading.units, residual))
                if acts {
                    self.queue.async { self.applyGapVerdict(residual: residual, window: DateInterval(start: last.at, end: reading.at)) }
                }
            }
        }
    }

    /// Logs the loan's running residual at a mid-loan reading. Diagnostic only: the verdict is
    /// judged once, over the whole window, at the hand-back or force reclaim.
    func logRunningAudit(_ snap: LoanOdometerSnapshot, context: String) {
        guard let asOf = snap.asOf, let base = ledgerLast, asOf > base.at,
              let pulseUnits = pumpPulseUnits else { return }
        let events = staged.values
            .filter { !stagedTombstones.contains($0.id) }
            .sorted { $0.seq < $1.seq }
        // The records count a bolus whole at its start, so a read mid-bolus runs negative.
        let delivering = events.contains {
            $0.record.kind == .bolus && $0.record.startDate <= asOf && asOf < ($0.record.endDate ?? $0.record.startDate)
        }
        let expected = LoanReconciler.expectedInsulin(events: events, schedule: deps.settings().basalRateSchedule,
                                                      pulseUnits: pulseUnits, from: base.at, to: asOf,
                                                      includingBolusesAtEnd: false)
        let delivered = snap.deliveredLatest - base.units
        let line = String(format: "e%d [odometer] (%@) loan so far %.1f min: delivered %.3f expected %.3f residual %+.3f%@",
                          epoch, context, asOf.timeIntervalSince(base.at) / 60, delivered, expected,
                          ((delivered - expected) * 1000).rounded() / 1000,
                          delivering ? " · a bolus was delivering" : "")
        guard line != lastRunningAuditLine else { return }
        lastRunningAuditLine = line
        PhoneLog.event("loan", line)
    }

    /// A verdict waiting for the reclaim round-trip to read the pod.
    struct PendingHandbackAudit {
        /// Only `.forceReclaim` survives a relaunch and books an estimate.
        enum Flavor: String { case handback, forceReclaim }
        let epoch: Int
        /// The window's start: the pod's total at the watch's takeover, and when.
        let deliveredAtStart: Double
        let windowStart: Date
        let expected: Double
        let loanMinutes: Double
        let cycles: Int
        let watchLatest: Double?
        let watchFreshened: Bool
        var flavor: Flavor = .handback
    }

    // MARK: - Verdicts

    /// Hand-back verdict: the watch's records are complete, so nothing is booked. Both directions
    /// notify time-sensitive; automatic dosing continues.
    func applyReconciliationVerdict(residual: Double, epoch: Int) {
        if residual > Self.unexplainedInsulinBand {
            handbackDiag(epoch, String(format:
                "** WARN — residual %+.3f U exceeds +%.2f: the pod delivered insulin the watch's complete records do not contain. Nothing booked; still looping. **",
                residual, Self.unexplainedInsulinBand))

            deps.issueUrgentNotice("Unexplained Insulin",
                             String(format: "The pod delivered %.2f U more than the watch session's records account for. It is not counted in insulin on board. Automatic dosing continues.", residual))
        } else if residual < -Self.warnNegativeResidual {
            handbackDiag(epoch, String(format:
                "** WARN — residual %+.3f U beyond -%.2f: records claim more delivery than the pod made (phantom IOB). Still looping — this direction under-doses and decays out. **",
                residual, Self.warnNegativeResidual))

            deps.issueUrgentNotice("Insulin On Board May Be Overstated",
                             String(format: "The watch session's records account for %.2f U more than the pod delivered. Automatic dosing continues; expect it to run cautious until this clears.", -residual))
        }
    }

    /// Force-reclaim verdict: the watch's records are missing, so insulin they would have explained
    /// is booked as an estimate. Automatic dosing continues on it.
    func applyForceReclaimVerdict(residual: Double, epoch: Int, window: DateInterval) {
        if residual > Self.unexplainedInsulinBand {
            handbackDiag(epoch, String(format:
                "** WARN — force-reclaim residual %+.3f U exceeds +%.2f: the pod delivered insulin the records cannot explain (watch died mid-session?). Still looping. **",
                residual, Self.unexplainedInsulinBand))

            bookEstimate(units: residual, window: window, epoch: epoch,
                         notice: String(format: "The watch's records haven't arrived: %@", Self.bookedSentences(residual)))
        } else if residual < -Self.warnNegativeResidual {
            handbackDiag(epoch, String(format:
                "** WARN — force-reclaim residual %+.3f U beyond -%.2f: records claim more than the pod delivered (phantom IOB). Looping resumes — this direction under-doses and decays out. **",
                residual, Self.warnNegativeResidual))

            deps.issueUrgentNotice(Self.overstatedTitle, Self.overstatedBody(-residual))
        } else {
            handbackDiag(epoch, String(format:
                "force-reclaim audit CLEAN — residual %+.3f U within ±%.2f; automatic dosing resumes", residual, Self.unexplainedInsulinBand))
        }
    }

    /// Back with the pod after a gap, as owner: the forced take-back's verdict for a loan this phone
    /// never heard of (the watch started without it). Looping continues either way.
    func applyGapVerdict(residual: Double, window: DateInterval) {
        let gapMinutes = window.duration / 60
        if residual > Self.unexplainedInsulinBand {
            handbackDiag(epoch, String(format:
                "** WARN — back with the pod after %.0f min: %+.3f U the phone's records cannot explain (Sport Mode started away from the phone?). Still looping. **",
                gapMinutes, residual))
            bookEstimate(units: residual, window: window, epoch: epoch,
                         notice: String(format: "Sport Mode probably started away from the phone: %@", Self.bookedSentences(residual)))
        } else if residual < -Self.warnNegativeResidual {
            handbackDiag(epoch, String(format:
                "** WARN — back with the pod after %.0f min: records claim %.3f U more than the pod delivered. Still looping. **", gapMinutes, -residual))
            deps.issueUrgentNotice(Self.overstatedTitle, Self.overstatedBody(-residual))
        } else {
            handbackDiag(epoch, String(format: "back with the pod after %.0f min: CLEAN — residual %+.3f U within ±%.2f", gapMinutes, residual, Self.unexplainedInsulinBand))
        }
    }

    static let estimatedTitle = "Insulin Estimated After Sport Mode"
    static let overstatedTitle = "Insulin On Board May Be Overstated"

    static func bookedSentences(_ units: Double) -> String {
        String(format: "%.2f U booked as a bolus. When the watch is back, its records update and IOB is exact.", units)
    }

    static func overstatedBody(_ units: Double) -> String {
        String(format: "The watch's records haven't arrived: insulin on board may be %.2f U high. Dosing runs cautious until the watch is back.", units)
    }

    // MARK: - Estimates

    /// Past insulin's action time an estimate no longer counts in insulin on board, so it leaves the
    /// ledger; its dose stays in the books.
    static func isAged(_ booking: PodLoanPhoneState.Ledger.Booking, now: Date) -> Bool {
        now.timeIntervalSince(booking.bookedAt) >= InsulinMath.defaultInsulinActivityDuration
    }

    /// Books an estimate as a manual dose now, so it keeps its identifier and does not decay early.
    func bookEstimate(units: Double, window: DateInterval, epoch: Int, notice: String) {
        let now = deps.now()
        let sync = "\(Self.estimateSyncPrefix)-e\(epoch)-\(Int(now.timeIntervalSince1970))"
        let entry = DoseEntry(type: .bolus, startDate: now, endDate: now,
                              value: units, unit: .units, decisionId: nil, deliveredUnits: units,
                              syncIdentifier: sync, manuallyEntered: true)
        deps.issueUrgentNotice(Self.estimatedTitle, notice)
        deps.bookGapDose(entry) { [weak self] ok in
            guard let self = self else { return }
            self.queue.async {
                guard ok else {
                    self.handbackDiag(epoch, String(format: "** estimate booking FAILED to save — %.2f U is NOT in the books. **", units))
                    return
                }
                self.updateState {
                    $0.ledger.bookings.removeAll { Self.isAged($0, now: now) }
                    $0.ledger.bookings.append(.init(sync: sync, units: units, bookedAt: now, window: window))
                }
                self.armPlaceholderReminders(units: units, bookedAt: now)
                let iso = ISO8601DateFormatter()
                self.handbackDiag(epoch, String(format: "estimate BOOKED — %.2f U bolus now (sync %@) for the window %@ to %@; retired by that window's records",
                                                units, sync, iso.string(from: window.start), iso.string(from: window.end)))
            }
        }
    }

    /// Late records retire every estimate whose window they cover, after the records are written.
    func retireEstimates(coveredBy doses: [DoseEntry], carbs: Int, epoch: Int) {
        let bookings = persisted.ledger.bookings
        // An empty drain proves nothing.
        guard !bookings.isEmpty, !doses.isEmpty else { return }
        let covered = bookings.filter { booking in
            doses.contains { $0.endDate > booking.window.start && $0.startDate < booking.window.end }
        }
        guard !covered.isEmpty else {
            handbackDiag(epoch, "gap estimate STANDS — these records do not cover the gap it was booked for")
            return
        }
        let boluses = doses.filter { $0.type == .bolus }
        let bolusUnits = boluses.reduce(0.0) { $0 + ($1.deliveredUnits ?? $1.programmedUnits) }
        let rateCount = doses.count - boluses.count
        for booking in covered {
            deps.deleteGapDose(booking.sync) { [weak self] ok in
                guard let self = self else { return }
                self.queue.async {
                    if ok {
                        self.updateState { $0.ledger.bookings.removeAll { $0.sync == booking.sync } }
                        self.deps.insulinHistoryRewritten(booking.bookedAt)
                        self.handbackDiag(epoch, String(format:
                            "estimate RETIRED — %d real dose(s) cover its window: %.2f U bolus + %d rate record(s) and %d carb(s); the %.2f U estimate is replaced by actual timing",
                            doses.count, bolusUnits, rateCount, carbs, booking.units))

                        self.rearmPlaceholderReminders()
                        self.deps.issueNotice("Watch Records Recovered",
                                        String(format: "The watch is back. Its records (%d doses, %d carbs) replaced the estimated %.2f U bolus — your IOB and COB now reflect actual timing.",
                                               doses.count, carbs, booking.units))
                    } else {
                        self.updateState {
                            for i in $0.ledger.bookings.indices where $0.ledger.bookings[i].sync == booking.sync {
                                $0.ledger.bookings[i].deleteFailed = true
                            }
                        }
                        self.handbackDiag(epoch, String(format:
                            "** gap DELETE FAILED — the %.2f U estimate AND the real records are both booked; IOB is over-counted until this retries **", booking.units))
                    }
                }
            }
        }
    }

    /// The reminders name the newest estimate standing; none when none stands.
    func rearmPlaceholderReminders() {
        if let newest = persisted.ledger.bookings.max(by: { $0.bookedAt < $1.bookedAt }) {
            armPlaceholderReminders(units: newest.units, bookedAt: newest.bookedAt)
        } else {
            cancelPlaceholderReminders()
        }
    }

    /// At launch: a delete that failed after the records landed is retried; an aged estimate leaves
    /// the ledger; the rest stand.
    func settleEstimatesAtLaunch() {
        let now = deps.now()
        if persisted.ledger.bookings.contains(where: { Self.isAged($0, now: now) }) {
            updateState { $0.ledger.bookings.removeAll { Self.isAged($0, now: now) } }
        }
        for booking in persisted.ledger.bookings {
            guard booking.deleteFailed else {
                handbackDiag(epoch, String(format: "estimate STANDS — %.2f U (sync %@) still unexplained; the records that would retire it have not arrived", booking.units, booking.sync))
                continue
            }
            handbackDiag(epoch, String(format: "estimate DELETE retrying at launch — %.2f U (sync %@) was unretired last session", booking.units, booking.sync))
            deps.deleteGapDose(booking.sync) { [weak self] ok in
                guard let self = self else { return }
                self.queue.async {
                    if ok {
                        self.updateState { $0.ledger.bookings.removeAll { $0.sync == booking.sync } }
                        self.deps.insulinHistoryRewritten(booking.bookedAt)
                        self.rearmPlaceholderReminders()
                        self.handbackDiag(self.epoch, String(format: "estimate RETIRED on launch retry — %.2f U cleared", booking.units))
                    } else {
                        self.handbackDiag(self.epoch, String(format: "** estimate DELETE FAILED AGAIN at launch — %.2f U still stands; will retry next launch or the next matching offer **", booking.units))
                    }
                }
            }
        }
    }
}
