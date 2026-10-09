//
//  PodLoanPhoneController+Records.swift
//  Loop
//
//  Taking in what the watch dosed: streamed batches are staged, hand-back offers commit.
//  The store is written before the ack; one commit at a time (others coalesce); dedup is
//  by event ID; nothing is dropped without saying so.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    /// Staged, not committed: the watch may still supersede an open temp.
    func handleBatch(_ batch: DoseRecordBatch) {
        // Records sent during a revoke count too.
        guard batch.epoch == epoch, state == .loaned || state == .reclaimPending else {
            handbackDiag(batch.epoch, "batch DROPPED — \(batch.events.count) event(s) ev=\(batch.epoch) vs phone ev=\(epoch), state=\(state.rawValue) (recovered via the offer path if the watch still resends)")

            if batch.epoch > epoch, newestForeignLoanEvidence.map({ batch.epoch >= $0.epoch }) ?? true {
                newestForeignLoanEvidence = (batch.epoch, deps.now())
            }

            // A future epoch means the watch is running a loan this phone never granted.
            if state == .owner, batch.epoch > epoch,
               persisted.seizeToken != nil {
                engageInferredLoanYield(evidence: "future-epoch batch e\(batch.epoch) at .owner (live seized loan streaming)")
            }

            // Records for a closed loan: resend the revoke, throttled.
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

        if let snap = batch.odometer {
            logRunningAudit(snap, context: "batch")
        }
    }

    /// The phone's half of the periodic pod-link census, logged regardless of traffic.
    func installPodLinkCensus() {
        WatchDataManager.podLinkCensus = { [weak self] in
            guard let self, let control = self.deps.pumpManager() as? ExclusiveDeviceControl else {
                return "no pump manager"
            }
            return "released=\(control.isControlReleased) \(control.connectionDiagnostics() ?? "no diagnostics")"
        }
    }

    /// Loan log, in the phone's own file as well as to the watch (whose copy can be stuck in a queue).
    func handbackDiag(_ epoch: Int, _ text: String) {
        os_log("HANDBACK-DIAG e%d: %{public}@", log: log, type: .default, epoch, text)

        PhoneLog.event("loan", "e\(epoch) \(text)")
        sendMessage(.diag(LoanDiag(epoch: epoch, text: text)))
    }

    /// Interim drain, final hand-back, or stale offer, told apart by `released` and epoch.
    /// Nothing before the write may change state the phone cannot undo if the write fails.
    func handleHandbackOffer(_ offer: HandbackOffer) {
        // Retro-acknowledge a loan the watch started alone: needs the token and a higher epoch,
        // and never over a grant in flight or a live loan.
        if let token = offer.seizeToken, state == .owner || state == .reclaimPending, offer.epoch > epoch,
           token == persisted.seizeToken {
            if state == .reclaimPending {
                cancelReclaimLadder()
                handbackDiag(offer.epoch, "[seize] retro-ack arrived MID-RECLAIM — ladder stood down; the aimed revoke got its drain")
            }
            handbackDiag(offer.epoch, "[seize] RETRO-ACK — offer for a SEIZED loan (token …\(String(token.uuidString.suffix(8)))); adopting epoch \(epoch)→\(offer.epoch) as .loaned, reconciling on the normal path")

            clearInferredLoanYield(reason: "retro-ack — the inferred loan is now the adopted loan e\(offer.epoch)")
            // Anchor the adopted loan at its earliest record, at most six hours back.
            let anchor = max(offer.events.map(\.record.startDate).min() ?? offer.handedBackAt,
                             deps.now().addingTimeInterval(-.hours(6)))
            let previous = state
            updateState {
                $0.epoch = offer.epoch
                $0.phase = .loaned
                $0.holdRenewedAt = offer.handedBackAt
                $0.holdLapseNoticedAt = nil
                $0.watchSilenceWarningsIssued = 0
                $0.audit.base = nil
                $0.audit.deliveredAtTakeover = nil
                $0.audit.loanStartedAt = anchor
            }
            stateDidChange(from: previous)
        }

        // An offer ahead of this phone's epoch cannot be committed.
        let isStale = offer.epoch < epoch
        guard offer.epoch == epoch || isStale else {
            os_log("Hand-back offer DROPPED: offer.epoch %d > phone.epoch %d — watch ahead of phone; loan may be stranded (needs reclaim or new request)",
                   log: log, type: .error, offer.epoch, epoch)
            handbackDiag(offer.epoch, "offer DROPPED epoch \(offer.epoch) > phone \(epoch) — phone behind, loan stranded")
            return
        }
        handbackDiag(offer.epoch, "offer RX ev=\(offer.events.count) released=\(offer.released.map { $0 ? "final" : "interim" } ?? "nil") stale=\(isStale) state=\(state.rawValue)")

        // One commit at a time; coalesce by epoch, and never let an interim replace a waiting final.
        if commitInFlight {
            let storedIsFinal = coalescedOffers[offer.epoch]?.released == true
            if !(storedIsFinal && offer.released != true) {
                coalescedOffers[offer.epoch] = offer
            }
            handbackDiag(offer.epoch, "offer COALESCED behind the in-flight write — \(coalescedOffers.count) waiting")
            return
        }

        // Missing `released` is from a build without interim drains: final.
        let isFinal = offer.released ?? true
        // An interim drain is also the watch checking in, so it renews the silence watchdog.
        if !isStale, !isFinal { noteHoldRenewal(sentAt: offer.handedBackAt) }
        // A fast loan can hand back before its takeover confirmation arrives.
        let canTransition = state == .loaned || state == .reclaimPending || state == .grantOffered
        // Refuse a hand-back while this phone's Bluetooth is off; it could not reach the pod.
        if !isStale, canTransition, deps.isBluetoothPoweredOff() {
            handbackDiag(offer.epoch, "hand-back REFUSED — this phone's Bluetooth is off, so it could not reclaim the pod; the watch keeps the loan")
            sendMessage(.denied(LoanDenied(reason: NSLocalizedString("iPhone Bluetooth is off — still running", comment: "Hand-back refused: shown on the watch glance"))))
            return
        }
        // .reconciling: the phone owes an ack; the loan ends when the write lands.
        if !isStale, isFinal, canTransition {
            state = .reconciling

            handbackDiag(offer.epoch, "commit done — ACKing now; the watch cannot release the pod until this lands")
            // Loop mode and recency come home with the pod.
            if let watchClosed = offer.watchClosedLoopEnabled {
                deps.noteWatchClosedLoop(watchClosed)
                handbackDiag(offer.epoch, "loop mode INHERITED from the wrist — phone will resume \(watchClosed ? "CLOSED" : "OPEN")")
            }

            if let watchLoop = offer.lastLoopCompleted {
                deps.noteWatchLoopCompleted(watchLoop)
                handbackDiag(offer.epoch, String(format: "loop recency INHERITED from the wrist — last cycle %.0fs ago", deps.now().timeIntervalSince(watchLoop)))
            }
        }

        // Only a live final offer that moved us to reconciling leaves a verdict owed.
        let auditThisOffer = !isStale && isFinal && state == .reconciling

        stage(events: offer.events, tombstones: offer.tombstones)

        if !isStale, offer.epoch == epoch, offer.released == false, let snap = offer.odometer {
            logRunningAudit(snap, context: "interim-offer")
        }

        // A stale offer speaks only for its own events.
        let ownEventIDs = isStale ? Set(offer.events.map(\.id)) : nil
        // Staged minus retracted minus already committed.
        let events = staged.values
            .filter { !stagedTombstones.contains($0.id) && !committedIDs.contains($0.id) }
            .filter { ownEventIDs?.contains($0.id) ?? true }
            .sorted { $0.seq < $1.seq }

        // The whole loan, for the expectation and the backfill.
        let allStagedEvents = staged.values
            .filter { !stagedTombstones.contains($0.id) }
            .sorted { $0.seq < $1.seq }

        // Fallback start when the anchors were lost.
        let loanStart = loanStartedAt ?? offer.handedBackAt.addingTimeInterval(-.hours(2))
        let input = LoanReconciler.Input(
            events: events,
            schedule: deps.settings().basalRateSchedule,
            loanStart: loanStart,
            loanEnd: offer.handedBackAt,

            isFinalHandback: isFinal)
        let outcome = LoanReconciler.reconcile(input)

        if auditThisOffer, let pulseUnits = pumpPulseUnits {
            let expected = LoanReconciler.expectedInsulin(events: allStagedEvents, schedule: deps.settings().basalRateSchedule,
                                                          pulseUnits: pulseUnits, from: loanStart, to: offer.handedBackAt)

            // The watch's own reading: logged, not ruled on.
            let delivered = offer.odometer.map { $0.deliveredLatest - $0.deliveredAtStart }
            // Continuous and pulse-floored totals, logged to tell a discrepancy from rounding.
            let drainCont = outcome.doses.reduce(0.0) { $0 + $1.programmedUnits }
            let drainFloor = outcome.doses.reduce(0.0) { $0 + ($1.programmedUnits / pulseUnits).rounded(.down) * pulseUnits }
            let loanMin = offer.handedBackAt.timeIntervalSince(loanStart) / 60
            handbackDiag(offer.epoch, String(format:
                "reconcile[provisional]: delivered=%@ expected=%.3f residual=%@ (band ±0.20) · thisDrain cont=%.3f floor=%.3f · loanMin=%.0f cycles=%d fresh=%@",
                delivered.map { String(format: "%.3f", $0) } ?? "n/a", expected,
                delivered.map { String(format: "%+.3f", $0 - expected) } ?? "n/a",
                drainCont, drainFloor,
                loanMin, allStagedEvents.count, offer.odometer?.freshenSucceeded == true ? "Y" : "N"))

            // The verdict waits for the phone's own pod read.
            if isFinal, let start = offer.odometer?.deliveredAtStart {
                let windowStart = auditBase?.units ?? start
                let windowExpected = auditBase.map {
                    LoanReconciler.expectedInsulin(events: allStagedEvents, schedule: deps.settings().basalRateSchedule,
                                                   pulseUnits: pulseUnits, from: $0.asOf, to: offer.handedBackAt)
                } ?? expected
                pendingHandbackAudit = PendingHandbackAudit(
                    epoch: offer.epoch, deliveredAtStart: windowStart, expected: windowExpected,
                    loanMinutes: loanMin, cycles: allStagedEvents.count,
                    watchLatest: offer.odometer?.deliveredLatest,
                    watchFreshened: offer.odometer?.freshenSucceeded == true,
                    takeoverUnits: start, wholeLoanExpected: expected)
            }
        }

        let doses = outcome.doses

        // The interim's open rate record is acked but not committed; it lands finished at the end.
        let committable = events.filter { $0.id != outcome.openEventID }

        // Drop impossible doses individually, by name.
        let sane = doses.filter { $0.endDate >= $0.startDate }
        if sane.count != doses.count {
            let bad = doses.filter { $0.endDate < $0.startDate }
            handbackDiag(offer.epoch, "** DROPPED \(bad.count) impossible dose(s) (end before start) — writing \(sane.count) of \(doses.count). First: \(bad[0].type) \(bad[0].startDate) -> \(bad[0].endDate) **")
        }

        let writeStart = deps.now()
        handbackDiag(offer.epoch, "write START \(sane.count) dose(s) (final=\(isFinal))")

        // No ack on failure: the watch's resend is the retry.
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
                        // Release the latch first on every exit.
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
                            // A newer loan has started: an older loan's records add no carbs.
                            self.handbackDiag(offer.epoch, "stale offer — \(outcome.carbs.count) carb(s) NOT committed (a dead loan cannot add carbs)")
                        }

                        // Overrides follow the pod home on interim drains too, each in turn.
                        if !isStale {
                            for change in outcome.overrideChanges {
                                self.applyWatchOverride(change, epoch: offer.epoch, isFinal: isFinal)
                            }
                        }

                        let newCursor = events.map(\.seq).max() ?? self.committedCursor
                        if !isStale {
                            // Saved before the ack, so a relaunch does not re-commit.
                            self.updateState {
                                $0.committedCursor = max($0.committedCursor, newCursor)
                                $0.committedIDs.formUnion(committable.map(\.id))
                            }
                            // The ack, and only now that the store has it.
                            self.sendMessage(.handbackAck(HandbackAck(epoch: self.epoch, committedCursor: self.committedCursor)))
                            self.handbackDiag(self.epoch, String(format: "write DONE %.0fms → ACK cursor %d", self.deps.now().timeIntervalSince(writeStart) * 1000, self.committedCursor))
                            if isFinal, self.state == .reconciling {
                                self.finishLoanAfterCommit()
                            } else if !isFinal {
                                os_log("Interim drain committed to cursor %d — watch still dosing", log: self.log, type: .default, self.committedCursor)
                            }
                        } else {
                            // Acked so the watch can let go; no dedup state moves.
                            self.sendMessage(.handbackAck(HandbackAck(epoch: offer.epoch, committedCursor: newCursor, stale: true)))
                        }

                        // Any back-dated insulin write invalidates the counteraction memo from its earliest dose.
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

                // The identified upsert re-writes the loan window, pre-truncated. Skipped for stale offers.
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
                        self.handbackDiag(offer.epoch, "backfill SKIPPED — a stale offer speaks only for its own records")
                    }
                    finishCommit(nil)
                } else {
                    self.handbackDiag(offer.epoch, "backfill \(backfill.count) loan-window dose(s) by store identity (past the store's basal boundary)")
                    backfillEarliestStart = backfill.map(\.startDate).min()
                    self.deps.backfillDoses(backfill, finishCommit)
                }
            }
        }
    }

    /// What the watch recorded in stock's stores for a loan (its dosing decisions, alerts and
    /// device log), sent once when the loan closed (after a force reclaim, whenever the watch learned it had
    /// ended). A loan this phone never granted or adopted is ignored; an earlier loan's are kept,
    /// as a stale offer's doses are.
    func handleWatchLoanHistory(_ transfer: LoanHistory) {
        deps.whenProtectedDataAvailable { [weak self] in
            guard let self = self else { return }
            self.queue.async {
                let alerts = transfer.alerts ?? [], deviceLog = transfer.deviceLog ?? []
                guard transfer.epoch <= self.epoch else {
                    self.handbackDiag(transfer.epoch, "loan history IGNORED — \(transfer.decisions.count) dosing decision(s), \(alerts.count) alert(s), \(deviceLog.count) device log line(s) for e\(transfer.epoch), a loan this phone (e\(self.epoch)) never granted")
                    return
                }
                self.deps.addDosingDecisions(transfer.decisions) { [weak self] result in
                    switch result {
                    case .success(let added):
                        self?.handbackDiag(transfer.epoch, "dosing decisions from the watch: \(added) of \(transfer.decisions.count) added (the rest already here)")
                    case .failure(let error):
                        self?.handbackDiag(transfer.epoch, "dosing decisions from the watch NOT added — \(error)")
                    }
                }
                if !alerts.isEmpty {
                    self.deps.addAlerts(alerts) { [weak self] result in
                        switch result {
                        case .success(let changed):
                            self?.handbackDiag(transfer.epoch, "alerts from the watch: \(changed) of \(alerts.count) added or updated (the rest already here)")
                        case .failure(let error):
                            self?.handbackDiag(transfer.epoch, "alerts from the watch NOT added — \(error)")
                        }
                    }
                }
                if !deviceLog.isEmpty {
                    self.deps.addDeviceLogEntries(deviceLog) { [weak self] result in
                        switch result {
                        case .success(let added):
                            self?.handbackDiag(transfer.epoch, "device log from the watch: \(added) of \(deviceLog.count) line(s) added (the rest already here)")
                        case .failure(let error):
                            self?.handbackDiag(transfer.epoch, "device log from the watch NOT added — \(error)")
                        }
                    }
                }
            }
        }
    }

    /// Adds the decisions this store does not already hold, by id, one batch at a time, so a
    /// file delivered twice adds nothing the second time.
    static func addNewDosingDecisions(_ decisions: [StoredDosingDecision], to store: DosingDecisionStore,
                                      completion: @escaping (Result<Int, Error>) -> Void) {
        loanHistoryIntakeQueue.async {
            let semaphore = DispatchSemaphore(value: 0)
            var result: Result<Int, Error> = .success(0)
            Task {
                do {
                    let present: [StoredDosingDecision] = try await store.findDosingDecisionsByIds(decisions.map(\.id))
                    var seen = Set(present.map(\.id))
                    let new = decisions.filter { seen.insert($0.id).inserted }
                    try await store.addStoredDosingDecisions(dosingDecisions: new)
                    result = .success(new.count)
                } catch {
                    result = .failure(error)
                }
                semaphore.signal()
            }
            semaphore.wait()
            completion(result)
        }
    }

    /// Adds the device log lines this log does not already hold, comparing whole lines over the
    /// span they cover, one batch at a time, so a file delivered twice adds nothing the second time.
    static func addNewDeviceLogEntries(_ entries: [LoanDeviceLogEntry], to deviceLog: PersistentDeviceLog,
                                       completion: @escaping (Result<Int, Error>) -> Void) {
        loanHistoryIntakeQueue.async {
            guard let first = entries.map(\.timestamp).min(), let last = entries.map(\.timestamp).max() else {
                return completion(.success(0))
            }
            let semaphore = DispatchSemaphore(value: 0)
            var result: Result<Int, Error> = .success(0)
            Task {
                do {
                    let present = try await deviceLog.fetch(startDate: first, endDate: last.addingTimeInterval(1))
                    var seen = Set(present.map(LoanDeviceLogEntry.init))
                    let new = entries.filter { seen.insert($0).inserted }.compactMap(\.storedEntry)
                    try await deviceLog.addStoredDeviceLogEntries(entries: new)
                    result = .success(new.count)
                } catch {
                    result = .failure(error)
                }
                semaphore.signal()
            }
            semaphore.wait()
            completion(result)
        }
    }

    private static let loanHistoryIntakeQueue = DispatchQueue(label: "com.loopkit.Loop.PodLoanPhoneController.loanHistoryIntake")

    /// After a write: run any deferred force, then one coalesced offer.
    func drainAfterCommit() {
        if let reason = pendingForceReclaimReason {
            pendingForceReclaimReason = nil
            forceReclaimToOwner(reason: reason)
        }
        if let next = coalescedOffers.popFirst()?.value {
            handleHandbackOffer(next)
        }
    }

    /// Idempotent by the override's identifier; a clear is skipped when the phone holds none, or
    /// one newer than the clear.
    private func applyWatchOverride(_ change: LoanReconciler.OverrideChange, epoch: Int, isFinal: Bool) {
        let current = deps.scheduleOverride()
        let phase = isFinal ? "final" : "interim"
        switch change {
        case .set(let override, let changedAt):
            guard current?.syncIdentifier != override.syncIdentifier else {
                os_log("[override] from watch: SKIPPED — %{public}@ already applied (sync %{public}@)",
                       log: log, type: .default, Self.overrideNameForLog(override), override.syncIdentifier.uuidString)
                handbackDiag(epoch, "[override] SKIPPED (already applied) \(Self.overrideNameForLog(override))")
                return
            }
            deps.applyScheduleOverride(override, changedAt)
            let ends = override.duration.isInfinite ? "indefinite" : ISO8601DateFormatter().string(from: override.scheduledEndDate)
            os_log("[override] from watch: APPLIED %{public}@ · insulin needs %.0f%% · target %{public}@ · ends %{public}@ · sync %{public}@ (%{public}@ drain)",
                   log: log, type: .default, Self.overrideNameForLog(override),
                   override.settings.effectiveInsulinNeedsScaleFactor * 100,
                   Self.targetForLog(override), ends, override.syncIdentifier.uuidString, phase)
            handbackDiag(epoch, String(format: "[override] APPLIED %@ · needs %.0f%% · target %@ · ends %@ (%@ drain)",
                                       Self.overrideNameForLog(override),
                                       override.settings.effectiveInsulinNeedsScaleFactor * 100,
                                       Self.targetForLog(override), ends, phase))
        case .cleared(let changedAt):
            guard let current else {
                os_log("[override] from watch: SKIPPED clear — the phone holds no override", log: log, type: .default)
                handbackDiag(epoch, "[override] SKIPPED clear (phone already has none)")
                return
            }
            guard current.startDate <= changedAt else {
                os_log("[override] from watch: SKIPPED clear — the phone's override is newer", log: log, type: .default)
                handbackDiag(epoch, "[override] SKIPPED clear (phone's override started after it)")
                return
            }
            deps.applyScheduleOverride(nil, changedAt)
            os_log("[override] from watch: CLEARED %{public}@ — phone schedules resolve unscaled again (%{public}@ drain)",
                   log: log, type: .default, Self.overrideNameForLog(current), phase)
            handbackDiag(epoch, "[override] CLEARED \(Self.overrideNameForLog(current)) (\(phase) drain)")
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

    /// The final records are in: take the link back, resume dosing, clear staging.
    private func finishLoanAfterCommit() {
        cancelReclaimLadder()
        cancelNotification(id: NotificationID.paused)

        // A force deferred behind this commit is satisfied by the close.
        pendingForceReclaimReason = nil

        // A newer loan is live: commit the books but do not take the pod.
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
        // The state observer opens the settle window.
        reclaimPodConnection()
        pendingRevoke = false
        state = .owner
        deps.setAutomaticDosingPaused(false)
        staged = [:]
        stagedTombstones = []
        persistStaged()

        updateState { $0.audit.deliveredAtGrant = nil }
    }

}
