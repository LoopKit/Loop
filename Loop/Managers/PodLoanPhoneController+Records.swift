//
//  PodLoanPhoneController+Records.swift
//  Loop
//
//  Taking in what the watch dosed: streamed batches and hand-back offers are staged and committed.
//  The store is written before the ack; one commit at a time (others coalesce); dedup is
//  by event ID; nothing is dropped without saying so.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications

extension PodLoanPhoneController {
    /// The watch's records during a loan: staged, then committed but for a rate record still running.
    func handleBatch(_ batch: DoseRecordBatch) {
        // Records sent during a revoke count too.
        guard batch.epoch == epoch, state == .loaned || state == .reclaimPending else {
            handbackDiag(batch.epoch, "ignored \(batch.events.count) records from the watch: this phone is on e\(epoch), state \(state.rawValue)")

            // Records are the watch's word that it holds the pod: `LoanControl` decides (rows 6, 17, 19).
            // They bound when the loan started, so records that reach the phone before the watch's own
            // report are judged the same way.
            let claim = LoanControl.Claim(loan: batch.epoch > epoch ? .newer : .closed,
                                          startedAt: batch.startedNoLaterThan,
                                          refusedBefore: refusedRevivedEpochs.contains(batch.epoch))
            let decision = decideAndAct(.watchClaims(claim), why: "records from the watch on e\(batch.epoch)", claimEpoch: batch.epoch)
            if batch.epoch > epoch, decision != .sendStop, newestForeignLoanEvidence.map({ batch.epoch >= $0.epoch }) ?? true {
                newestForeignLoanEvidence = (batch.epoch, deps.now())
            }
            // Standing aside for a loan this phone's credential started: adopt it, and its records come in now.
            guard state == .owner, yieldingToInferredLoan, batch.epoch > epoch,
                  let token = batch.seizeToken, token == persisted.seizeToken else { return }
            adoptWatchStartedLoan(epoch: batch.epoch, earliestRecord: batch.events.map(\.record.startDate).min(),
                                  sentAt: batch.sentAt ?? deps.now(), odometer: batch.odometer, watchHoldsPod: true)
            handleBatch(batch)
            return
        }
        noteHoldRenewal(sentAt: batch.sentAt)
        stage(events: batch.events, tombstones: batch.tombstones)

        if let snap = batch.odometer {
            logRunningAudit(snap, context: "records")
        }

        // Committed as they arrive, so the phone's stores and screens follow the watch while it is in
        // reach. A batch with no new records still stores what has finished by the time it was sent:
        // a bolus or temp basal kept back while it ran. Records that arrive during a write wait,
        // staged, for the next one.
        let sentAt = batch.sentAt ?? deps.now()
        guard !commitInFlight else { return }
        guard !batch.events.isEmpty || !batch.tombstones.isEmpty || heldRecordHasFinished(by: sentAt) else {
            // The watch resends whatever is unacknowledged, so an empty batch means everything it had
            // recorded by then is already in the stores.
            noteRecordsCurrent(asOf: sentAt)
            return
        }
        let records = HandbackOffer(epoch: batch.epoch, handedBackAt: sentAt, finalStatus: nil,
                                    odometer: batch.odometer, events: batch.events, tombstones: batch.tombstones,
                                    recovered: false, released: false)
        commitStaged(records, isFinal: false, isStale: false, auditThisOffer: false)
    }

    /// Whether a record kept back while it ran (staged, not yet committed) has finished by `date`.
    private func heldRecordHasFinished(by date: Date) -> Bool {
        let held = staged.values.filter { !stagedTombstones.contains($0.id) && !committedIDs.contains($0.id) }
        guard !held.isEmpty else { return false }
        let open = LoanReconciler.reconcile(LoanReconciler.Input(
            events: held.sorted { $0.seq < $1.seq },
            schedule: deps.settings().basalRateSchedule,
            loanStart: loanStartedAt ?? date.addingTimeInterval(-.hours(2)),
            loanEnd: date,
            isFinalHandback: false)).openEventIDs
        return held.contains { !open.contains($0.id) }
    }

