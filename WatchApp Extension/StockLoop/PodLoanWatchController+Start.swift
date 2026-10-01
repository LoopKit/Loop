//
//  PodLoanWatchController+Start.swift
//  WatchApp Extension
//
//  Asking for the pod, and taking it over.
//
//  A grant is a whole session in one message: the pod's raw state, the phone's therapy settings,
//  its insulin, carb and glucose history, its override and its loop mode. Intake takes ALL of it
//  or refuses out loud and leaves the watch startable — a half-built loan dosing on part of the
//  phone's history is the failure this file exists to make impossible.
//
//  The takeover itself is a read ladder against the pod. The loan is not `.active` until the pod
//  answers, and the grant's lease is re-checked on every iteration, because watchOS can suspend
//  the app in the middle of one.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import OmnipodKit
import WatchKit
import os.log

extension PodLoanWatchController {

    /// One line of sensor state for the takeover log. The pod and the G7 share a single radio, so
    /// a slow ladder cannot be read without knowing what the sensor was doing at the time.
    func g7StateForContention() -> String {
        loopManager.g7ContentionSummary
    }

    /// Seed the insulin book from the grant, BLOCKING, and report whether it worked. A wrist
    /// without the phone's history must not dose, so a failed seed refuses the whole takeover.
    ///
    /// Only FINISHED doses are seeded. A dose still delivering at takeover is carried by the
    /// grant's pod state instead: the watch's own pump manager reports it as a mutable dose on the
    /// first status read, so insulin on board tracks its delivery in real time and the eventual
    /// finalization books actual units with no seeded row to swallow it.
    func ingestGrantHistory(_ grant: LoanGrant) -> Bool {
        let seedReconciliation = self.now()
        let (entries, liveDoses) = grant.seedDoseEntries(finishedBy: seedReconciliation)
        let epoch = grant.epoch
        let grossImpliedSum = entries.reduce(0.0) { $0 + $1.programmedUnits }
        let liveNote = liveDoses.isEmpty ? "" :
            String(format: "; %d live — delivery tracked from pod state (#72), latest ends +%.0fm",
                   liveDoses.count, (liveDoses.map { $0.endDate }.max()!.timeIntervalSince(seedReconciliation)) / 60)

        let gate = DispatchSemaphore(value: 0)
        var seedError: Error?
        let loopManager = self.loopManager
        Task {
            // Reset then seed, once per loan. A row persisted from a previous loan and its
            // re-seeded twin from this grant carry DIFFERENT identities, and the reset is what
            // keeps one physical dose to one row.
            await loopManager.resetInsulinBook(reason: "new grant (epoch \(epoch))")
            do { try await loopManager.seedInsulinHistory(entries) } catch { seedError = error }
            gate.signal()
        }
        gate.wait()
        if let seedError {
            SportLog.event("loan", "** INSULIN BOOK SEED FAILED — \(String(describing: seedError)) — refusing the takeover: a wrist without the phone's history must not dose **")
            return false
        }
        SportLog.event("loan", String(format: "insulin book seeded from grant — %d finished record(s) under the phone's identities%@ · grossImpliedΣ=%.2fU",
                                       entries.count, liveNote, grossImpliedSum))

        // Diagnostic only, and asynchronous: the seeded insulin on board at the takeover instant,
        // which is the number to compare against the phone's own at the same moment when a loan's
        // opening dose is ever questioned.
        loopManager.primeIOBFromStore(at: seedReconciliation) { iob in
            guard let iob = iob else {
                SportLog.event("loan", "SEED-IN IOB unavailable (no schedule yet)")
                return
            }
            SportLog.event("loan", String(format: "SEED-IN IOB=%.2fU @ takeover (%d seeded doses: %d finished%@)",
                                          iob, entries.count + liveDoses.count, entries.count, liveNote))
            self.loopManager.dumpIOBDecomp("SEED-IN", at: seedReconciliation)
        }
        ingestGrantCarbs(grant)
        ingestGrantGlucose(grant)
        return true
    }

