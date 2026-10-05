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

    /// Seeds finished doses from the grant; a failed seed refuses the takeover. A dose still
    /// delivering arrives via the pod state as a mutable dose. The takeover waits for it with the pod
    /// not yet taken, so nothing doses meanwhile, and re-checks the loan after.
    func ingestGrantHistory(_ grant: LoanGrant) async -> Bool {
        let seedReconciliation = self.now()
        let (entries, liveDoses) = grant.seedDoseEntries(finishedBy: seedReconciliation)
        let epoch = grant.epoch

        // Reset first, so one physical dose stays one row.
        await loopManager.resetInsulinBook(reason: "the grant for loan \(epoch)")
        do {
            try await loopManager.seedInsulinHistory(entries)
        } catch {
            SportLog.event("loan", "could not seed the insulin history from the grant: \(String(describing: error))")
            return false
        }
        SportLog.event("loan", "insulin history seeded from the grant: \(entries.count) finished dose(s), \(liveDoses.count) still delivering")

        // The display run, so the glance shows the inherited insulin from takeover; its IOB is
        // also logged to compare with the phone's.
        loopManager.updateDisplayState { state in
            guard let iob = state.activeInsulin?.value else { return }
            SportLog.event("loan", String(format: "insulin on board at takeover %.2f U", iob))
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

        loopManager.carbStore.setSyncCarbObjects(objects) { [weak self] error in
            if let error = error {
                self?.log.error("Grant carb replace failed: %{public}@", String(describing: error))
                return
            }

            // Logs residual, missing and duplicate entries; the loan proceeds either way.
            guard let self = self else { return }
            let expectedIDs = Set(carbs.compactMap { $0.syncIdentifier })
            let readFrom = (carbs.map(\.startDate).min() ?? self.now()).addingTimeInterval(-3600)
            self.loopManager.carbStore.getCarbEntries(start: readFrom) { result in
                switch result {
                case .failure(let error):
                    SportLog.event("cob-diff", "carbs replaced from the grant, but could not be read back: \(error)")
                case .success(let stored):
                    let storedIDs = Set(stored.compactMap { $0.syncIdentifier })
                    let residual = storedIDs.subtracting(expectedIDs)
                    let missing = expectedIDs.subtracting(storedIDs)
                    let dupes = stored.count - storedIDs.count
                    if residual.isEmpty && missing.isEmpty && dupes == 0 {
                        SportLog.event("cob-diff", String(format: "carbs replaced from the grant: %d entries, %.0f g", expectedIDs.count, seededGrams))
                    } else {
                        SportLog.event("cob-diff", "carbs replaced from the grant, but \(residual.count) left over, \(missing.count) missing and \(dupes) duplicated")
                    }
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

                SportLog.event("loan", "seeded \(stored.count) glucose sample(s) from the grant")
                // Rerun the display now the phone's glucose is in: the takeover's first display
                // run may have found none.
                self.loopManager.updateDisplayState()
            } catch {
                self.log.error("Grant glucose ingest failed: %{public}@", String(describing: error))
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
        DispatchQueue.main.async {
            guard self.phase == .idle || self.phase == .recoveredDrain else {
                SportLog.event("loan", "ignored a Start in phase \(self.phase.rawValue)")
                return
            }
            // Allowed over a parked drain: its records keep resending under their own epoch.
            if self.phase == .recoveredDrain {
                SportLog.event("loan", "starting with \(self.journal.unackedEvents().count) record(s) of an earlier loan still going to the phone")
            }
            self.startCancelled = false
            self.phase = .requested
            self.attemptStartedAt = self.now()
            self.lastIdleNote = nil
            self.withdrawSeizeOffer(reason: "a new Start request went out")

            SportLog.event("loan", "loan requested from the phone, build \(watchBuild)")
            let known = max(self.epoch ?? 0, self.journal.activeEpoch ?? 0, self.persisted.highWaterEpoch, self.lastRevokedEpoch ?? 0)
            self.sendMessage(.request(LoanRequest(watchBuild: watchBuild, sentAt: self.now(), knownEpoch: known)))

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
            let situation = LoanControl.Situation(device: .watch, trigger: .startTapped, watchHasStoredCopy: dormant != nil,
                                                  watchReadsCGM: self.loopManager.cgmManager != nil)
            guard case .query(_, let onSilence) = LoanControl.decide(situation) else { return }
            if case .prompt(.startWithoutPhone) = LoanControl.afterQuery(.silence, onSilence: onSilence), let dormant {
                self.seizeOffer = (issuedAt: dormant.issuedAt, token: dormant.seizeToken)
                self.lastIdleNote = nil
                SportLog.event("seize", String(format: "no answer from the phone; offering an offline start from the grant stored %@",
                                               DateFormatter.localizedString(from: dormant.issuedAt, dateStyle: .short, timeStyle: .short)))
                return
            }

            if case .tell(.noResponseFromPhoneAndNoCGM) = LoanControl.afterQuery(.silence, onSilence: onSilence) {
                self.lastIdleNote = NSLocalizedString("No answer from iPhone. The watch isn't reading the CGM, so Sport Mode can't start without the iPhone.", comment: "Glance: loan request timed out and the watch has no CGM of its own")
                SportLog.event("loan", "no answer from the phone in \(Int(timeout)) s and the watch reads no CGM; no offline start offered")
                return
            }
            self.lastIdleNote = NSLocalizedString("No answer from iPhone. Open Loop on the iPhone and try again.", comment: "Glance: loan request timed out")
            SportLog.event("loan", "no answer from the phone in \(Int(timeout)) s")
        }
        requestTimeoutWork = work
        schedule(after: timeout, label: "request-timeout", execute: work)
    }

    /// The offer answers one unanswered request; a later grant or Start makes it stale. On `queue`.
    private func withdrawSeizeOffer(reason: String) {
        guard seizeOffer != nil else { return }
        seizeOffer = nil
        SportLog.event("seize", "offline start offer withdrawn: \(reason)")
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
        }
        return decodedSettings
    }

    /// Builds the whole loan from a grant or refuses it, leaving Start working. Nothing touches
    /// the journal, epoch or pod until every check has passed.
    func handleGrant(_ grant: LoanGrant) {
        SportLog.event("loan", "grant received for loan \(grant.epoch)")

        // Any other grant retires a pending seize token.
        if !seizeActivationInFlight { pendingSeizeToken = nil }

        guard phase == .idle || phase == .requested || phase == .recoveredDrain else {
            SportLog.event("loan", "grant ignored in phase \(phase.rawValue)")

            // Answer a duplicate with what we hold; silence reads as "no watch".
            if phase == .active, (epoch ?? Int.min) >= grant.epoch {
                sendHoldsPodStatusReport(reason: "a stale grant for loan \(grant.epoch)")
            }
            return
        }
        // After the phase check and before any rejection, each of which returns to rest.
        requestTimeoutWork?.cancel()

        // `notifyPhone` is false when merely declining a stale or duplicate grant.
        func rejectGrant(_ reason: String, notifyPhone: Bool) {
            SportLog.event("loan", "grant rejected: \(reason)")
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
            SportLog.event("loan", "grant refused: therapy settings incomplete, \(missing) missing")
            sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "therapy settings incomplete: \(missing)")))
            return
        }

        // The phone's upload services, staged until uploads start at ACTIVE.
        LoanRemoteUploads.shared.stage(services: grant.sharedServiceConfigurations, phoneCGMUploadsGlucose: grant.phoneCGMUploadsGlucose)

        // A seize over a parked drain folds the old events into this epoch, keeping their identities.
        if seizeActivationInFlight, journal.hasUndrainedEvents {
            let carried = journal.adoptEpoch(grant.epoch)
            SportLog.event("seize", "carried \(carried) record(s) of the earlier loan into loan \(grant.epoch)")

            // A fold persists the token now: real records already exist.
            if let token = pendingSeizeToken {
                updateState { $0.seizeToken = token }
                pendingSeizeToken = nil
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
        handbackRequested = false
        finalOfferSent = false
        uploadsConfirmed = nil

        // Timed from the grant, so the ladder measures the pod, not the phone.
        attemptStartedAt = self.now()
        withdrawSeizeOffer(reason: "a grant was accepted")
        // Force-unwrapped only because the completeness check above has already returned on nil.
        // Everything a resume needs, saved with the phase.
        updateState {
            $0.phase = .takingOver
            $0.grantedSettings = .init(therapySettingsRaw: grant.therapySettingsRaw,
                                       supplementRaw: grant.therapySettingsSupplementRaw,
                                       glucoseAlertSettings: grant.glucoseAlertSettings,
                                       settingsHistory: grant.settingsHistory,
                                       serviceConfigurations: grant.serviceConfigurations,
                                       phoneCGMUploadsGlucose: grant.phoneCGMUploadsGlucose)
        }
        loopManager.settings = decodedSettings!
        loopManager.settingsProvider.history = grant.settingsHistory
        loopManager.configureGlucoseAlerts(from: grant.glucoseAlertSettings, startingLoan: true)
        WatchAlertPresenter.logAuthorization("the start of loan \(grant.epoch)")

        // The phone's history, else none: a kept event the phone never saw could overlap one it
        // re-sends, which LoopKit traps on.
        loopManager.adoptOverrideHistory(grant.overrideHistory ?? [])
        if let raw = grant.activeOverrideRaw {
            if let plist = (try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil)) as? TemporaryScheduleOverride.RawValue,
               let override = TemporaryScheduleOverride(rawValue: plist) {
                loopManager.scheduleOverride = override
            } else {
                // Undecodable override: say so, since this loan doses unscaled.
                SportLog.event("override", "could not read the override in the grant; this loan doses without it")
            }
        }

        // Not part of LoopSettings; without them the two devices predict and dose differently.
        loopManager.setAlgorithmExperiments(integralRetrospectiveCorrection: grant.integralRetrospectiveCorrectionEnabled ?? false,
                                            glucoseBasedApplicationFactor: grant.glucoseBasedApplicationFactorEnabled ?? false,
                                            guardAndRunway: grant.guardAndRunwayEnabled ?? false,
                                            volatilityBaseline: grant.volatilityBaseline)

        // The loan inherits the phone's loop mode; an old phone defaults to open loop.
        loopManager.setClosedLoopEnabled(grant.phoneClosedLoopEnabled ?? false,
                                         reason: grant.phoneClosedLoopEnabled == nil
                                            ? "by default, as the phone sent no loop mode"
                                            : "as the phone had it at the grant")

        // Loop recency belongs to the system, so it carries across.
        if let phoneLoop = grant.lastLoopCompleted {
            loopManager.seedLastLoopCompleted(phoneLoop, source: "the phone at the grant")
        }

        // Built through the registry from the phone's export and this watch's saved local state,
        // from which the kit attaches its own handle for the pump if it has one. A pump that can be
        // loaned has control and an odometer.
        guard let configuration = grant.sharedPumpConfiguration,
              let manager = watchPumpManager(adopting: configuration, localState: pumpLocalState(for: configuration)),
              let control = manager as? ExclusiveDeviceControl, manager is PumpDeliveryOdometer else {
            teardownPump()
            returnToRestingPhase()
            lastIdleNote = NSLocalizedString("Couldn't build the pod driver from the iPhone's details. Try again.", comment: "Glance: pump snapshot rejected")
            SportLog.event("loan", "takeover failed: could not build the pump manager from the phone's configuration")
            sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "pump configuration rejected")))
            return
        }

        manager.pumpManagerDelegate = self
        manager.delegateQueue = .main
        pumpManager = manager
        pumpStateStore.wrappedValue = manager.watchRawValue
        savePumpLocalState(of: manager)

        // The export's header opens the ledger's window at the copy's reading (on a phoneless start it
        // can be half an hour old); the takeover read, like every pump report, closes it.
        updateState { $0.ledgerLast = configuration.deliveredUnits.map { (units: $0, at: configuration.asOf) } }
        Task { [weak self] in
            guard let self else { return }
            let seeded = await self.ingestGrantHistory(grant)
            // The loan may have moved on while the history was seeded: a revoke, a teardown, a newer grant.
            guard self.phase == .takingOver, self.epoch == grant.epoch,
                  (self.pumpManager as AnyObject?) === (manager as AnyObject) else {
                SportLog.event("loan", "takeover of loan \(grant.epoch) abandoned: the loan moved on while the insulin history was seeded")
                return
            }
            guard seeded else {
                teardownPump()
                returnToRestingPhase()
                lastIdleNote = NSLocalizedString("Couldn't load the insulin history from the iPhone. Try again.", comment: "Glance: insulin book seed failed")
                SportLog.event("loan", "takeover failed: the insulin history could not be seeded")
                sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "insulin book seed failed")))
                return
            }
            self.takeControlForTakeover(grant: grant, manager: manager, control: control, configuration: configuration)
        }
    }

    /// The takeover once the insulin book is seeded: find or dial the pod, take control, read it.
    private func takeControlForTakeover(grant: LoanGrant, manager: PumpManager, control: ExclusiveDeviceControl,
                                        configuration: SharedDeviceConfiguration) {
        // A pump this watch has never met must be found first, which needs the screen on.
        let discover = watchTakeControlNeedsSearch(adopting: configuration, localState: pumpLocalState(for: configuration))
        takeoverFirstContact = discover
        takeoverPodReached = false
        takeoverNudges = 0
        // Only a first contact needs the screen, so only it asks for the wrist and taps it.
        if discover {
            SportLog.event("loan", "first contact with this pod: the takeover needs the watch screen on")
            for delay in [8.0, 30.0] {
                schedule(after: delay, label: "takeover-nudge") { [weak self] in
                    guard let self = self, self.phase == .takingOver, self.epoch == grant.epoch,
                          Self.shouldNudgeTakeover(podReached: self.takeoverPodReached, appActive: self.isWatchAppActive(),
                                                   nudgesSoFar: self.takeoverNudges) else { return }
                    self.takeoverNudges += 1
                    self.playTakeoverNudge()
                    SportLog.event("loan", String(format: "pod not reached after %.0f s with the screen off; asked for the screen with a tap", delay))
                    self.notifyUI()
                }
            }
        }
        control.takeControl()
        DispatchQueue.main.async { [weak self] in self?.attemptTakeoverRead(manager: manager, grant: grant, attempt: 0) }
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
    }

    /// The glance note when the takeover window closes with no pod answer. After a grant the phone takes the
    /// pod back; after a start without the phone (control row 25) the phone is away, so nobody loops.
    static func takeoverExpiredNote(offlineStart: Bool) -> String {
        offlineStart
            ? NSLocalizedString("The pod didn't answer, so Sport Mode didn't start. Neither device is looping.", comment: "Glance: a start without the phone got no answer from the pod")
            : NSLocalizedString("The pod didn't answer in time. Your iPhone still has the pod. Tap Start to try again.", comment: "Glance: grant lease expired mid-takeover")
    }

    /// Reads pod status until it answers: again when the pump reports ready, or after 8 s if no
    /// report comes (a read can fail on a link already up). The lease is the only deadline; it is
    /// re-checked every iteration and expiry outranks a good status.
    func attemptTakeoverRead(manager: PumpManager, grant: LoanGrant, attempt: Int) {
        let odometer = manager as? PumpDeliveryOdometer
        let refresh: (@escaping (Bool) -> Void) -> Void = { completion in
            guard let odometer else { return completion(false) }
            Task { completion(await odometer.refreshDeliveredUnits()) }
        }
        refresh { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // Superseded while the read was out; nothing doses on a stale epoch.
                guard self.phase == .takingOver, self.epoch == grant.epoch else {
                    SportLog.event("loan", "takeover of loan \(grant.epoch) abandoned: the loan moved on during a pod read")
                    return
                }

                guard self.now() < grant.expiresAt else {
                    let offlineStart = self.pendingSeizeToken != nil
                    self.teardownPump()
                    self.returnToRestingPhase()

                    self.lastIdleNote = Self.takeoverExpiredNote(offlineStart: offlineStart)
                    SportLog.event("loan", "takeover failed: the pod did not answer before the grant expired, after \(attempt + 1) read(s)")
                    self.sendMessage(.takeoverFailed(TakeoverFailed(epoch: grant.epoch, reason: "grant expired mid-takeover")))
                    return
                }
                if success, let odometer, let reading = odometer.deliveredUnits {
                    let delivered = reading.units
                    let offlineStart = self.pendingSeizeToken != nil
                    // The base for every later audit of this loan.
                    self.revokeCapturedDelivered = nil
                    self.revokeCapturedDeliveredAt = nil
                    self.recordTakeoverActive(delivered: delivered, at: reading.at)
                    self.onLoanActiveChanged?(true)
                    let takeoverSecs = self.attemptStartedAt.map { self.now().timeIntervalSince($0) } ?? -1
                    SportLog.event("loan", String(format: "%@loan %d active: pod taken after %d read(s) in %.1f s, pump total %.2f U",
                                                  offlineStart ? "offline " : "", grant.epoch, attempt + 1, takeoverSecs, delivered))
                    self.sendMessage(.takeoverComplete(TakeoverComplete(epoch: grant.epoch, firstPodStatus: self.currentPodStatus())))

                    // The read's own report closed the ledger's window from the copy's reading and booked
                    // what it could not explain, so the loop can have the pump now; a full `loop()` so
                    // the first program is journaled.
                    self.loopManager.pumpManager = manager
                    self.loopManager.loop()
                } else {
                    let fireRetry: () -> Void = { [weak self] in
                        guard let self = self else { return }
                        self.takeoverRetryAction = nil
                        self.takeoverBackstop = nil
                        guard self.phase == .takingOver, self.epoch == grant.epoch else {
                            SportLog.event("loan", "takeover of loan \(grant.epoch) abandoned: the loan moved on between pod reads")
                            return
                        }
                        self.attemptTakeoverRead(manager: manager, grant: grant, attempt: attempt + 1)
                    }
                    // Two objects: a cancelled work item performs nothing.
                    self.takeoverRetryAction = { fireRetry() }
                    let backstop = DispatchWorkItem { fireRetry() }
                    self.takeoverBackstop = backstop
                    self.schedule(after: 8, label: "takeover-read", execute: backstop)
                }
            }
        }
    }
}