    /// Takes on a loan the watch started without this phone, proven by this phone's offline-start
    /// credential: from here its records come in as a lent loan's do (control row 17).
    func adoptWatchStartedLoan(epoch newEpoch: Int, earliestRecord: Date?, sentAt: Date,
                               odometer: LoanOdometerSnapshot?, watchHoldsPod: Bool) {
        handbackDiag(newEpoch, "adopting the loan the watch started without this phone, after e\(epoch)")

        let wasStandingAside = yieldingToInferredLoan
        clearInferredLoanYield(reason: "its loan e\(newEpoch) is adopted")
        // Anchor the adopted loan at its earliest record, at most six hours back.
        let anchor = max(earliestRecord ?? sentAt, deps.now().addingTimeInterval(-.hours(6)))
        let lastPodReading = deps.pumpManager()?.lastSync
        let previous = state
        updateState {
            $0.epoch = newEpoch
            $0.phase = .loaned
            $0.holdRenewedAt = sentAt
            $0.loanStartedAt = anchor
            // Standing aside set it already; otherwise this phone's records end at its last pod reading.
            if !wasStandingAside { $0.recordsCurrentAt = lastPodReading }
        }
        // The watch's window starts at its takeover reading when the message carries it. With an older
        // watch it starts at this phone's last reading, so the phone's own doses before it stay its own.
        if let odometer, let startAt = odometer.deliveredAtStartAt {
            noteTakeoverReading(units: odometer.deliveredAtStart, at: startAt)
        } else if let last = ledgerLast {
            handbackDiag(newEpoch, String(format: "the watch's window starts at this phone's last reading, %.2f U at %@",
                                          last.units, ISO8601DateFormatter().string(from: last.at)))
        }
        stateDidChange(from: previous)

        // Dosing authority and the radio go together.
        if watchHoldsPod, let control = deps.pumpManager() as? ExclusiveDeviceControl, !control.isControlReleased {
            control.releaseControl()
            deps.pumpControlChanged(true)
            readThePodIfKept()
        }
    }

    /// The phone's stores hold every carb and insulin record the watch had made by `date`: what the
    /// banner shows. Never moves back; messages can arrive out of order.
    func noteRecordsCurrent(asOf date: Date) {
        guard date > (persisted.recordsCurrentAt ?? .distantPast) else { return }
        updateState { $0.recordsCurrentAt = date }
    }

    /// The loan's log line, tagged with its loan number.
    func handbackDiag(_ epoch: Int, _ text: String) {
        deps.logLoanLine("e\(epoch) \(text)")
    }

