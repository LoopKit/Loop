//
//  PodLoanWatchController+Start.swift
//  WatchApp Extension
//
//  Requesting the pod and taking it over. A grant is taken whole or refused, and the loan
//  is not active until the pod answers.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController {

    /// Seeds finished doses from the grant, blocking; a failed seed refuses the takeover.
    /// A dose still delivering arrives via the pod state as a mutable dose.
    func ingestGrantHistory(_ grant: LoanGrant) -> Bool {
        let seedReconciliation = self.now()
        let (entries, liveDoses) = grant.seedDoseEntries(finishedBy: seedReconciliation)
        let epoch = grant.epoch
        let grossImpliedSum = entries.reduce(0.0) { $0 + $1.programmedUnits }
        let liveNote = liveDoses.isEmpty ? "" :
            String(format: "; %d live — delivery tracked from pod state, latest ends +%.0fm",
                   liveDoses.count, (liveDoses.map { $0.endDate }.max()!.timeIntervalSince(seedReconciliation)) / 60)

        let gate = DispatchSemaphore(value: 0)
        var seedError: Error?
        let loopManager = self.loopManager
        Task {
            // Reset first, so one physical dose stays one row.
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

        // The display run, so the glance shows the inherited insulin from takeover; its IOB is
        // also logged to compare with the phone's.
        loopManager.updateDisplayState { state in
            guard let iob = state.activeInsulin?.value else {
                SportLog.event("loan", "SEED-IN IOB unavailable (display run incomplete: no settings or no recent glucose yet)")
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

    /// Replaces the carb store wholesale, so deleted or stale entries cannot keep dosing.
    /// Verified by reading identities back, not by comparing COB.
    func ingestGrantCarbs(_ grant: LoanGrant) {
        let carbs = grant.carbHistory ?? []
        // Each entry keeps the phone's authorship: Loop's own can be deleted here, another app's cannot.
        let objects: [SyncCarbObject] = carbs.map { c in
            SyncCarbObject(
                absorptionTime: c.absorptionTime,
                createdByCurrentApp: c.createdByCurrentApp ?? false,
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

            // Logs residual, missing and duplicate entries; the loan proceeds either way.
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
                    SportLog.event("cob-diff", String(format: "REPLACE %@ · watch COB(post)=%.2f g · replaced %.0f g%@ · [%@]",
                                                       source, postV, seededGrams, verdict, manifest))
                }
            }
        }
    }

    /// Seeds recent glucose so momentum and retrospective correction are warm on the first cycle.
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

        // These samples came from the phone, so stamp them as such.
        loopManager.noteGlucoseSource(directG7: false)
        Task {
            do {
                let stored = try await loopManager.glucoseStore.addGlucoseSamples(samples)

                SportLog.event("glucose", "INGEST src=grant-seed stored=\(stored.count)/\(samples.count) · loan takeover warm-up")
                SportLog.event("loan", "seeded \(stored.count) glucose sample\(stored.count == 1 ? "" : "s") from the phone (momentum/RC warm-up)")
                // Rerun the display now the phone's glucose is in: the takeover's first display
                // run may have found none.
                self.loopManager.updateDisplayState()
            } catch {
                os_log("Grant glucose ingest failed: %{public}@", log: OSLog(subsystem: "com.loopkit.Loop", category: "PodLoanWatchController"), type: .error, String(describing: error))
            }
        }
    }

    /// Every refusal and failed start lands here, so none can strand the controller in `.requested`.
    func returnToRestingPhase() {
        if journal.hasUndrainedEvents {
            phase = .recoveredDrain
            sendHandbackOffer(recovered: true)
        } else {
            phase = .idle
        }
    }

    /// The offline start is a backup, offered when the phone does not answer within 10 s. The request
    /// is the question; whether the phone looks reachable decides nothing (control row 2).
    func requestLoan(watchBuild: String) {
        #if targetEnvironment(simulator)

        SportLog.event("loan", "Start (sim): simFakeLoanFlow=\(simFakeLoanFlow) — \(simFakeLoanFlow ? "FAKE flow driver" : "REAL loan protocol")")
        if simFakeLoanFlow { simDriveStart(); return }
        #endif
        queue.async {
            guard self.phase == .idle || self.phase == .recoveredDrain else {
                SportLog.event("loan", "Start ignored — not idle (phase \(self.phase.rawValue))")
                return
            }
            // Allowed over a parked drain: its records keep resending under their own epoch.
            if self.phase == .recoveredDrain {
                SportLog.event("loan", "Start over a parked drain — \(self.journal.unackedEvents().count) undrained event(s) keep resending; a seize would fold them in [seize]")
            }
            self.startCancelled = false
            self.phase = .requested
            self.attemptStartedAt = self.now()
            self.lastIdleNote = nil
            self.withdrawSeizeOffer(reason: "a new Start request went out")

            SportLog.event("loan", "REQUEST sent (build \(watchBuild)) — awaiting grant")
            let known = max(self.epoch ?? 0, self.journal.activeEpoch ?? 0, self.persisted.highWaterEpoch, self.lastRevokedEpoch ?? 0)
            self.sendMessage(.request(LoanRequest(watchBuild: watchBuild, supportsSeize: true, sentAt: self.now(), knownEpoch: known)))

            // Rows 1 and 2: the request is the query; `LoanControl` decides the wait and what silence means.
            let situation = LoanControl.Situation(device: .watch, trigger: .startTapped)
            guard case .query(let wait, _) = LoanControl.decide(situation) else { return }
            self.armRequestTimeout(wait.seconds)
        }
    }

    /// An unreachable phone at an End is read again this much later: just after the app comes on
    /// screen, reachability reads false for a moment with the phone there.
    static let unreachableRecheck: TimeInterval = 1

    /// On `queue`. The timeout ends the request; a stored credential turns it into the offline offer.
    private func armRequestTimeout(_ timeout: TimeInterval) {
        requestTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.phase == .requested else { return }

            defer { self.notifyUI() }
            self.returnToRestingPhase()

            // A queued request delivered later would grant a fresh epoch over whatever happens next.
            self.cancelStaleQueuedRequests(context: "request timed out")

            // Decided when the silence is known, with the copy as it is now: offer the offline start if this
            // watch holds a copy (its age is shown, not enforced), else say the phone did not answer.
            let dormant = self.storedDormantGrant()
            let situation = LoanControl.Situation(device: .watch, trigger: .startTapped, watchHasStoredCopy: dormant != nil)
            guard case .query(_, let onSilence) = LoanControl.decide(situation) else { return }
            if case .prompt(.startWithoutPhone) = LoanControl.afterQuery(.silence, onSilence: onSilence), let dormant {
                self.seizeOffer = (issuedAt: dormant.issuedAt, token: dormant.seizeToken)
                self.lastIdleNote = nil
                SportLog.event("seize", String(format: "REQUEST TIMED OUT — no answer from the phone; offering offline start (credential issued %@) [seize]",
                                               DateFormatter.localizedString(from: dormant.issuedAt, dateStyle: .short, timeStyle: .short)))
                return
            }

            self.lastIdleNote = NSLocalizedString("No answer from iPhone. Open Loop on the iPhone and try again.", comment: "Glance: loan request timed out")
            SportLog.event("loan", "REQUEST TIMED OUT — no grant in \(Int(timeout))s (phone refused / busy / unreachable)")
        }
        requestTimeoutWork = work
        schedule(after: timeout, label: "request-timeout", execute: work)
    }

    /// The offer answers one unanswered request; a later grant or Start makes it stale. On `queue`.
    private func withdrawSeizeOffer(reason: String) {
        guard seizeOffer != nil else { return }
        seizeOffer = nil
        SportLog.event("seize", "offline offer WITHDRAWN — \(reason) [seize]")
    }

    /// Resting, with a standing copy of a pump this watch would have to search for: Start needs the screen on.
    func pumpFirstContactExpected() -> Bool {
        guard phase == .idle || phase == .recoveredDrain, let configuration = standingPumpConfiguration else { return false }
        return watchTakeControlNeedsSearch(adopting: configuration, localState: pumpLocalState(for: configuration))
    }

    static let firstContactStartNote = NSLocalizedString(
        "New pod — keep your wrist up after Start",
        comment: "Glance note above Start when this watch has never connected to the current pod")

    /// The hint under the takeover bar; only a first contact needs one.
    static func takeoverHint(firstContact: Bool, podReached: Bool, nudged: Bool) -> String? {
        guard firstContact else { return nil }
        if podReached {
            return NSLocalizedString("Pod found — you can lower your wrist.", comment: "Glance: takeover reached the pod")
        }
        if nudged {
            return NSLocalizedString("Raise your wrist to finish connecting.", comment: "Glance: first takeover stuck with the screen off")
        }
        return NSLocalizedString("Keep your wrist up until the pod is found.", comment: "Glance: first takeover of a pod")
    }

    /// Tap the wrist only while the pod is unreached and the screen is off, at most twice.
    static func shouldNudgeTakeover(podReached: Bool, appActive: Bool, nudgesSoFar: Int) -> Bool {
        !podReached && !appActive && nudgesSoFar < 2
    }

    /// `LoopSettings.rawValue` drops the schedules and insulin model, so the supplement carries them.
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

    /// Builds the whole loan from a grant or refuses it, leaving Start working. Nothing touches
    /// the journal, epoch or pod until every check has passed.
    func handleGrant(_ grant: LoanGrant) {
        SportLog.event("loan", "GRANT received — epoch \(grant.epoch), \(grant.pumpConfiguration.count)B pump configuration")

        // Any other grant retires a pending seize token.
        if !seizeActivationInFlight { pendingSeizeToken = nil }

        guard phase == .idle || phase == .requested || phase == .recoveredDrain else {
            SportLog.event("loan", "grant ignored — wrong phase (\(phase.rawValue))")

            // Answer a duplicate with what we hold; silence reads as "no watch".
            if phase == .active, (epoch ?? Int.min) >= grant.epoch {
                sendHoldsPodStatusReport(reason: "stale grant e\(grant.epoch) refused")
            }
            return
        }
        // After the phase check and before any rejection, each of which returns to rest.
        requestTimeoutWork?.cancel()

        // `notifyPhone` is false when merely declining a stale or duplicate grant.
        func rejectGrant(_ reason: String, notifyPhone: Bool) {
            SportLog.event("loan", "grant REJECTED — \(reason); returning to resting so Start works again")
            if notifyPhone {
                sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: reason)))
            }
            returnToRestingPhase()
        }
        // A Start the looper cancelled at the offline offer: the grant starts nothing, and the phone,
        // told, takes the pod back at once (transfer G). Sport Mode is entered only by a tap.
        if phase == .idle, startCancelled, !seizeActivationInFlight {
            rejectGrant("the Start was cancelled on the watch", notifyPhone: true)
            return
        }
        // Lease expired, or an epoch at least this new is already known.
        guard self.now() < grant.expiresAt || seizeActivationInFlight else {
            rejectGrant("grant expired", notifyPhone: true)
            return
        }
        // Told to the phone: left waiting, it would hold the pod released until its dead-man ran out.
        if let known = epoch, grant.epoch <= known, !seizeActivationInFlight {
            rejectGrant("stale epoch \(grant.epoch) (known \(known))", notifyPhone: true)
            return
        }

        // The phone already asked for this pod back; taking it would mean two owners.
        if let revoked = lastRevokedEpoch, grant.epoch <= revoked {
            rejectGrant("epoch \(grant.epoch) at or below the last revoke (ev=\(revoked)); the phone already asked for the pod back",
                        notifyPhone: true)
            return
        }

        // The second channel's copy of a grant already taken.
        if !seizeActivationInFlight, grant.epoch <= persisted.highWaterEpoch {
            rejectGrant("epoch \(grant.epoch) already accepted once (high-water \(persisted.highWaterEpoch)) — a late duplicate",
                        notifyPhone: false)
            return
        }

        // Checked before the journal is touched, so a refusal leaves no residue.
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

        // A seize over a parked drain folds the old events into this epoch, keeping their identities.
        if seizeActivationInFlight, journal.hasUndrainedEvents {
            let carried = journal.adoptEpoch(grant.epoch)
            SportLog.event("seize", "journal FOLDED — \(carried) undrained event(s) carried into epoch \(grant.epoch); the drain rides this loan's stream [seize]")

            // A fold persists the token now: real records already exist.
            if let token = pendingSeizeToken {
                updateState { $0.seizeToken = token }
                pendingSeizeToken = nil
                SportLog.event("seize", "reunion token …\(String(token.uuidString.suffix(8))) persisted at FOLD — the folded drain needs the retro-ack door [seize]")
            }
        } else {
            // Not a fold: refuse rather than clobber records the phone has not seen.
            do {
                try journal.begin(epoch: grant.epoch)
            } catch {
                rejectGrant("undrained prior loan must drain first", notifyPhone: true)
                return
            }
        }

        // The high-water only rises, so a spent epoch is never reused; saved before the pod is touched.
        updateState {
            $0.epoch = grant.epoch
            $0.highWaterEpoch = max($0.highWaterEpoch, grant.epoch)
        }
        phoneSupportsInterimHandback = grant.supportsInterimHandback ?? false
        phoneSupportsOverrideRecords = grant.supportsOverrideRecords ?? false
        handbackRequested = false
        finalOfferSent = false

        // Timed from the grant, so the ladder measures the pod, not the phone.
        attemptStartedAt = self.now()
        withdrawSeizeOffer(reason: "a grant was accepted")
        // Force-unwrapped only because the completeness check above has already returned on nil.
        // Everything a resume needs, including the capability flags, saved with the phase.
        updateState {
            $0.phase = .takingOver
            $0.grantedSettings = .init(therapySettingsRaw: grant.therapySettingsRaw,
                                       supplementRaw: grant.therapySettingsSupplementRaw,
                                       supportsInterimHandback: grant.supportsInterimHandback ?? false,
                                       supportsOverrideRecords: grant.supportsOverrideRecords ?? false,
                                       glucoseAlertSettings: grant.glucoseAlertSettings,
                                       settingsHistory: grant.settingsHistory)
        }
        loopManager.settings = decodedSettings!
        loopManager.settingsProvider.history = grant.settingsHistory
        Task { @MainActor [loopManager] in loopManager.configureGlucoseAlerts(from: grant.glucoseAlertSettings, startingLoan: true) }
        WatchAlertPresenter.logAuthorization("loan start, epoch \(grant.epoch)")

        // The phone's history, else none: a kept event the phone never saw could overlap one it
        // re-sends, which LoopKit traps on.
        loopManager.adoptOverrideHistory(grant.overrideHistory ?? [])
        if let raw = grant.activeOverrideRaw {
            if let plist = (try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil)) as? TemporaryScheduleOverride.RawValue,
               let override = TemporaryScheduleOverride(rawValue: plist) {
                loopManager.scheduleOverride = override
            } else {
                // Undecodable override: say so, since this loan doses unscaled.
                SportLog.event("override", "grant carried an override the watch could NOT decode — this loan doses UNSCALED; re-tap the preset on the wrist")
            }
        }

        // Not part of LoopSettings; without them the two devices predict and dose differently.
        loopManager.setAlgorithmExperiments(integralRetrospectiveCorrection: grant.integralRetrospectiveCorrectionEnabled ?? false,
                                            glucoseBasedApplicationFactor: grant.glucoseBasedApplicationFactorEnabled ?? false)

        // The loan inherits the phone's loop mode; an old phone defaults to open loop.
        loopManager.setClosedLoopEnabled(grant.phoneClosedLoopEnabled ?? false,
                                         reason: grant.phoneClosedLoopEnabled == nil
                                            ? "(older phone sent no loop mode — defaulting open)"
                                            : "inherited from the phone at grant")

        // Loop recency belongs to the system, so it carries across.
        if let phoneLoop = grant.lastLoopCompleted {
            loopManager.seedLastLoopCompleted(phoneLoop, source: "phone at grant")
        }

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

            // Effective values: an override rescales basal, ISF and carb ratio too.
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

        // Built through the registry from the phone's export and this watch's saved local state,
        // from which the kit attaches its own handle for the pump if it has one. A pump that can be
        // loaned has control and an odometer.
        SportLog.event("loan", "pump manager: building from the phone's configuration")
        guard let configuration = grant.sharedPumpConfiguration,
              let manager = watchPumpManager(adopting: configuration, localState: pumpLocalState(for: configuration)),
              let control = manager as? ExclusiveDeviceControl, manager is PumpDeliveryOdometer else {
            teardownPump()
            returnToRestingPhase()
            lastIdleNote = NSLocalizedString("Couldn't build the pod driver from the iPhone's details. Try again.", comment: "Glance: pump snapshot rejected")
            SportLog.event("loan", "grant FAILED — could not build the pump from the phone's configuration")
            sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "pump configuration rejected")))
            return
        }
        SportLog.event("loan", "pump manager: built (\(configuration.managerIdentifier))")

        manager.pumpManagerDelegate = self
        manager.delegateQueue = queue
        pumpManager = manager
        pumpStateStore.wrappedValue = manager.watchRawValue
        savePumpLocalState(of: manager)

        // The export's header opens the ledger's window at the copy's reading (on a phoneless start it
        // can be half an hour old); the takeover read, like every pump report, closes it.
        updateState { $0.ledgerLast = configuration.deliveredUnits.map { (units: $0, at: configuration.asOf) } }
        guard ingestGrantHistory(grant) else {
            teardownPump()
            returnToRestingPhase()
            lastIdleNote = NSLocalizedString("Couldn't load the insulin history from the iPhone. Try again.", comment: "Glance: insulin book seed failed")
            SportLog.event("loan", "grant FAILED — the insulin book could not be seeded from the phone's history")
            sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "insulin book seed failed")))
            return
        }

        // A pump this watch has never met must be found first, which needs the screen on.
        let discover = watchTakeControlNeedsSearch(adopting: configuration, localState: pumpLocalState(for: configuration))
        takeoverFirstContact = discover
        takeoverPodReached = false
        takeoverNudges = 0
        // Only a first contact needs the screen, so only it asks for the wrist and taps it.
        if discover {
            SportLog.event("loan", "takeover: FIRST CONTACT with this pod — finding it needs the watch screen on; the glance asks for the wrist up")
            for delay in [8.0, 30.0] {
                schedule(after: delay, label: "takeover-nudge") { [weak self] in
                    guard let self = self, self.phase == .takingOver, self.epoch == grant.epoch,
                          Self.shouldNudgeTakeover(podReached: self.takeoverPodReached, appActive: self.isWatchAppActive(),
                                                   nudgesSoFar: self.takeoverNudges) else { return }
                    self.takeoverNudges += 1
                    self.playTakeoverNudge()
                    SportLog.event("loan", String(format: "takeover: pod not reached after %.0fs with the screen off — tapped the wrist", delay))
                    self.notifyUI()
                }
            }
        }
        control.takeControl()
        SportLog.event("loan", "pump adopted — \(discover ? "search armed" : "own handle — the first read dials")")

        SportLog.event("loan", String(format: "takeover ladder start — lease %+.0fs, epoch %d%@",
                                      grant.expiresAt.timeIntervalSince(now()), grant.epoch,
                                      seizeMarkerActive ? " [seize]" : ""))
        queue.async { [weak self] in self?.attemptTakeoverRead(manager: manager, grant: grant, attempt: 0) }
    }

    /// Leaving the takeover cancels the readiness-driven retry and the backstop.
    func setTakeoverSessionListener(_ armed: Bool) {
        guard !armed else { return }
        takeoverBackstop?.cancel()
        takeoverBackstop = nil
        takeoverRetryAction = nil
    }

    /// The pump's readiness drives the ladder (`CBPeripheral.state` is unreliable here); the
    /// backstop covers no event at all. On `queue`.
    func pumpControlDidBecomeReady() {
        guard phase == .takingOver else { return }
        // The pod has been reached: whatever is left of the takeover works with the wrist down.
        if !takeoverPodReached {
            takeoverPodReached = true
            if takeoverFirstContact { notifyUI() }
        }
        guard let action = takeoverRetryAction else { return }
        SportLog.event("loan", "takeover: pump control READY (kit event) — reading now instead of waiting for the backstop")
        takeoverRetryAction = nil
        takeoverBackstop?.cancel()
        takeoverBackstop = nil
        // Let the session finish coming up.
        schedule(after: 0.25, label: "session-event-settle") { action() }
    }

    /// The takeover's one save: odometer, `.active` and a seized loan's reunion token together.
    /// The token is persisted only here: an aborted activation never touched the pod.
    func recordTakeoverActive(delivered: Double, at: Date?) {
        let token = pendingSeizeToken
        pendingSeizeToken = nil
        updateState {
            $0.deliveredAtTakeover = delivered
            $0.deliveredAtTakeoverAt = at
            $0.phase = .active
            if let token { $0.seizeToken = token }
        }
        if let token {
            SportLog.event("seize", "seized loan ACTIVE — reunion token …\(String(token.uuidString.suffix(8))) persisted for the offer echo [seize]")
        }
    }

    /// Reads pod status until it answers: again when the pump reports ready, or after 8 s if no
    /// report comes (a read can fail on a link already up). The lease is the only deadline; it is
    /// re-checked every iteration and expiry outranks a good status.
    func attemptTakeoverRead(manager: PumpManager, grant: LoanGrant, attempt: Int, driver: String = "initial") {
        let control = manager as? ExclusiveDeviceControl
        let odometer = manager as? PumpDeliveryOdometer
        let refresh: (@escaping (Bool) -> Void) -> Void = { completion in
            guard let odometer else { return completion(false) }
            Task { completion(await odometer.refreshDeliveredUnits()) }
        }
        refresh { [weak self] success in
            guard let self = self else { return }
            self.queue.async {
                // Superseded while the read was out; nothing doses on a stale epoch.
                guard self.phase == .takingOver, self.epoch == grant.epoch else {
                    SportLog.event("loan", "TAKEOVER SUPERSEDED — epoch \(grant.epoch) abandoned mid-ladder (now phase \(self.phase.rawValue), epoch \(self.epoch.map(String.init) ?? "nil"))")
                    return
                }

                guard self.now() < grant.expiresAt else {
                    self.teardownPump()
                    self.returnToRestingPhase()

                    // A silent pod versus a wedged watch Bluetooth stack.
                    let wedged = control?.hostRadioNeedsReset ?? false
                    if wedged {
                        self.lastIdleNote = NSLocalizedString("The pod didn't answer. Turn watch Bluetooth off and on, then try again.", comment: "Glance: takeover failed with the BLE-wedge signature")
                    } else {
                        self.lastIdleNote = NSLocalizedString("The pod didn't answer in time. Your iPhone still has the pod. Tap Start to try again.", comment: "Glance: grant lease expired mid-takeover")
                    }
                    SportLog.event("loan", "TAKEOVER ABORTED — grant lease expired mid-takeover after \(attempt + 1) read(s), epoch \(grant.epoch), wedgeSignature=\(wedged)\(self.seizeMarkerActive ? " [seize]" : "")")
                    self.sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "grant expired mid-takeover")))
                    return
                }
                if success, let odometer, let reading = odometer.deliveredUnits {
                    let delivered = reading.units
                    // The base for every later audit of this loan.
                    self.revokeCapturedDelivered = nil
                    self.revokeCapturedDeliveredAt = nil
                    self.recordTakeoverActive(delivered: delivered, at: reading.at)
                    self.onLoanActiveChanged?(true)
                    let takeoverSecs = self.attemptStartedAt.map { self.now().timeIntervalSince($0) } ?? -1
                    SportLog.event("loan", String(format: "ACTIVE — epoch %d, pod taken after %d read(s) in %.1fs [takeover-timing], odometer %.2f U, final read driver=%@ · %@",
                                                  grant.epoch, attempt + 1, takeoverSecs, delivered, driver, RuntimeStateLog.snapshot()))
                    self.sendMessage(.takeoverComplete(TakeoverComplete(epoch: grant.epoch, firstPodStatus: self.currentPodStatus())))

                    // The read's own report closed the ledger's window from the copy's reading and booked
                    // what it could not explain, so the loop can have the pump now; a full `loop()` so
                    // the first program is journaled.
                    self.loopManager.pumpManager = manager
                    self.loopManager.loop()
                } else {
                    if attempt == 0 {
                        SportLog.event("loan", "connecting to pod… (BLE session establishing; reading again when the pump reports ready, or after 8 s, until the grant lease runs out)")
                    }
                    let readElapsed = self.attemptStartedAt.map { self.now().timeIntervalSince($0) } ?? -1
                    SportLog.event("loan", String(format: "takeover read %d driver=%@ (+%.1fs) — pump link %@",
                                                  attempt + 1, driver, readElapsed,
                                                  control.map { $0.isControlReady ? "ready" : "not ready" } ?? "no control"))

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
                    // Two objects: a cancelled work item performs nothing.
                    self.takeoverRetryAction = { fireRetry("event") }
                    let backstop = DispatchWorkItem { fireRetry("backstop") }
                    self.takeoverBackstop = backstop
                    self.schedule(after: 8, label: "takeover-read", execute: backstop)
                }
            }
        }
    }
}