    /// Replace the watch's carb store with the grant's, wholesale.
    ///
    /// `setSyncCarbObjects` wipes and replaces, which is the point: an EMPTY carb history is a
    /// clean wipe, so a residual from a previous epoch — or an entry the user deleted on the phone
    /// — cannot survive on the watch and keep driving dosing. An upsert never deletes what is
    /// absent, so both would live on here, still driving dosing, until they aged out.
    ///
    /// The result is verified by reading the stored IDENTITIES back, not by comparing computed
    /// COB: two different carb sets can agree on COB and disagree on everything that matters.
    ///
    /// A grant carrying no carb history at all — an older phone — wipes exactly as an empty one
    /// does. The log tells the two apart; the behaviour deliberately does not.
    func ingestGrantCarbs(_ grant: LoanGrant) {
        let phoneCOB = grant.predictionSnapshot?.cobGrams
        let phoneCOBStr = phoneCOB.map { String(format: "%.1f", $0) } ?? "n/a"

        let snapshotAge = grant.predictionSnapshot.map { self.now().timeIntervalSince($0.snapshotAt) }
        let carbs = grant.carbHistory ?? []
        // Seeded entries are deliberately not this app's work — the phone authored them — which
        // is also why deleting one on the wrist has to use the door that skips stock's authorship
        // checks: both of them refuse an entry with no uuid that this app did not create.
        let objects: [SyncCarbObject] = carbs.map { c in
            SyncCarbObject(
                absorptionTime: c.absorptionTime,
                createdByCurrentApp: false,
                foodType: c.foodType,
                grams: c.grams,
                startDate: c.startDate,
                uuid: nil,
                provenanceIdentifier: c.provenanceIdentifier,
                syncIdentifier: c.syncIdentifier,
                syncVersion: c.syncVersion,
                userCreatedDate: c.userCreatedDate,
                userUpdatedDate: c.userUpdatedDate,
                userDeletedDate: nil,
                operation: .create,
                addedDate: nil,
                supercededDate: nil)
        }
        let seededGrams = carbs.reduce(0.0) { $0 + $1.grams }
        let source = (grant.carbHistory == nil) ? "absent(old phone)"
                   : (carbs.isEmpty ? "empty(deleted on phone)→wipe" : "\(objects.count) entr\(objects.count == 1 ? "y" : "ies")")
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let manifest = carbs.isEmpty ? "—" : carbs.map { c in
            String(format: "%.1fg@%@ sync=%@ prov=%@", c.grams, tf.string(from: c.startDate),
                   c.syncIdentifier ?? "nil", String(c.provenanceIdentifier.prefix(12)))
        }.joined(separator: " | ")

        loopManager.carbStore.setSyncCarbObjects(objects) { [weak self] error in
            if let error = error {
                os_log("Grant carb replace failed: %{public}@", log: OSLog(subsystem: "com.loopkit.Loop", category: "PodLoanWatchController"), type: .error, String(describing: error))
                return
            }

            // Read back and compare identities: RESIDUAL is an entry the wipe should have removed
            // and did not, MISSING is one of the grant's that never landed, DUPLICATE is one
            // stored twice. The verdict is LOGGED and the loan proceeds — refusing a takeover
            // because a carb store is untidy would be the worse trade — but a phantom-COB report
            // is unanswerable without this line.
            guard let self = self else { return }
            let expectedIDs = Set(carbs.compactMap { $0.syncIdentifier })
            let readFrom = (carbs.map(\.startDate).min() ?? self.now()).addingTimeInterval(-3600)
            self.loopManager.carbStore.getCarbEntries(start: readFrom) { result in
                var verdict: String
                switch result {
                case .failure(let e):

                    verdict = " ⚠ wipe UNVERIFIED (read-back failed: \(e))"
                case .success(let stored):
                    let storedIDs = Set(stored.compactMap { $0.syncIdentifier })
                    let residual = storedIDs.subtracting(expectedIDs)
                    let missing = expectedIDs.subtracting(storedIDs)
                    let dupes = stored.count - storedIDs.count
                    if residual.isEmpty && missing.isEmpty && dupes == 0 {
                        verdict = " · wipe verified \(stored.count)/\(expectedIDs.count)"
                    } else {
                        verdict = String(format: " ⚠ WIPE FAILED — %d residual, %d missing, %d duplicate",
                                         residual.count, missing.count, dupes)
                    }
                }
                self.loopManager.glanceCarbsOnBoard { cob in
                    let postV = cob ?? 0
                    let vsPhone = phoneCOB.map { postV - $0 }

                    let ageStr = snapshotAge.map { "\(Int($0.rounded()))s" } ?? "n/a"
                    SportLog.event("cob-diff", String(format: "REPLACE %@ · phoneCOB=%@ g (snapshot age %@) · watch COB(post)=%.2f g · replaced %.0f g · Δ(post−phone)=%@ g (observation freshness, not a model split)%@ · [%@]",
                                                       source, phoneCOBStr, ageStr, postV, seededGrams,
                                                       vsPhone.map { String(format: "%+.2f", $0) } ?? "—",
                                                       verdict, manifest))
                }
            }
        }
    }

    /// Seed the phone's recent glucose so momentum and retrospective correction are warm from the
    /// first post-takeover cycle. Without it the watch's glucose store is empty for the opening
    /// minutes of every loan and the prediction ignores history entirely.
    func ingestGrantGlucose(_ grant: LoanGrant) {
        guard let records = grant.glucoseHistory, !records.isEmpty else { return }
        let mgdl = LoopUnit.milligramsPerDeciliter
        let mgdlPerMin = mgdl.unitDivided(by: .minute)
        let samples: [NewGlucoseSample] = records.map { r in
            NewGlucoseSample(
                date: r.startDate,
                quantity: LoopQuantity(unit: mgdl, doubleValue: r.valueMgdl),
                condition: nil,
                trend: nil,
                trendRate: r.trendRateMgdlPerMin.map { LoopQuantity(unit: mgdlPerMin, doubleValue: $0) },
                isDisplayOnly: r.isDisplayOnly,
                wasUserEntered: r.wasUserEntered,
                syncIdentifier: r.syncIdentifier ?? "loanv2-glucose-\(Int(r.startDate.timeIntervalSince1970 * 1000))")
        }

        // These samples came out of the phone's own store, so "via iPhone" IS their provenance —
        // stamped here, or the provenance line reads blank for the first minutes of every loan.
        loopManager.notePhoneGlucoseDelivered()
        Task {
            do {
                let stored = try await loopManager.glucoseStore.addGlucoseSamples(samples)

                SportLog.event("glucose", "INGEST src=grant-seed stored=\(stored.count)/\(samples.count) · loan takeover warm-up")
                SportLog.event("loan", "seeded \(stored.count) glucose sample\(stored.count == 1 ? "" : "s") from the phone (momentum/RC warm-up)")
            } catch {
                os_log("Grant glucose ingest failed: %{public}@", log: OSLog(subsystem: "com.loopkit.Loop", category: "PodLoanWatchController"), type: .error, String(describing: error))
            }
        }
    }