    /// Interim drain, final hand-back, or stale offer, told apart by `released` and epoch.
    /// Nothing before the write may change state the phone cannot undo if the write fails.
    func handleHandbackOffer(_ offer: HandbackOffer) {
        // Retro-acknowledge a loan the watch started alone: needs the token and a higher epoch,
        // and never over a grant in flight or a live loan.
        if let token = offer.seizeToken, state == .owner || state == .reclaimPending, offer.epoch > epoch,
           token == persisted.seizeToken {
            if state == .reclaimPending {
                cancelTakeBackAttempt()
                handbackDiag(offer.epoch, "take-back stopped: the watch is handing back")
            }
            // A live offer means the watch still holds the pod. A final or recovered offer is a loan
            // already over; only its records come in.
            adoptWatchStartedLoan(epoch: offer.epoch, earliestRecord: offer.events.map(\.record.startDate).min(),
                                  sentAt: offer.handedBackAt, odometer: offer.odometer,
                                  watchHoldsPod: offer.released != true && !offer.recovered)
        }

        // An offer ahead of this phone's epoch cannot be committed.
        let isStale = offer.epoch < epoch
        guard offer.epoch == epoch || isStale else {
            handbackDiag(offer.epoch, "hand-back ignored: this phone is behind, on e\(epoch); the loan may be stranded")
            return
        }

        // One commit at a time; coalesce by epoch, and never let an interim replace a waiting final.
        if commitInFlight {
            let storedIsFinal = coalescedOffers[offer.epoch]?.released == true
            if !(storedIsFinal && offer.released != true) {
                coalescedOffers[offer.epoch] = offer
            }
            handbackDiag(offer.epoch, "hand-back waits for the write in progress, \(coalescedOffers.count) waiting")
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
            handbackDiag(offer.epoch, "hand-back refused: this phone's Bluetooth is off, so the watch keeps the loan")
            sendMessage(.denied(LoanDenied(reason: NSLocalizedString("The watch is still looping. To end, turn on iPhone Bluetooth and tap End again.", comment: "Hand-back refused: shown on the watch glance"))))
            return
        }
        // .reconciling: the phone owes an ack; the loan ends when the write lands.
        if !isStale, isFinal, canTransition {
            state = .reconciling

            handbackDiag(offer.epoch, "final hand-back received with \(offer.events.count) records; acknowledged once they are saved")
            // Where the watch confirmed it uploaded this loan's glucose, the phone's uploads resume after
            // the loan: Nightscout tells readings apart only by their time, which each device stamps
            // from its own receipt, so the phone's copies would be a second row each. Elsewhere, and
            // after a force reclaim, the phone uploads its own copies.
            let glucoseUploaded = offer.servicesConfirming("Glucose")
            if !glucoseUploaded.isEmpty { deps.skipLoanGlucoseUploads(glucoseUploaded) }
            handbackDiag(offer.epoch, "uploads: the watch confirmed \(offer.uploadsConfirmed.map { $0.isEmpty ? "none" : $0.map { "\($0.key) \($0.value.joined(separator: "+"))" }.joined(separator: "; ") } ?? "nothing (older watch)") — the phone uploads the rest")
            // Loop mode and recency come home with the pod.
            if let watchClosed = offer.watchClosedLoopEnabled {
                deps.noteWatchClosedLoop(watchClosed)
                handbackDiag(offer.epoch, "the watch's loop mode comes home: \(watchClosed ? "closed" : "open") loop")
            }

            if let watchLoop = offer.lastLoopCompleted {
                deps.noteWatchLoopCompleted(watchLoop)
            }
        }

        // Only a live final offer that moved us to reconciling leaves a verdict owed.
        let auditThisOffer = !isStale && isFinal && state == .reconciling

        stage(events: offer.events, tombstones: offer.tombstones)

        if !isStale, offer.epoch == epoch, offer.released == false, let snap = offer.odometer {
            logRunningAudit(snap, context: "interim hand-back")
        }

        commitStaged(offer, isFinal: isFinal, isStale: isStale, auditThisOffer: auditThisOffer)
    }

    /// Writes the staged records not yet committed to the stores, then acknowledges them. A rate
    /// record still running, or a bolus still being given, is acknowledged but kept back: each lands
    /// finished later. One write at a time (`commitInFlight`).
    private func commitStaged(_ offer: HandbackOffer, isFinal: Bool, isStale: Bool, auditThisOffer: Bool) {
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
            let loanMin = offer.handedBackAt.timeIntervalSince(loanStart) / 60
            handbackDiag(offer.epoch, String(format:
                "the watch's count at hand-back: delivered %@, expected %.3f U, residual %@ over %.0f min, %d records",
                delivered.map { String(format: "%.3f U", $0) } ?? "unknown", expected,
                delivered.map { String(format: "%+.3f U", $0 - expected) } ?? "unknown",
                loanMin, allStagedEvents.count))

            // The verdict waits for the phone's own pod read, over the window from the ledger's last reading.
            if isFinal, let start = offer.odometer?.deliveredAtStart {
                let base = ledgerLast
                let windowExpected = base.map {
                    LoanReconciler.expectedInsulin(events: allStagedEvents, schedule: deps.settings().basalRateSchedule,
                                                   pulseUnits: pulseUnits, from: $0.at, to: offer.handedBackAt)
                } ?? expected
                pendingHandbackAudit = PendingHandbackAudit(
                    epoch: offer.epoch, deliveredAtStart: base?.units ?? start, windowStart: base?.at ?? loanStart,
                    expected: windowExpected,
                    loanMinutes: loanMin,
                    watchLatest: offer.odometer?.deliveredLatest)
            }
        }

