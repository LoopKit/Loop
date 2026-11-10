//
//  PodLoanPhoneController+Ledger.swift
//  Loop
//
//  The insulin ledger: the pod's total at the last reading, and the estimates standing in the dose
//  store. A reading at a change of custody ends one window and starts the next; the device that held
//  the pod in a window explains it with its records and the schedule; what it cannot explain is
//  booked once, named by the window, and retired by that window's own late records. Automatic
//  dosing continues either way. Also the one function that saves the watch's records in the phone's dose history.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import LoopAlgorithm
import UserNotifications

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

    static func pumpEventTitle(for type: DoseType) -> String {
        switch type {
        case .bolus:     return "Bolus"
        case .tempBasal: return "Temp Basal"
        case .basal:     return "Basal"
        case .suspend:   return "Suspend"
        case .resume:    return "Resume"
        }
    }

    var reclaimProgress: ReclaimProgress? {
        Self.reclaimProgress(from: uiSnapshot(), now: deps.now())
    }

    /// The phone loop's dosing gate: a grant is under way, the pod is lent out, a take-back is
    /// reaching for it, a take-back's audit has not ruled, this phone holds watch records it has not
    /// saved, or it is asking the watch about insulin it cannot explain.
    var holdsAutomaticDosing: Bool {
        let saved = persisted
        return grantInFlight
            || (deps.pumpManager() as? ExclusiveDeviceControl)?.isControlReleased == true
            || saved.phase == .reclaimPending || saved.pendingForceAudit != nil
            || Self.watchLoopsThePod(saved)
            || holdsUnsavedWatchRecords
            || askingAboutUnexplainedInsulin
    }

    /// With the pod back, this phone still holds watch records its dose history does not: a take-back's
    /// save has not landed, or records came after it. Insulin on board is short by them until it does.
    var holdsUnsavedWatchRecords: Bool {
        state == .owner && staged.values.contains { !stagedTombstones.contains($0.id) && !committedIDs.contains($0.id) }
    }

    /// Holding the pod, this phone asks the watch only after a reading shows insulin its records cannot
    /// explain (rows 5, 17 and 18): the watch may be looping the pod. The cycle that reading feeds doses
    /// nothing until the answer; silence lets this phone loop again.
    var askingAboutUnexplainedInsulin: Bool {
        watchAskedAt != nil && controlRole == .holdsPod
    }

    /// The watch loops the pod: lent to it, or this phone standing aside for a loan it never granted.
    /// Holds dosing even if the pod driver kept the pod when asked to let go.
    static func watchLoopsThePod(_ saved: PodLoanPhoneState) -> Bool {
        saved.phase == .grantOffered || saved.phase == .loaned || saved.yieldingToInferredLoan
    }

    var isPodLoanedOut: Bool {
        state != .owner || yieldingToInferredLoan
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
            completion(doses.filter { !Self.isEstimate($0) }.compactMap(LoanDoseRecord.init(storeDose:)))
        }
    }

    /// The watch's first reading of the pod: the window until then was this phone's, whose last
    /// program the pod ran on. Logged, never acted on. The watch's window starts here,
    /// unless this phone read the pod after it: the latest reading starts the window, so the phone's
    /// own doses after the watch's takeover stay the phone's.
    func noteTakeoverReading(units: Double, at: Date) {
        let last = ledgerLast
        if let last, at <= last.at {
            PhoneLog.event("loan", String(format: "the watch's window starts at this phone's later reading, %.2f U at %@",
                                          last.units, ISO8601DateFormatter().string(from: last.at)))
            return
        }
        noteReading(units: units, at: at)
        guard let last, units >= last.units, let pulseUnits = pumpPulseUnits else { return }
        let schedule = deps.settings().basalRateSchedule
        ownRecords(from: last.at) { records in
            let residual = LoanReconciler.insulinNotInRecords(totalThen: last.units, then: last.at, totalNow: units, now: at,
                                                              records: records, schedule: schedule, pulseUnits: pulseUnits)
            PhoneLog.event("loan", String(format: "this phone's insulin check until the watch took over: %.1f min, pod total %.2f to %.2f U, residual %+.3f U",
                                          at.timeIntervalSince(last.at) / 60, last.units, units, residual))
        }
    }

    /// Called from the pump's report, before the report completes, so the cycle the reading feeds
    /// sees the verdict. While this phone holds the pump, each reading closes the open window
    /// against its own records, and on a phone a watch could start without, the verdict acts at
    /// once: a loan started away from the phone can be minutes long. Not while a reclaim's verdict
    /// is owed: that closes the watch's window. `completion` fires once any booking is in the store.
    func checkOwnPumpTotal(completion: @escaping () -> Void = {}) {
        // The window is the watch's, judged when the pod comes back.
        if Self.watchLoopsThePod(self.persisted) {
            self.letGoAgainIfKept()
            return completion()
        }
        guard self.state == .owner, self.pendingHandbackAudit == nil,
              let pump = self.deps.pumpManager() as? PumpDeliveryOdometer,
              (pump as? ExclusiveDeviceControl)?.isControlReleased != true,
              let reading = pump.deliveredUnits else { return completion() }
        guard let last = self.ledgerLast else {
            self.noteReading(units: reading.units, at: reading.at)
            return completion()
        }
        guard reading.at > last.at else { return completion() }
        self.noteReading(units: reading.units, at: reading.at)
        // A lower total is a different pod: start again from it.
        guard reading.units >= last.units else { return completion() }
        let gap = reading.at.timeIntervalSince(last.at)
        let acts = self.persisted.seizeToken != nil
        let schedule = self.deps.settings().basalRateSchedule
        let pulseUnits = pump.deliveryPulseUnits
        self.ownRecords(from: last.at) { records in
            let residual = LoanReconciler.insulinNotInRecords(totalThen: last.units, then: last.at,
                                                              totalNow: reading.units, now: reading.at,
                                                              records: records, schedule: schedule, pulseUnits: pulseUnits)
            PhoneLog.event("loan", String(format: "this phone's insulin check: %.1f min, pod total %.2f to %.2f U, residual %+.3f U",
                                          gap / 60, last.units, reading.units, residual))
            guard acts else { return completion() }
            DispatchQueue.main.async {
                self.applyGapVerdict(residual: residual, window: DateInterval(start: last.at, end: reading.at), completion: completion)
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
        let line = String(format: "e%d loan so far, from the watch's %@: %.1f min, delivered %.3f U, expected %.3f U, running residual %+.3f U%@",
                          epoch, context, asOf.timeIntervalSince(base.at) / 60, delivered, expected,
                          ((delivered - expected) * 1000).rounded() / 1000,
                          delivering ? ", a bolus was being given" : "")
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
        let watchLatest: Double?
        var flavor: Flavor = .handback
    }

    // MARK: - Verdicts

    /// Hand-back verdict: the watch's records are complete, so nothing is booked. Both directions
    /// notify time-sensitive; automatic dosing continues.
    func applyReconciliationVerdict(residual: Double, epoch: Int) {
        if residual > Self.unexplainedInsulinBand {
            handbackDiag(epoch, String(format:
                "insulin warning: residual %+.3f U exceeds +%.2f U; the watch's records are complete, so nothing is booked",
                residual, Self.unexplainedInsulinBand))

            deps.issueUrgentNotice("Unexplained Insulin",
                             String(format: "Unexpected: the pod delivered %.2f U more than the watch recorded. It isn't counted in insulin on board. Consider reporting it with a Loop Report.", residual))
        } else if residual < -Self.warnNegativeResidual {
            handbackDiag(epoch, String(format:
                "insulin warning: residual %+.3f U is beyond -%.2f U; the records claim more than the pod delivered",
                residual, Self.warnNegativeResidual))

            deps.issueUrgentNotice("Insulin On Board May Be Overstated",
                             String(format: "Unexpected: the watch recorded %.2f U more than the pod delivered. Loop may dose cautiously for a few hours. Consider reporting it with a Loop Report.", -residual))
        }
    }

    /// Force-reclaim verdict: the watch's records are missing, so insulin they would have explained
    /// is booked as an estimate. Automatic dosing continues on it.
    func applyForceReclaimVerdict(residual: Double, epoch: Int, window: DateInterval) {
        if residual > Self.unexplainedInsulinBand {
            handbackDiag(epoch, String(format:
                "insulin warning after take-back: residual %+.3f U exceeds +%.2f U; booking it as an estimate",
                residual, Self.unexplainedInsulinBand))

            bookEstimate(units: residual, window: window, epoch: epoch,
                         notice: String(format: "%.2f U booked as a bolus because the watch's records haven't arrived. Its records replace this when the watch is back.", residual))
        } else if residual < -Self.warnNegativeResidual {
            handbackDiag(epoch, String(format:
                "insulin warning after take-back: residual %+.3f U is beyond -%.2f U; the records claim more than the pod delivered",
                residual, Self.warnNegativeResidual))

            deps.issueUrgentNotice(Self.overstatedTitle, Self.overstatedBody(-residual))
        } else {
            handbackDiag(epoch, String(format:
                "insulin after take-back is clean: residual %+.3f U within ±%.2f U", residual, Self.unexplainedInsulinBand))
        }
    }

    /// A window this phone held, judged against its own records: a difference beyond the band either way
    /// is another device having controlled the pod, a loan this phone never heard of (the watch started
    /// without it). Extra insulin is booked before the cycle decides; then `LoanControl` decides what
    /// follows (rows 4, 5 and 18). Silent when clean.
    func applyGapVerdict(residual: Double, window: DateInterval, completion: @escaping () -> Void = {}) {
        let gapMinutes = window.duration / 60
        decideAndAct(.podReading(differenceBeyondBand: abs(residual) > Self.unexplainedInsulinBand),
                     why: String(format: "the pod shows %+.2f U this phone's records cannot explain", residual))
        if residual > Self.unexplainedInsulinBand {
            handbackDiag(epoch, String(format:
                "insulin warning: %+.3f U over the last %.0f min that this phone's records cannot explain; booking it as an estimate",
                residual, gapMinutes))
            bookEstimate(units: residual, window: window, epoch: epoch,
                         notice: String(format: "%.2f U booked as a bolus: insulin the iPhone didn't record, probably from Sport Mode started on the watch. The watch's records replace it when it's back.", residual),
                         completion: completion)
        } else if residual < -Self.warnNegativeResidual {
            handbackDiag(epoch, String(format:
                "insulin warning: this phone's records claim %.3f U more than the pod delivered over the last %.0f min", -residual, gapMinutes))
            deps.issueUrgentNotice(Self.overstatedTitle, Self.overstatedBody(-residual))
            completion()
        } else {
            completion()
        }
    }

    static let estimatedTitle = "Insulin Estimated After Sport Mode"
    static let overstatedTitle = "Insulin On Board May Be Overstated"

    static func overstatedBody(_ units: Double) -> String {
        String(format: "Insulin on board may be %.2f U high until the watch's records arrive. Loop will dose cautiously meanwhile.", units)
    }

    // MARK: - Estimates

    /// Past insulin's action time an estimate no longer counts in insulin on board, so it leaves the
    /// ledger; its dose stays in the books.
    static func isAged(_ booking: PodLoanPhoneState.Ledger.Booking, now: Date) -> Bool {
        now.timeIntervalSince(booking.bookedAt) >= InsulinMath.defaultInsulinActivityDuration
    }

    /// Books an estimate as a manual dose now, so it keeps its identifier and does not decay early.
    /// `completion` fires once the store has answered, either way.
    func bookEstimate(units: Double, window: DateInterval, epoch: Int, notice: String, completion: @escaping () -> Void = {}) {
        let now = deps.now()
        let sync = "\(Self.estimateSyncPrefix)-e\(epoch)-\(Int(now.timeIntervalSince1970))"
        let entry = DoseEntry(type: .bolus, startDate: now, endDate: now,
                              value: units, unit: .units, decisionId: nil, deliveredUnits: units,
                              syncIdentifier: sync, manuallyEntered: true)
        deps.issueUrgentNotice(Self.estimatedTitle, notice)
        deps.bookGapDose(entry) { [weak self] ok in
            guard let self = self else { return completion() }
            DispatchQueue.main.async {
                defer { completion() }
                guard ok else {
                    self.handbackDiag(epoch, String(format: "estimate not saved: %.2f U is not in the books", units))
                    return
                }
                self.updateState {
                    $0.ledger.bookings.removeAll { Self.isAged($0, now: now) }
                    $0.ledger.bookings.append(.init(sync: sync, units: units, bookedAt: now, window: window))
                }
                self.armPlaceholderReminders(units: units, bookedAt: now)
                let iso = ISO8601DateFormatter()
                self.handbackDiag(epoch, String(format: "estimate booked: %.2f U as a bolus for %@ to %@, sync %@",
                                                units, iso.string(from: window.start), iso.string(from: window.end), sync))
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
            handbackDiag(epoch, "estimate stands: these records do not cover its window")
            return
        }
        let boluses = doses.filter { $0.type == .bolus }
        let bolusUnits = boluses.reduce(0.0) { $0 + ($1.deliveredUnits ?? $1.programmedUnits) }
        let rateCount = doses.count - boluses.count
        for booking in covered {
            deps.deleteGapDose(booking.sync) { [weak self] ok in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if ok {
                        self.updateState { $0.ledger.bookings.removeAll { $0.sync == booking.sync } }
                        self.deps.insulinHistoryRewritten(booking.bookedAt)
                        self.handbackDiag(epoch, String(format:
                            "estimate retired: %.2f U replaced by the watch's records, %d doses with %.2f U of bolus, %d rate records, %d carbs",
                            booking.units, doses.count, bolusUnits, rateCount, carbs))

                        self.rearmPlaceholderReminders()
                        self.deps.issueNotice("Watch Records Recovered", carbs > 0
                            ? String(format: "The watch's records replaced the estimated %.2f U. Loop now doses with the watch's insulin and carbs.", booking.units)
                            : String(format: "The watch's records replaced the estimated %.2f U. Insulin on board is exact again.", booking.units))
                    } else {
                        self.updateState {
                            for i in $0.ledger.bookings.indices where $0.ledger.bookings[i].sync == booking.sync {
                                $0.ledger.bookings[i].deleteFailed = true
                            }
                        }
                        self.handbackDiag(epoch, String(format:
                            "estimate not deleted: the %.2f U estimate and the watch's records are both booked until a retry", booking.units))
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
                handbackDiag(epoch, String(format: "estimate stands at launch: %.2f U, sync %@", booking.units, booking.sync))
                continue
            }
            deps.deleteGapDose(booking.sync) { [weak self] ok in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if ok {
                        self.updateState { $0.ledger.bookings.removeAll { $0.sync == booking.sync } }
                        self.deps.insulinHistoryRewritten(booking.bookedAt)
                        self.rearmPlaceholderReminders()
                        self.handbackDiag(self.epoch, String(format: "estimate retired at launch: %.2f U, sync %@", booking.units, booking.sync))
                    } else {
                        self.handbackDiag(self.epoch, String(format: "estimate not deleted at launch: %.2f U, sync %@, still stands", booking.units, booking.sync))
                    }
                }
            }
        }
    }
}

extension DoseStore {
    /// The one way the watch's records enter this phone's dose history. They are saved as a pump
    /// driver's finished events are, so stock derives the dose cache, Apple Health and the uploads from
    /// them.
    ///
    /// Sport Mode's one difference from a pump driver: the watch's records can arrive after this phone
    /// has already reported past them (a take-back, or a loan started without the phone). Stock does
    /// not derive doses older than what it has already filled, so the dose cache, which insulin on
    /// board is computed from, is then made to agree with the pump events over the stretch the batch
    /// covers: a temp basal ends where the next rate record starts, and every finished bolus and temp
    /// basal is there. Returns the doses written that way; none when the records arrive in order.
    func saveLoanRecords(_ events: [NewPumpEvent], completeUpTo: Date, phoneHasReleasedThePod: Bool) async throws -> [DoseEntry] {
        // "History is complete up to here" never moves back: an older loan's records, and records that
        // arrive after a take-back, carry an earlier time than this phone has already reported.
        let reconciliation = Swift.max(completeUpTo, lastPumpEventsReconciliation ?? .distantPast)
        var events = events
        if phoneHasReleasedThePod {
            events += try await finishOwnPendingDoses(reportedIn: events, upTo: reconciliation)
        }
        try await addPumpEvents(events, lastReconciliation: reconciliation, replacePendingEvents: false)

        let batch = events.compactMap(\.dose)
        guard let earliest = batch.map(\.startDate).min(), let latest = batch.map(\.endDate).max() else { return [] }

        // What the pump events say was delivered: each temp basal runs until the next rate record
        // starts, as stock reads them. A zero-length record sorts first among equal starts: it ends
        // what ran before it, not what starts with it.
        let recorded = try await getPumpEventValues(since: earliest.addingTimeInterval(-.hours(24))).compactMap(\.dose)
        let rates = recorded
            .filter { $0.type == .tempBasal || $0.type == .basal || $0.type == .suspend }
            .sorted { ($0.startDate, $0.endDate) < ($1.startDate, $1.endDate) }
        var finished = recorded.filter { $0.type == .bolus && !$0.isMutable }
        for (index, dose) in rates.enumerated() where dose.type == .tempBasal && !dose.isMutable {
            let end = index + 1 < rates.count ? Swift.min(dose.endDate, rates[index + 1].startDate) : dose.endDate
            if let cut = dose.trimmed(to: end, syncIdentifier: dose.syncIdentifier), cut.endDate > cut.startDate {
                finished.append(cut)
            }
        }

        let cached = try await insulinDeliveryStore.getDoseEntries(start: earliest.addingTimeInterval(-.hours(24)),
                                                                   end: latest.addingTimeInterval(1))
        let amended = finished.filter { dose in
            guard dose.startDate <= latest, dose.endDate >= earliest, let identifier = dose.syncIdentifier else { return false }
            // By prefix: a stored dose cut in pieces keeps its identifier as the start of each piece's.
            let rows = cached.filter { $0.syncIdentifier?.hasPrefix(identifier) ?? false }
            guard let row = rows.first else { return true }
            guard dose.type == .tempBasal, rows.count == 1, row.syncIdentifier == identifier else { return false }
            return abs(row.endDate.timeIntervalSince(dose.endDate)) > 1
        }
        if !amended.isEmpty {
            try await syncDoseEntries(amended)
        }
        return amended
    }

    /// A loan started without this phone leaves the phone's own temp basal or bolus pending in its
    /// history: its pump driver released the pod while they ran and never reports them finished, and
    /// stock deletes pending records at the driver's next report. While the driver has released the
    /// pod nothing else finishes them, so they are finished here: one the watch reports is removed, so
    /// the watch's finished record is stored in its place; any other that has ended is stored final, a
    /// temp basal ending where the next rate record starts and a bolus in full. Returns the final
    /// copies to store; one still running is left for the next save.
    private func finishOwnPendingDoses(reportedIn events: [NewPumpEvent], upTo reconciliation: Date) async throws -> [NewPumpEvent] {
        let stored = try await getPumpEventValues(since: reconciliation.addingTimeInterval(-.hours(24)))
        let reported = Set(events.map(\.raw))
        let rateStarts = (stored.compactMap(\.dose) + events.compactMap(\.dose))
            .filter { $0.type == .tempBasal || $0.type == .basal || $0.type == .suspend }
            .map(\.startDate)
        var finals: [NewPumpEvent] = []
        for event in stored {
            guard let dose = event.dose, dose.isMutable, dose.type == .bolus || dose.type == .tempBasal,
                  let raw = event.raw else { continue }
            var final: DoseEntry?
            if !reported.contains(raw) {
                var end = dose.endDate
                if dose.type == .tempBasal, let next = rateStarts.filter({ $0 > dose.startDate }).min() {
                    end = Swift.min(end, next)
                }
                guard end <= reconciliation else { continue }
                final = dose.type == .tempBasal ? dose.trimmed(to: end, syncIdentifier: dose.syncIdentifier) : dose
                final?.isMutable = false
            }
            let failure: DoseStoreError? = await withCheckedContinuation { continuation in
                deletePumpEvent(event) { continuation.resume(returning: $0) }
            }
            if let failure { throw failure }
            if let final {
                finals.append(NewPumpEvent(date: final.startDate, dose: final, raw: raw, title: event.title ?? ""))
            }
        }
        return finals
    }
}