    /// Stash the phone's last prediction and log it beside ours. Nothing that doses reads it; it
    /// is the only way to compare the two devices' arithmetic across the boundary afterwards.
    func ingestPredictionSnapshot(_ grant: LoanGrant) {
        loopManager.stashPhonePredictionSnapshot(grant.predictionSnapshot)
        guard let s = grant.predictionSnapshot else { return }
        let now = self.now()
        SportLog.event("snapshot", String(format:
            "RX phone@grant — eventual %.0f start %.0f@%.0fs IOB %.2f@%.0fs COB %.0f · impact mom %+.0f ins %+.0f carb %+.0f RC %+.0f · momPts %d rcDisc %d · snapAge %.0fs",
            s.eventualMgdl, s.startGlucoseMgdl, now.timeIntervalSince(s.startGlucoseDate),
            s.iobUnits, now.timeIntervalSince(s.iobDate), s.cobGrams,
            s.impactMomentumMgdl, s.impactInsulinMgdl, s.impactCarbMgdl, s.impactRCMgdl,
            s.momentumPointCount, s.rcDiscrepancyCount, now.timeIntervalSince(s.snapshotAt)))
    }

    /// Where every refusal and every failed start lands.
    ///
    /// Undrained records make it a parked drain, whose resend chain is re-kicked here; otherwise
    /// plain idle. Routing every refusal through this is what keeps a rejection from stranding the
    /// controller in `.requested` with no armed timer, where Start is a silent no-op until the
    /// next relaunch.
    func returnToRestingPhase() {
        if journal.hasUndrainedEvents {
            phase = .recoveredDrain
            sendHandbackOffer(freshened: false, recovered: true)
        } else {
            phase = .idle
        }
    }