        let doses = outcome.doses

        // The interim's open records (a rate record still running, a bolus still being given) are
        // acked but not committed; each lands finished later. The bolus is stored meanwhile, mutable.
        let committable = events.filter { !outcome.openEventIDs.contains($0.id) }

        // Drop impossible doses individually, by name.
        let sane = doses.filter { $0.endDate >= $0.startDate }
        if sane.count != doses.count {
            let bad = doses.filter { $0.endDate < $0.startDate }
            handbackDiag(offer.epoch, "dropped \(bad.count) of \(doses.count) doses that end before they start; first: \(bad[0].type) \(bad[0].startDate) to \(bad[0].endDate)")
        }

        let writeStart = deps.now()

        // No ack on failure: the watch's resend is the retry.
        commitInFlight = true
        deps.addPumpEvents(newPumpEvents(from: sane), offer.handedBackAt) { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.commitInFlight = false
                    self.handbackDiag(offer.epoch, "saving the watch's records failed; the watch will resend: \(String(describing: error))")

                    if let reason = self.pendingForceReclaimReason {
                        self.pendingForceReclaimReason = nil
                        self.forceReclaimToOwner(reason: reason)
                    }
                    return
                }

                var backfillEarliestStart: Date? = nil

                let finishCommit: (Error?) -> Void = { [weak self] backfillError in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        // Release the latch first on every exit.
                        self.commitInFlight = false
                        if let backfillError = backfillError {
                            self.handbackDiag(offer.epoch, "saving the loan's doses in the dose store failed: \(String(describing: backfillError))")

                            if let reason = self.pendingForceReclaimReason {
                                self.pendingForceReclaimReason = nil
                                self.forceReclaimToOwner(reason: reason)
                            }
                            return
                        }

                        if !isStale {
                            for carb in outcome.carbs {
                                self.deps.addCarb(carb) { _ in }
                            }

                            for gone in outcome.deletedCarbs {
                                self.deps.deleteCarb(gone) { error in
                                    self.handbackDiag(offer.epoch, error == nil
                                        ? String(format: "carb delete from the watch applied: %.0f g", gone.grams)
                                        : String(format: "carb delete from the watch failed: %.0f g at %@: %@",
                                                 gone.grams, String(describing: gone.startDate), String(describing: error!)))
                                }
                            }
                        } else if !outcome.carbs.isEmpty {
                            // A newer loan has started: an older loan's records add no carbs.
                            self.handbackDiag(offer.epoch, "\(outcome.carbs.count) carbs from an older loan not added")
                        }

                        // Overrides follow the pod home on interim drains too, each in turn.
                        if !isStale {
                            for change in outcome.overrideChanges {
                                self.applyWatchOverride(change, epoch: offer.epoch)
                            }
                        }

                        let newCursor = events.map(\.seq).max() ?? self.committedCursor
                        if !isStale {
                            // Saved before the ack, so a relaunch does not re-commit.
                            self.updateState {
                                $0.committedCursor = max($0.committedCursor, newCursor)
                                $0.committedIDs.formUnion(committable.map(\.id))
                            }
                            self.noteRecordsCurrent(asOf: offer.handedBackAt)
                            // The ack, and only now that the store has it.
                            self.sendMessage(.handbackAck(HandbackAck(epoch: self.epoch, committedCursor: self.committedCursor)))
                            self.handbackDiag(self.epoch, String(format: "records saved in %.0f ms; acknowledged up to %d", self.deps.now().timeIntervalSince(writeStart) * 1000, self.committedCursor))
                            if isFinal, self.state == .reconciling {
                                self.finishLoanAfterCommit()
                            }
                        } else {
                            // Acked so the watch can let go; no dedup state moves.
                            self.sendMessage(.handbackAck(HandbackAck(epoch: offer.epoch, committedCursor: newCursor, stale: true)))
                        }

                        // Any back-dated insulin write invalidates the counteraction memo from its earliest dose.
                        if let earliest = (sane.map(\.startDate) + (backfillEarliestStart.map { [$0] } ?? [])).min() {
                            self.deps.insulinHistoryRewritten(earliest)
                        }

                        self.retireEstimates(coveredBy: sane, carbs: isStale ? 0 : outcome.carbs.count, epoch: offer.epoch)
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
                // A bolus still being given is the pump-event path's alone, until it has finished.
                let backfill = self.storeIdentifiedDoses(from: self.truncatingOverlaps(
                    backfillOutcome.doses.filter { $0.endDate >= $0.startDate && !$0.isMutable }))
                if isStale || backfill.isEmpty {
                    if isStale {
                        self.handbackDiag(offer.epoch, "hand-back from an older loan: only its own records are saved")
                    }
                    finishCommit(nil)
                } else {
                    self.handbackDiag(offer.epoch, "saving \(backfill.count) of the loan's doses in the dose store")
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
            DispatchQueue.main.async {
                let alerts = transfer.alerts ?? [], deviceLog = transfer.deviceLog ?? []
                guard transfer.epoch <= self.epoch else {
                    self.handbackDiag(transfer.epoch, "history from the watch ignored: this phone never granted this loan, its last is e\(self.epoch)")
                    return
                }
                self.deps.addDosingDecisions(transfer.decisions, transfer.servicesConfirming("DosingDecision")) { [weak self] result in
                    switch result {
                    case .success(let added):
                        self?.handbackDiag(transfer.epoch, "dosing decisions from the watch: \(added) of \(transfer.decisions.count) added")
                    case .failure(let error):
                        self?.handbackDiag(transfer.epoch, "dosing decisions from the watch not added: \(error)")
                    }
                }
                if !alerts.isEmpty {
                    self.deps.addAlerts(alerts) { [weak self] result in
                        switch result {
                        case .success(let changed):
                            self?.handbackDiag(transfer.epoch, "alerts from the watch: \(changed) of \(alerts.count) added or updated")
                        case .failure(let error):
                            self?.handbackDiag(transfer.epoch, "alerts from the watch not added: \(error)")
                        }
                    }
                }
                if !deviceLog.isEmpty {
                    self.deps.addDeviceLogEntries(deviceLog) { [weak self] result in
                        switch result {
                        case .success(let added):
                            self?.handbackDiag(transfer.epoch, "device log from the watch: \(added) of \(deviceLog.count) lines added")
                        case .failure(let error):
                            self?.handbackDiag(transfer.epoch, "device log from the watch not added: \(error)")
                        }
                    }
                }
            }
        }
    }

    /// Adds the decisions this store does not already hold, by id, one batch at a time, so a
    /// file delivered twice adds nothing the second time. Returns how many were added. With `skipUploads`,
    /// the uploaders hear of the batch only after it has moved the bookmarks the watch's uploads cover.
    static func addNewDosingDecisions(_ decisions: [StoredDosingDecision], to store: DosingDecisionStore,
                                      skipUploads: ((Set<UUID>) async -> Void)? = nil) async throws -> Int {
        try await oneHistoryBatchAtATime {
            let delegate = store.delegate
            if skipUploads != nil { store.delegate = nil }
            defer { store.delegate = delegate }
            let present: [StoredDosingDecision] = try await store.findDosingDecisionsByIds(decisions.map(\.id))
            var seen = Set(present.map(\.id))
            let new = decisions.filter { seen.insert($0.id).inserted }
            try await store.addStoredDosingDecisions(dosingDecisions: new)
            if let skipUploads {
                await skipUploads(Set(new.map(\.id)))
                store.delegate = delegate
                delegate?.dosingDecisionStoreHasUpdatedDosingDecisionData(store)
            }
            return new.count
        }
    }

    /// Adds the device log lines this log does not already hold, comparing whole lines over the
    /// span they cover, one batch at a time, so a file delivered twice adds nothing the second time.
    /// Returns how many were added.
    static func addNewDeviceLogEntries(_ entries: [LoanDeviceLogEntry], to deviceLog: PersistentDeviceLog) async throws -> Int {
        guard let first = entries.map(\.timestamp).min(), let last = entries.map(\.timestamp).max() else { return 0 }
        return try await oneHistoryBatchAtATime {
            let present = try await deviceLog.fetch(startDate: first, endDate: last.addingTimeInterval(1))
            var seen = Set(present.map(LoanDeviceLogEntry.init))
            let new = entries.filter { seen.insert($0).inserted }.compactMap(\.storedEntry)
            try await deviceLog.addStoredDeviceLogEntries(entries: new)
            return new.count
        }
    }