    /// Ask the phone for the pod.
    ///
    /// The timeout is 60 s with the phone reachable and 8 s without. The grant now includes the
    /// phone's own cancel-before-release round-trip to the pod on top of message delivery, so a
    /// short timeout would give up with the pod already released — the worst shape available, an
    /// offer to seize a pod the phone has just let go of. Reachability only ACCELERATES the
    /// timeout; it never gates the attempt, because it reads false for a healthy backgrounded
    /// phone.
    func requestLoan(watchBuild: String) {
        #if targetEnvironment(simulator)

        let simFakeFlow = defaults.bool(forKey: "sim.fakeLoanFlow")
        SportLog.event("loan", "Start (sim): sim.fakeLoanFlow=\(simFakeFlow) — \(simFakeFlow ? "FAKE flow driver" : "REAL loan protocol")")
        if simFakeFlow { simDriveStart(); return }
        #endif
        queue.async {
            guard self.phase == .idle || self.phase == .recoveredDrain else {
                SportLog.event("loan", "Start ignored — not idle (phase \(self.phase.rawValue))")
                return
            }
            // Starting over a parked drain is allowed: the old loan's records keep resending
            // under their own epoch, and a seize would fold them into the new one instead.
            if self.phase == .recoveredDrain {
                SportLog.event("loan", "Start over a parked drain — \(self.journal.unackedEvents().count) undrained event(s) keep resending; a seize would fold them in [seize]")
            }
            self.phase = .requested
            self.attemptStartedAt = self.now()
            self.lastIdleNote = nil

            let reachable = self.isPhoneReachable()

            let timeout: TimeInterval = reachable ? 60 : 8
            SportLog.event("loan", "REQUEST sent (build \(watchBuild)) — awaiting grant\(reachable ? "" : " (phone unreachable — short \(Int(timeout))s timeout)")")
            self.sendMessage(.request(LoanRequest(watchBuild: watchBuild, supportsSeize: true, sentAt: self.now())))

            self.requestTimeoutWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.phase == .requested else { return }

                defer { self.notifyUI() }
                self.returnToRestingPhase()

                // The request is no longer wanted, so nothing of it may stay in the queue: one
                // delivered at reunion, inside the phone's freshness window, grants a fresh epoch
                // over whatever this watch does next.
                self.cancelStaleQueuedRequests(context: "request timed out")

                // A stored credential turns a timeout into an offer to start without the phone.
                // Its age is SHOWN in the confirmation and never enforced — staleness is the
                // user's call, and the lease bounds the handshake rather than the credential.
                if let dormant = self.storedDormantGrant() {
                    self.seizeOffer = (issuedAt: dormant.issuedAt, token: dormant.seizeToken)
                    self.lastIdleNote = nil
                    SportLog.event("seize", String(format: "REQUEST TIMED OUT (reachable=%@) — offering offline start (credential issued %@) [seize]",
                                                   self.isPhoneReachable() ? "Y" : "N",
                                                   DateFormatter.localizedString(from: dormant.issuedAt, dateStyle: .short, timeStyle: .short)))
                    return
                }

                if self.isPhoneReachable() {
                    SportLog.event("loan", "REQUEST TIMED OUT with phone REACHABLE — one-way wedge signature (#113)")
                }
                self.lastIdleNote = NSLocalizedString("No response from iPhone — check the phone (loan refused, or busy) and try again.", comment: "Glance: loan request timed out")
                SportLog.event("loan", "REQUEST TIMED OUT — no grant in \(Int(timeout))s (phone refused / busy / unreachable)")
            }
            self.requestTimeoutWork = work
            self.schedule(after: timeout, label: "request-timeout", execute: work)
        }
    }

    /// Rebuild the phone's settings from the grant.
    ///
    /// The supplement is not optional in practice: `LoopSettings.rawValue` drops the basal, ISF
    /// and carb-ratio schedules and the insulin model on this branch. Missing schedules make the
    /// watch refuse the grant loudly; a missing insulin model would degrade it SILENTLY to the
    /// rapid-acting-adult curve, which is why the model is carried and logged with the rest.
    static func decodeTherapySettings(raw: Data, supplement: Data?) -> LoopSettings? {
        var decodedSettings: LoopSettings?
        if let raw = (try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil)) as? LoopSettings.RawValue {
            decodedSettings = LoopSettings(rawValue: raw)
        }

        if var s = decodedSettings, let data = supplement,
           let supplement = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
            if let raw = supplement["basalRateSchedule"] as? BasalRateSchedule.RawValue {
                s.basalRateSchedule = BasalRateSchedule(rawValue: raw)
            }
            if let raw = supplement["insulinSensitivitySchedule"] as? InsulinSensitivitySchedule.RawValue {
                s.insulinSensitivitySchedule = InsulinSensitivitySchedule(rawValue: raw)
            }
            if let raw = supplement["carbRatioSchedule"] as? CarbRatioSchedule.RawValue {
                s.carbRatioSchedule = CarbRatioSchedule(rawValue: raw)
            }
            if let raw = supplement["defaultRapidActingModel"] as? ExponentialInsulinModelPreset.RawValue {
                s.defaultRapidActingModel = ExponentialInsulinModelPreset(rawValue: raw)
            }
            decodedSettings = s
            SportLog.event("loan", "grant settings supplement applied — basal \(s.basalRateSchedule == nil ? "MISSING" : "ok"), ISF \(s.insulinSensitivitySchedule == nil ? "MISSING" : "ok"), CR \(s.carbRatioSchedule == nil ? "MISSING" : "ok"), model \(s.defaultRapidActingModel.map { String(describing: $0) } ?? "default")")
        }
        return decodedSettings
    }

    /// Take a grant and either build the whole loan from it or refuse it in a way that leaves
    /// Start working.
    ///
    /// The order is deliberate: phase check, cancel the request timeout, the four independent
    /// rejections, therapy-settings completeness, and only then anything that touches the journal,
    /// the epoch or the pod. A refusal must leave no journal or epoch residue behind it.
    func handleGrant(_ grant: LoanGrant) {
        SportLog.event("loan", "GRANT received — epoch \(grant.epoch), \(grant.pumpManagerRawState.count)B pod state")

        // Any grant that is not this watch's own seize activation retires a pending token: it
        // belongs to an activation that is not going to happen.
        if !seizeActivationInFlight { pendingSeizeToken = nil }

        guard phase == .idle || phase == .requested || phase == .recoveredDrain else {
            SportLog.event("loan", "grant ignored — wrong phase (\(phase.rawValue))")

            // Answered with what we hold rather than with silence: a phone probing for a grant
            // that never landed reads silence as "no watch" and parks its own hand-over.
            if phase == .active, (epoch ?? Int.min) >= grant.epoch {
                sendHoldsPodStatusReport(reason: "stale grant e\(grant.epoch) refused")
            }
            return
        }
        // Cancelled AFTER the phase check and BEFORE the rejections below, each of which returns
        // to a resting phase: a rejection that left `.requested` standing with no timer would make
        // Start a silent no-op until the next relaunch.
        requestTimeoutWork?.cancel()

        // Every refusal goes through here, so none of them can forget to leave a resting phase.
        // `notifyPhone` is the distinction between a grant that failed — the phone should stop
        // waiting on it — and one this watch is merely declining as stale or duplicate, where the
        // phone's own loan may be perfectly healthy and must not be told its takeover failed.
        func rejectGrant(_ reason: String, notifyPhone: Bool) {
            SportLog.event("loan", "grant REJECTED — \(reason); returning to resting so Start works again")
            if notifyPhone {
                sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: reason)))
            }
            returnToRestingPhase()
        }
        // Four independent rejections. The lease has run out, so the phone is entitled to have
        // reclaimed already; or we already know an epoch at least this new.
        guard self.now() < grant.expiresAt || seizeActivationInFlight else {
            rejectGrant("grant expired", notifyPhone: true)
            return
        }
        if let known = epoch, grant.epoch <= known, !seizeActivationInFlight {
            rejectGrant("stale epoch \(grant.epoch) (known \(known))", notifyPhone: false)
            return
        }

        // The split-brain guard: the phone has already asked for this pod back. A grant queued
        // before a request timed out and delivered afterwards would otherwise leave both devices
        // believing they own the pod.
        if let revoked = lastRevokedEpoch, grant.epoch <= revoked {
            rejectGrant("epoch \(grant.epoch) at or below the last revoke (ev=\(revoked)); the phone already asked for the pod back",
                        notifyPhone: true)
            return
        }

        // A grant rides both channels, so the queued copy of one already accepted must not be
        // taken a second time after a short loan has cleared `epoch`.
        if !seizeActivationInFlight, grant.epoch <= defaults.integer(forKey: Keys.highWaterEpoch) {
            rejectGrant("epoch \(grant.epoch) already accepted once (high-water \(defaults.integer(forKey: Keys.highWaterEpoch))) — a late duplicate",
                        notifyPhone: false)
            return
        }

        // Completeness is checked BEFORE the journal is touched, so a refusal leaves no epoch or
        // journal residue — and an incomplete configuration becomes one legible denial rather than
        // a configuration error on every cycle for the rest of the session.
        let decodedSettings = Self.decodeTherapySettings(raw: grant.therapySettingsRaw, supplement: grant.therapySettingsSupplementRaw)
        let missing: String? = {
            guard let s = decodedSettings else { return "settings snapshot" }
            if s.basalRateSchedule == nil { return "basal schedule" }
            if s.insulinSensitivitySchedule == nil { return "insulin sensitivity" }
            if s.carbRatioSchedule == nil { return "carb ratio" }
            if s.glucoseTargetRangeSchedule == nil { return "glucose target range" }
            if s.maximumBasalRatePerHour == nil { return "max basal rate" }
            if s.maximumBolus == nil { return "max bolus" }
            return nil
        }()
        if let missing = missing {
            returnToRestingPhase()
            lastIdleNote = String(format: NSLocalizedString("Can't start: %@ didn't arrive from the phone. Check therapy settings and try again.", comment: "Glance: grant refused for incomplete settings (1: missing field)"), missing)
            SportLog.event("loan", "grant REFUSED — therapy settings incomplete (\(missing))")
            sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "therapy settings incomplete: \(missing)")))
            return
        }

        // A seize over a parked drain FOLDS: the old events are re-tagged into this epoch rather
        // than re-minted, so their identities survive and a stale queued offer for the old epoch
        // books the same ids into a store that dedupes them.
        if seizeActivationInFlight, journal.hasUndrainedEvents {
            let carried = journal.adoptEpoch(grant.epoch)
            SportLog.event("seize", "journal FOLDED — \(carried) undrained event(s) carried into epoch \(grant.epoch); the drain rides this loan's stream [seize]")

            // On a FOLD the token is persisted immediately rather than at `.active`: real records
            // already exist, so the phone's retro-acknowledgement door has to be open from here.
            if let token = pendingSeizeToken {
                defaults.set(token.uuidString, forKey: DormantKeys.activeToken)
                pendingSeizeToken = nil
                SportLog.event("seize", "reunion token …\(String(token.uuidString.suffix(8))) persisted at FOLD — the folded drain needs the retro-ack door [seize]")
            }
        } else {
            // Not a fold: refuse to start on top of an undrained prior loan rather than clobber
            // records the phone has never seen.
            do {
                try journal.begin(epoch: grant.epoch)
            } catch {
                rejectGrant("undrained prior loan must drain first", notifyPhone: true)
                return
            }
        }

        epoch = grant.epoch

        // The high-water mark only ever rises and is never cleared: closing a loan wipes `epoch`
        // and the journal, and that amnesia is what let back-to-back seizes reuse a spent epoch.
        defaults.set(max(defaults.integer(forKey: Keys.highWaterEpoch), grant.epoch), forKey: Keys.highWaterEpoch)
        phoneSupportsInterimHandback = grant.supportsInterimHandback ?? false
        phoneSupportsOverrideRecords = grant.supportsOverrideRecords ?? false
        handbackRequested = false
        finalOfferSent = false

        // The takeover clock restarts here rather than at the request, so the ladder's timings
        // describe the pod's answer and not how long the phone took to grant.
        attemptStartedAt = self.now()
        lastTakeoverReadAt = nil
        takeoverMaxReadGap = 0
        // Zeroed before the ladder starts: its connect counts are what separate "the link never
        // came up" from "the app was suspended" when a takeover fails.
        PodLoanConnectClock.reset()

        // Both probes exist so a failed ladder can be attributed: whether the app was awake, and
        // whether dispatch was delivering our timers on time. Without them a suspension and an
        // unreachable pod produce the same log.
        PodLoanConnectClock.appStateProbe = { RuntimeStateLog.appStateName() }
        RuntimeStateLog.probeTimerDeferral("takeover-start")
        // Force-unwrapped only because the completeness check above has already returned on nil.
        phase = .takingOver
        loopManager.settings = decodedSettings!

        // Persisted because a resume has no grant to read: this payload, the pod's raw state and
        // the takeover odometer are everything the rebuild needs, and the capability flags must
        // come back with them or a resumed loan would offer records the phone cannot read.
        var payload: [String: Any] = ["raw": grant.therapySettingsRaw,
                                      "interim": grant.supportsInterimHandback ?? false,
                                      "overrideRecords": grant.supportsOverrideRecords ?? false]
        if let supplement = grant.therapySettingsSupplementRaw { payload["supplement"] = supplement }
        defaults.set(payload, forKey: Keys.grantedTherapySettings)

        if let raw = grant.activeOverrideRaw {
            if let plist = (try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil)) as? TemporaryScheduleOverride.RawValue,
               let override = TemporaryScheduleOverride(rawValue: plist) {
                loopManager.scheduleOverride = override
            } else {
                // Stated, never silently dropped: without the override the wrist resolves every
                // schedule unscaled — full-strength insulin during exercise, which is the
                // over-delivery direction.
                SportLog.event("override", "grant carried an override the watch could NOT decode — this loan doses UNSCALED; re-tap the preset on the wrist")
            }
        }

        // Carried separately because it is not part of LoopSettings. Without it the watch runs
        // Standard retrospective correction while the phone runs Integral: different predictions
        // from identical inputs, with no error anywhere to say so.
        loopManager.setIntegralRetrospectiveCorrection(grant.integralRetrospectiveCorrectionEnabled ?? false)

        // The loan INHERITS the phone's loop mode. A phone too old to send one defaults to open:
        // advisory is the direction that cannot over-deliver.
        loopManager.setClosedLoopEnabled(grant.phoneClosedLoopEnabled ?? false,
                                         reason: grant.phoneClosedLoopEnabled == nil
                                            ? "(older phone sent no loop mode — defaulting open)"
                                            : "inherited from the phone at grant")

        // Loop recency is a property of the SYSTEM, so the boundary inherits it; this device's
        // own next cycle then keeps or loses that freshness honestly.
        if let phoneLoop = grant.lastLoopCompleted {
            loopManager.seedLastLoopCompleted(phoneLoop, source: "phone at grant")
        }

        ingestPredictionSnapshot(grant)

        if let s = decodedSettings {
            let now = self.loopManager.now()
            let isf = s.insulinSensitivitySchedule?.quantity(at: now).doubleValue(for: .milligramsPerDeciliter)
            let cr = s.carbRatioSchedule?.value(at: now)
            let basal = s.basalRateSchedule?.value(at: now)
            let target = s.glucoseTargetRangeSchedule?.quantityRange(at: now)
            let lo = target?.lowerBound.doubleValue(for: .milligramsPerDeciliter)
            let hi = target?.upperBound.doubleValue(for: .milligramsPerDeciliter)
            let csf = (isf != nil && cr != nil && cr! > 0) ? isf! / cr! : nil
            SportLog.event("settings", String(
                format: "granted @now — ISF %@ mg/dL/U · CR %@ g/U · CSF %@ mg/dL/g · basal %@ U/hr · target %@-%@ · maxBasal %@ U/hr · maxBolus %@ U",
                isf.map { String(format: "%.0f", $0) } ?? "nil",
                cr.map { String(format: "%.1f", $0) } ?? "nil",
                csf.map { String(format: "%.2f", $0) } ?? "nil",
                basal.map { String(format: "%.2f", $0) } ?? "nil",
                lo.map { String(format: "%.0f", $0) } ?? "nil",
                hi.map { String(format: "%.0f", $0) } ?? "nil",
                s.maximumBasalRatePerHour.map { String(format: "%.2f", $0) } ?? "nil",
                s.maximumBolus.map { String(format: "%.2f", $0) } ?? "nil"))

            // Logged as EFFECTIVE values, because an override rescales basal, ISF and carb ratio
            // as well as the target — and those rescaled numbers are what this loan doses on.
            if let o = self.loopManager.scheduleOverride, o.isActive(at: now) {
                let f = o.settings.effectiveInsulinNeedsScaleFactor
                SportLog.event("settings", String(
                    format: "override ACTIVE '%@' × %.2f insulin needs — effective ISF %@ mg/dL/U · CR %@ g/U · basal %@ U/hr (dosing uses THESE, not the schedule above)",
                    o.context.presetNameForLog,
                    f,
                    isf.map { String(format: "%.0f", $0 / f) } ?? "nil",
                    cr.map { String(format: "%.1f", $0 / f) } ?? "nil",
                    basal.map { String(format: "%.2f", $0 * f) } ?? "nil"))
            }
        }

        // The grant carries the phone's whole pump-manager envelope; the pod's own raw state is
        // the "state" member inside it. A snapshot that will not unwrap cannot be repaired here,
        // so the grant fails outright and the phone is told — it still has the pod.
        guard let rawValue = (try? PropertyListSerialization.propertyList(from: grant.pumpManagerRawState, options: [], format: nil)) as? [String: Any],
              var rawState = rawValue["state"] as? PumpManager.RawStateValue else {
            teardownPump()
            returnToRestingPhase()
            lastIdleNote = NSLocalizedString("Couldn't read the pod from the phone. Try again.", comment: "Glance: pump snapshot rejected")
            SportLog.event("loan", "grant FAILED — could not rebuild the pump from the phone's snapshot")
            sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "pump state snapshot rejected")))
            return
        }

        // NEVER remove `bleIdentifier` from the inherited pod state. `PodState` decodes the pod's
        // encryption key and its BLE handle in ONE `if let`, so dropping the handle silently drops
        // the KEY, and the pod then hangs up milliseconds into the first command. The phone's
        // value is inert on this device, but it is substituted — only when we have a cached handle
        // of our own — rather than cleared.
        takeoverCachedHandle = nil
        var cachedHandle: String?
        if var podRaw = rawState["podState"] as? [String: Any],
           let address = podRaw["address"] as? UInt32 {
            cachedHandle = PodLoanBleIdentifierCache.identifier(forPodAddress: address)
            if let cachedHandle {
                takeoverCachedHandle = (address, cachedHandle)
                podRaw["bleIdentifier"] = cachedHandle
                rawState["podState"] = podRaw
            }
            SportLog.event("loan", String(format: "handle for pod %08X: %@", address,
                                          cachedHandle.map { "CACHED \($0) — skipping discovery" } ?? "none yet — will discover"))
        }

        // The snapshot was serialized AFTER the phone released the pod. Left set, the driver's
        // init-time disarm drops the handle it has just armed.
        rawState["podConnectionReleased"] = false
        guard let manager = OmniPumpManager(rawState: rawState) else {
            teardownPump()
            returnToRestingPhase()
            lastIdleNote = NSLocalizedString("Couldn't read the pod from the phone. Try again.", comment: "Glance: pump snapshot rejected")
            SportLog.event("loan", "grant FAILED — could not rebuild the pump from the phone's snapshot")
            sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "pump state snapshot rejected")))
            return
        }

        manager.pumpManagerDelegate = self
        manager.delegateQueue = queue
        pumpManager = manager
        defaults.set(manager.rawState, forKey: Keys.pumpState)

        // What the phone's copy knew, captured before anything of ours runs. On a phoneless start
        // the copy can be half an hour old, and the difference between it and the pod's own
        // odometer is insulin that is in nobody's book.
        if let units = manager.podLoanInsulinDelivered, let asOf = manager.podLoanInsulinDeliveredAt {
            takeoverCopyTotal = (units, asOf)
        } else {
            takeoverCopyTotal = nil
        }
        takeoverCopyRecords = grant.doseHistory
        guard ingestGrantHistory(grant) else {
            teardownPump()
            returnToRestingPhase()
            lastIdleNote = NSLocalizedString("Couldn't build the insulin book from the phone's history. Try again.", comment: "Glance: insulin book seed failed")
            SportLog.event("loan", "grant FAILED — the insulin book could not be seeded from the phone's history")
            sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "insulin book seed failed")))
            return
        }

        // Scan only when there is no cached handle; with one, the first read dials it directly.
        let discover = takeoverCachedHandle == nil
        let armed = manager.podLoanBeginTakeover(discover: discover)
        SportLog.event("loan", "pump rebuilt — \(armed ? (discover ? "takeover scan armed" : "cached handle — the first read dials") : "no pod address!")")

        SportLog.event("loan", String(format: "takeover ladder start — lease %+.0fs, epoch %d%@",
                                      grant.expiresAt.timeIntervalSince(now()), grant.epoch,
                                      seizeMarkerActive ? " [seize]" : ""))
        queue.async { [weak self] in self?.attemptTakeoverRead(manager: manager, grant: grant, attempt: 0) }
    }

    /// Arm and disarm the pod stack's session-established hook, for the whole `.takingOver` phase.
    ///
    /// `CBPeripheral.state` read from this queue is not valid and contradicts the connect
    /// callbacks, so the stack's own event is what drives the next ladder read; the backstop
    /// covers only the case where no event fires at all.
    func setTakeoverSessionListener(_ armed: Bool) {
        guard armed else {
            PodLoanConnectClock.podLoanOnSessionEstablished = nil
            takeoverBackstop?.cancel()
            takeoverBackstop = nil
            takeoverRetryAction = nil
            return
        }
        PodLoanConnectClock.podLoanOnSessionEstablished = { [weak self] in
            guard let self = self else { return }
            self.queue.async {
                guard self.phase == .takingOver, let action = self.takeoverRetryAction else { return }
                SportLog.event("loan", "takeover: pod session ESTABLISHED (stack event) — reading now instead of waiting for the backstop")
                self.takeoverRetryAction = nil
                self.takeoverBackstop?.cancel()
                self.takeoverBackstop = nil
                // The event fires the read instead of waiting out the backstop; the quarter
                // second lets the stack finish bringing the session up first.
                self.schedule(after: 0.25, label: "session-event-settle") { action() }
            }
        }
    }

    /// The takeover ladder: read the pod's status until it answers, up to fourteen reads, driven
    /// by the stack's session event with an eight-second backstop. The loan flips to `.active`
    /// only on a read that comes back with a delivery total.
    ///
    /// The lease is re-checked on EVERY iteration and expiry outranks a good status. The ladder
    /// can run far past its nominal budget when the app is suspended in the middle of it, and past
    /// the lease the phone is entitled to have reclaimed — flipping `.active` then would put two
    /// controllers on one pod.
    func attemptTakeoverRead(manager: OmniPumpManager, grant: LoanGrant, attempt: Int, driver: String = "initial") {
        let maxAttempts = 14
        manager.podLoanReadStatus { [weak self] success in
            guard let self = self else { return }
            self.queue.async {
                // Something else has moved the loan on while this read was out. Say so and stop;
                // nothing may dose on a superseded epoch.
                guard self.phase == .takingOver, self.epoch == grant.epoch else {
                    SportLog.event("loan", "TAKEOVER SUPERSEDED — epoch \(grant.epoch) abandoned mid-ladder (now phase \(self.phase.rawValue), epoch \(self.epoch.map(String.init) ?? "nil"))")
                    return
                }

                guard self.now() < grant.expiresAt else {
                    self.teardownPump()
                    self.returnToRestingPhase()

                    // The connect clock distinguishes a pod that never answered from a watch
                    // Bluetooth stack that is wedged — the second has a fix the user can apply.
                    let wedged = PodLoanConnectClock.wedgeSignature(since: self.attemptStartedAt)
                    if wedged {
                        self.lastIdleNote = NSLocalizedString("The pod didn't answer. Turn watch Bluetooth off and on, then try again.", comment: "Glance: takeover failed with the BLE-wedge signature")
                    } else {
                        self.lastIdleNote = NSLocalizedString("Sport Mode start expired before the pod answered. Tap Start to try again.", comment: "Glance: grant lease expired mid-takeover")
                    }
                    SportLog.event("loan", "TAKEOVER ABORTED — grant lease expired mid-takeover after \(attempt + 1) read(s), epoch \(grant.epoch), wedgeSignature=\(wedged)\(self.seizeMarkerActive ? " [seize]" : "")")
                    self.sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "grant expired mid-takeover")))
                    return
                }
                if success, let delivered = manager.podLoanInsulinDelivered {
                    // The odometer at this instant is the base every later audit of this loan is
                    // measured from, so it is persisted with the loan.
                    self.revokeCapturedDelivered = nil
                    self.revokeCapturedDeliveredAt = nil
                    self.deliveredAtTakeover = delivered
                    self.defaults.set(delivered, forKey: Keys.deliveredAtTakeover)
                    self.phase = .active

                    // Promoted to persistence only HERE, at `.active`. An aborted activation
                    // never touched the pod, so nothing may later echo its token — a stale token
                    // beside a forced-fresh epoch is exactly the pair the phone's retro-ack
                    // matches on.
                    if let token = self.pendingSeizeToken {
                        self.defaults.set(token.uuidString, forKey: DormantKeys.activeToken)
                        self.pendingSeizeToken = nil
                        SportLog.event("seize", "seized loan ACTIVE — reunion token …\(String(token.uuidString.suffix(8))) persisted for the offer echo [seize]")
                    }
                    self.loopManager.pumpManager = manager
                    self.onLoanActiveChanged?(true)
                    let takeoverSecs = self.attemptStartedAt.map { self.now().timeIntervalSince($0) } ?? -1
                    SportLog.event("loan", String(format: "ACTIVE — epoch %d, pod taken after %d read(s) in %.1fs [takeover-timing], odometer %.2f U, final read driver=%@ · %@",
                                                  grant.epoch, attempt + 1, takeoverSecs, delivered, driver, RuntimeStateLog.snapshot()))
                    self.sendMessage(.takeoverComplete(TakeoverComplete(epoch: grant.epoch, firstPodStatus: self.currentPodStatus())))

                    // Book what the copy cannot explain BEFORE the first cycle, then assert our
                    // own program with a full `loop()` rather than a bespoke enact: a full cycle
                    // reuses every gate, records a cycle verdict and — the point — MINTS A JOURNAL
                    // EVENT, so the loan's first program is ours, streamed, and inside the audit.
                    self.bookInsulinTheCopyCannotExplain(podTotal: delivered, epoch: grant.epoch)
                    self.loopManager.loop()
                } else if attempt + 1 < maxAttempts {
                    if attempt == 0 {
                        SportLog.event("loan", "connecting to pod… (BLE session establishing; typically ~17s, budget ~40s)")
                    }

                    let readElapsed = self.attemptStartedAt.map { self.now().timeIntervalSince($0) } ?? -1

                    let readNow = self.now()
                    if let prev = self.lastTakeoverReadAt {
                        self.takeoverMaxReadGap = max(self.takeoverMaxReadGap, readNow.timeIntervalSince(prev))
                    }
                    self.lastTakeoverReadAt = readNow

                    // Only the first few reads: the probe is there to catch a ladder that is
                    // being deferred from the start, not to narrate a long one.
                    if attempt < 3 { RuntimeStateLog.probeTimerDeferral("ladder-read\(attempt + 1)") }

                    SportLog.event("loan", String(format: "takeover read %d/%d driver=%@ (+%.1fs) — pod BLE state %@ · %@ · %@ · %@",
                                                  attempt + 1, maxAttempts, driver, readElapsed,
                                                  manager.podLoanConnectionStateDescription,
                                                  PodLoanConnectClock.summary(since: self.attemptStartedAt),
                                                  self.g7StateForContention(),
                                                  RuntimeStateLog.snapshot()))

                    let fireRetry: (String) -> Void = { [weak self] nextDriver in
                        guard let self = self else { return }
                        self.takeoverRetryAction = nil
                        self.takeoverBackstop = nil
                        guard self.phase == .takingOver, self.epoch == grant.epoch else {
                            SportLog.event("loan", "TAKEOVER SUPERSEDED — epoch \(grant.epoch) abandoned between reads (now phase \(self.phase.rawValue), epoch \(self.epoch.map(String.init) ?? "nil"))")
                            return
                        }
                        self.attemptTakeoverRead(manager: manager, grant: grant, attempt: attempt + 1, driver: nextDriver)
                    }
                    // TWO objects, not one. Storing a single work item for both the event-driven
                    // retry and the backstop, then cancelling it before performing it, kills the
                    // ladder dead: a cancelled item releases its block and performs nothing.
                    self.takeoverRetryAction = { fireRetry("event") }
                    let backstop = DispatchWorkItem { fireRetry("backstop") }
                    self.takeoverBackstop = backstop
                    self.schedule(after: 8, label: "takeover-read", execute: backstop)
                } else {
                    self.teardownPump()
                    self.returnToRestingPhase()
                    let failSecs = self.attemptStartedAt.map { self.now().timeIntervalSince($0) } ?? -1

                    // Two different failures with two different things for the user to do: a long
                    // gap between reads means OUR POLLING was deferred — the app was suspended —
                    // rather than that the pod could not be reached.
                    let stalled = self.takeoverMaxReadGap > 20
                    let wedged = !stalled && PodLoanConnectClock.wedgeSignature(since: self.attemptStartedAt)
                    if stalled {
                        self.lastIdleNote = String(format: NSLocalizedString(
                            "Sport Mode didn't start — the watch app stopped running mid-connect (%@). Your phone still has the pod. Keep the watch awake — wrist up or screen on — and try again.",
                            comment: "Glance: takeover failed because the app was suspended"), batteryTag())
                    } else {
                        self.lastIdleNote = NSLocalizedString(
                            "Sport Mode didn't start — the pod couldn't be reached. Your phone still has it and is still looping.",
                            comment: "Glance: takeover failed — the pod link never established")
                    }
                    SportLog.event("loan", String(format: "TAKEOVER FAILED wedge=%@ — %@ after %d reads in %.1fs [takeover-timing], max inter-read gap %.1fs (event-driven; 8s backstop when no event fires), %@, final BLE state %@, %@, %@, epoch %d%@",
                                                  wedged ? "YES" : "no",
                                                  stalled ? "ladder STALLED (our polling was deferred; see cb: for whether the link was up)" : "pod unreachable",
                                                  maxAttempts, failSecs, self.takeoverMaxReadGap, batteryTag(),
                                                  manager.podLoanConnectionStateDescription,
                                                  PodLoanConnectClock.summary(since: self.attemptStartedAt),
                                                  RuntimeStateLog.snapshot(), grant.epoch,
                                                  self.seizeMarkerActive ? " [seize]" : ""))

                    self.sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: stalled ? "watch app suspended mid-takeover" : (wedged ? "watch Bluetooth wedged — toggle needed" : "couldn't establish the pod link"))))
                    // A cached handle that produced not one connect is forgotten, so the next
                    // Start pays for discovery once instead of retrying a handle that is dead.
                    if let trusted = self.takeoverCachedHandle, PodLoanConnectClock.connectCount == 0 {
                        PodLoanBleIdentifierCache.forget(podAddress: trusted.address)
                        SportLog.event("loan", "takeover: cached handle \(trusted.handle) never connected — FORGOTTEN; the next Start discovers")
                    }
                }
            }
        }
    }
}