    /// The last batch of loan history taken in; the next one waits for it, so two deliveries of the
    /// same file never both find a line missing.
    private static var historyBatchTail: Task<Void, Never>?

    private static func oneHistoryBatchAtATime(_ batch: @escaping @MainActor () async throws -> Int) async throws -> Int {
        let previous = historyBatchTail
        let task = Task { @MainActor () async throws -> Int in
            await previous?.value
            return try await batch()
        }
        historyBatchTail = Task { _ = try? await task.value }
        return try await task.value
    }

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
    private func applyWatchOverride(_ change: LoanReconciler.OverrideChange, epoch: Int) {
        let current = deps.scheduleOverride()
        switch change {
        case .set(let override, let changedAt):
            guard current?.syncIdentifier != override.syncIdentifier else {
                handbackDiag(epoch, "preset from the watch already applied: \(Self.overrideNameForLog(override))")
                return
            }
            deps.applyScheduleOverride(override, changedAt)
            let ends = override.duration.isInfinite ? "indefinite" : ISO8601DateFormatter().string(from: override.scheduledEndDate)
            handbackDiag(epoch, String(format: "preset from the watch applied: %@, insulin needs %.0f%%, target %@, ends %@",
                                       Self.overrideNameForLog(override),
                                       override.settings.effectiveInsulinNeedsScaleFactor * 100,
                                       Self.targetForLog(override), ends))
        case .cleared(let changedAt):
            guard let current else {
                handbackDiag(epoch, "preset end from the watch skipped: this phone has none active")
                return
            }
            guard current.startDate <= changedAt else {
                handbackDiag(epoch, "preset end from the watch skipped: this phone's preset started later")
                return
            }
            deps.applyScheduleOverride(nil, changedAt)
            handbackDiag(epoch, "preset from the watch ended: \(Self.overrideNameForLog(current))")
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
        cancelTakeBackAttempt()
        cancelNotification(id: NotificationID.paused)

        // A force deferred behind this commit is satisfied by the close.
        pendingForceReclaimReason = nil

        // A newer loan is live: commit the books but do not take the pod.
        if supersededByLiveLoan(epoch) {
            let liveEpoch = newestForeignLoanEvidence?.epoch ?? epoch + 1
            state = .owner
            staged = [:]
            stagedTombstones = []
            persistStaged()
            pendingHandbackAudit = nil
            engageInferredLoanYield(evidence: "e\(epoch) was handed back while the watch runs e\(liveEpoch); its records are saved")
            return
        }
        // The state observer opens the settle window.
        reclaimPodConnection()
        state = .owner
        staged = [:]
        stagedTombstones = []
        persistStaged()
    }

}
