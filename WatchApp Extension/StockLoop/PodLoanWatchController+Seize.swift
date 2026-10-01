//
//  PodLoanWatchController+Seize.swift
//  WatchApp Extension
//
//  Starting a loan without the phone, and what happens when the phone comes back.
//
//  While the phone owns the pod it keeps this watch supplied with a DORMANT grant — a whole
//  session's materials, refreshed as the books and the settings change, stored and never used.
//  When a loan request times out, that credential becomes an offer to start anyway; confirming it
//  activates the stored grant through the ordinary grant path under a freshly minted lease.
//
//  The phone's return does not end the loan. It raises a PROMPT, because reachable is not the
//  same as present — a phone can be lost in the house and still on WiFi — so the hand-back stays
//  the user's deliberate act.
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

    /// Activate the stored credential the user just confirmed.
    ///
    /// The epoch is forced clear of every epoch this watch has ever seen — its own, the journal's,
    /// the high-water mark and the last revoke — and never below the credential's own. Folding
    /// onto an epoch already spent would let a parked drain's queued final offer close the LIVE
    /// loan on the phone.
    ///
    /// The lease is minted here because a dormant credential arrives already expired by contract;
    /// it bounds this handshake only, and the credential's own age is the user's business.
    func confirmSeize() {
        queue.async {
            // Only from a resting phase, and the stored credential must still be the one the
            // offer was raised for: a refresh in between mints a new token, so confirming against
            // the old one is a stale tap on a screen that has moved on.
            guard self.phase == .idle || self.phase == .recoveredDrain, let offer = self.seizeOffer,
                  let dormant = self.storedDormantGrant(), dormant.seizeToken == offer.token else {
                SportLog.event("seize", "confirm arrived with no live offer — ignored [seize]")
                return
            }
            self.seizeOffer = nil

            let newEpoch = max(dormant.grant.epoch,
                               (self.epoch ?? 0) + 1,
                               (self.journal.activeEpoch ?? 0) + 1,
                               self.defaults.integer(forKey: Keys.highWaterEpoch) + 1,
                               (self.lastRevokedEpoch ?? 0) + 1)

            let leaseUntil = self.now().addingTimeInterval(Self.seizeActivationLease)
            self.pendingSeizeToken = dormant.seizeToken

            // Anything still queued would be delivered at reunion and grant an epoch over this
            // loan; drop it before the pod changes hands.
            self.cancelStaleQueuedRequests(context: "seize confirmed")
            SportLog.event("seize", String(format: "SEIZE confirmed — activating dormant grant (issued %@, epoch %d→%d, lease +%.0fs, token …%@) [seize]",
                                           DateFormatter.localizedString(from: dormant.issuedAt, dateStyle: .short, timeStyle: .short),
                                           dormant.grant.epoch, newEpoch, Self.seizeActivationLease,
                                           String(dormant.seizeToken.uuidString.suffix(8))))
            self.phase = .requested
            self.attemptStartedAt = self.now()
            // Activation runs through the ordinary grant path — one code path for granted and
            // seized loans, so the two cannot drift — with the in-flight flag raised across it.
            // `handleGrant` is synchronous up to the ladder, so the flag is cleared on the way out.
            self.seizeActivationInFlight = true
            self.handleGrant(dormant.grant.withEpoch(newEpoch, leaseUntil: leaseUntil))
            self.seizeActivationInFlight = false
        }
    }

    /// The user declined the offline start. The credential stays stored for the next attempt.
    func dismissSeize() {
        queue.async {
            guard self.seizeOffer != nil else { return }
            self.seizeOffer = nil
            self.lastIdleNote = NSLocalizedString("Offline start cancelled.", comment: "Glance note after dismissing a seize offer")
            SportLog.event("seize", "seize offer DISMISSED [seize]")
            self.notifyUI()
        }
    }

    /// The phone becoming reachable during a SEIZED loan raises a prompt, never an automatic
    /// hand-back.
    ///
    /// Debounced by thirty seconds and re-checked when it fires, so a flicker of reachability
    /// cannot raise one; at most one prompt per reachability transition, and none at all once the
    /// user has already asked to End.
    func noteReachabilityChanged(_ reachable: Bool) {
        queue.async {
            guard reachable else { return }
            guard self.phase == .active,
                  self.defaults.string(forKey: DormantKeys.activeToken) != nil,
                  !self.handbackRequested, !self.reunionPromptActive else { return }
            // A stored default with no UI, for a session where the prompt is not wanted.
            guard !self.defaults.bool(forKey: Self.seizeAutoHandbackDisabledKey) else {
                SportLog.event("seize", "phone returned during a seized loan — reunion prompt DISABLED by kill switch [seize]")
                return
            }
            guard !self.seizeReunionDebounceArmed else { return }
            self.seizeReunionDebounceArmed = true
            SportLog.event("seize", "phone REACHABLE during a seized loan — reunion prompt in 30s unless it flickers away [seize]")
            self.schedule(after: 30, label: "seize-reunion-debounce") { [weak self] in
                guard let self = self else { return }
                self.seizeReunionDebounceArmed = false
                guard self.phase == .active,
                      self.defaults.string(forKey: DormantKeys.activeToken) != nil,
                      !self.handbackRequested, !self.reunionPromptActive else { return }
                guard self.isPhoneReachable() else {
                    SportLog.event("seize", "phone flickered away before the reunion debounce — seized loan continues [seize]")
                    return
                }
                self.reunionPromptActive = true
                SportLog.event("seize", "phone is back — REUNION PROMPT raised (R40(f): the hand-back stays the user's deliberate act) [seize]")
                self.notifyUI()
                self.issueReunionPromptAlert()

                self.sendHoldsPodStatusReport(reason: "reunion prompt raised")
            }
        }
    }

    /// Tell the phone outright that this watch holds the pod.
    ///
    /// Sent at the reunion prompt and at Keep, and as the answer to any stale grant, revoke or
    /// status query while a newer loan is live. The phone's standing-aside otherwise waits on
    /// dose-stream evidence that only appears when the loop happens to enact something, and its
    /// silence reads to the phone as a dead watch.
    func sendHoldsPodStatusReport(reason: String) {
        guard phase == .active, let current = epoch else { return }
        sendMessage(.statusReport(StatusReport(
            epoch: current,
            mode: currentMode(),
            lastDirectGlucoseAge: loopManager.latestGlucoseAge,
            lastEventSeq: journal.lastEventSeq,
            podFault: pumpManager?.podLoanFaultDescription,
            holdsPod: true,
            knowsGrant: true)))
        SportLog.event("seize", "statusReport sent — holdsPod e\(current) (\(reason)) [seize]")
    }

    /// The reunion prompt's Hand Back. From here on it is an ordinary hand-back.
    func confirmReunionHandback() {
        queue.async {
            guard self.reunionPromptActive, self.phase == .active else { return }
            self.reunionPromptActive = false
            SportLog.event("seize", "reunion prompt: HAND BACK chosen — normal hand-back begins [seize]")
            self.notifyUI()
            self.beginHandback()
        }
    }

    /// The reunion prompt's Keep. The loan continues, and the phone is told again that this
    /// watch holds the pod so it does not start reasoning from silence.
    func dismissReunionPrompt() {
        queue.async {
            guard self.reunionPromptActive else { return }
            self.reunionPromptActive = false
            SportLog.event("seize", "reunion prompt: KEEP chosen — seized loan continues [seize]")
            self.notifyUI()

            self.sendHoldsPodStatusReport(reason: "Keep chosen")
        }
    }

    /// The prompt's alert half, so the phone's return is visible without the glance on screen.
    func issueReunionPromptAlert() {
        let title = NSLocalizedString("iPhone Is Back", comment: "Watch alert title when the phone returns during a seized loan")
        let body = NSLocalizedString("Sport Mode is still running without it. Open the app to hand the pod back, or keep going.", comment: "Watch alert body when the phone returns during a seized loan")
        Task { @MainActor in
            loopManager.issueAlert(Alert(
                identifier: Alert.Identifier(managerIdentifier: "PodLoan", alertIdentifier: "seizeReunionPrompt"),
                foregroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                backgroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                trigger: .immediate))
        }
    }

    /// Store the refreshed credential. Whole-book and latest-only: each one carries a complete
    /// session's materials, so a new one simply replaces the old.
    func handleDormantGrant(_ dormant: DormantGrant) {
        guard let data = try? LoanProtocol.encoder.encode(dormant) else {
            SportLog.event("seize", "dormant grant arrived but failed to re-encode — NOT stored [seize]")
            return
        }
        defaults.set(data, forKey: DormantKeys.envelope)
        SportLog.event("seize", String(format: "dormant grant refreshed — issued %@, %d dose record(s), token …%@ [seize]",
                                       DateFormatter.localizedString(from: dormant.issuedAt, dateStyle: .none, timeStyle: .medium),
                                       dormant.grant.doseHistory.count,
                                       String(dormant.seizeToken.uuidString.suffix(8))))
    }

    /// The stored credential, or nil if none has arrived or it no longer decodes. A credential
    /// that will not decode is simply absent — there is no partial seize.
    func storedDormantGrant() -> DormantGrant? {
        guard let data = defaults.data(forKey: DormantKeys.envelope) else { return nil }
        return try? LoanProtocol.decoder.decode(DormantGrant.self, from: data)
    }

    /// How much of the pod's delivery since the copy was taken the copy cannot account for.
    ///
    /// Rate records go through the shared reconciler; boluses are handled here instead, so one
    /// still delivering at `now` is pro-rated by the elapsed fraction of its window rather than
    /// counted whole. The remainder is quantized to milli-units before the band comparison, so the
    /// boundary turns on the pulse grid and never on floating-point dust.
    ///
    /// Returns zero unless the excess clears the band: a shortfall means the copy claims insulin
    /// the pod never delivered, which cannot add insulin on board and is not this function's
    /// business.
    static func insulinTheCopyCannotExplain(copyTotal: Double, copyAt: Date, podTotal: Double, now: Date,
                                            records: [LoanDoseRecord], schedule: BasalRateSchedule?) -> Double {
        guard now > copyAt, podTotal >= copyTotal else { return 0 }
        // The reconciler works in events, so the copy's rate records are wrapped in synthetic
        // ones. Only their ORDER matters here — these seqs are local and never leave this call.
        let rateEvents = records.filter { $0.kind != .bolus }.enumerated().map {
            LoanEvent(id: UUID(), seq: $0.offset + 1, provenance: .confirmed, record: $0.element, loggedAt: now)
        }
        var expected = LoanReconciler.expectedInsulin(events: rateEvents, schedule: schedule, from: copyAt, to: now)
        for bolus in records where bolus.kind == .bolus {
            guard let amount = bolus.amount, amount > 0 else { continue }
            let end = bolus.endDate ?? bolus.startDate
            if end > bolus.startDate {
                let overlap = min(end, now).timeIntervalSince(max(bolus.startDate, copyAt))
                if overlap > 0 { expected += amount * overlap / end.timeIntervalSince(bolus.startDate) }
            } else if bolus.startDate >= copyAt, bolus.startDate <= now {
                expected += amount
            }
        }
        let unexplained = ((podTotal - copyTotal - expected) * 1000).rounded() / 1000
        return unexplained > unexplainedInsulinBand ? unexplained : 0
    }

    /// Book insulin the phone's copy cannot explain as a bolus delivered NOW, blocking, before
    /// the first cycle of the loan runs.
    ///
    /// The copy can be half an hour old on a phoneless start, and anything the phone delivered
    /// after it was taken is in nobody's book — the watch would see glucose rising, no insulin on
    /// board, and dose on top of it. SEEDED rather than journalled, because the phone already has
    /// these units recorded and journalling them would book them there a second time. Stamped now,
    /// so nothing has decayed: insulin on board errs high and the dosing errs low.
    ///
    /// Unlike the phone's equivalent verdict this does not open the loop — the user has just asked
    /// this watch to dose.
    func bookInsulinTheCopyCannotExplain(podTotal: Double, epoch: Int) {
        defer { takeoverCopyTotal = nil; takeoverCopyRecords = [] }
        guard let copy = takeoverCopyTotal else {
            SportLog.event("loan", "takeover book check SKIPPED — the copy carried no pod total to compare against")
            return
        }
        let at = self.now()
        let unexplained = Self.insulinTheCopyCannotExplain(copyTotal: copy.units, copyAt: copy.asOf, podTotal: podTotal, now: at,
                                                           records: takeoverCopyRecords,
                                                           schedule: loopManager.settings.basalRateSchedule)
        let age = at.timeIntervalSince(copy.asOf) / 60
        guard unexplained > 0 else {
            SportLog.event("loan", String(format: "takeover book check CLEAN — pod total %.2f → %.2f U over %.1f min is explained by the copy's records and the schedule",
                                          copy.units, podTotal, age))
            return
        }
        let entry = DoseEntry(type: .bolus, startDate: at, endDate: at, value: unexplained, unit: .units,
                              decisionId: nil, deliveredUnits: unexplained,
                              syncIdentifier: "PODLOAN-WATCHGAP-e\(epoch)",
                              insulinType: pumpManager?.status.insulinType)
        // Blocking: the caller goes on to run the loan's first cycle, which must not see a book
        // that is still missing these units.
        let gate = DispatchSemaphore(value: 0)
        var failure: Error?
        let loopManager = self.loopManager
        Task {
            do { try await loopManager.seedInsulinHistory([entry]) } catch { failure = error }
            gate.signal()
        }
        gate.wait()
        if let failure {
            SportLog.event("loan", String(format: "** takeover book check: %.2f U UNEXPLAINED and the booking FAILED — %@ **", unexplained, String(describing: failure)))
            return
        }
        SportLog.event("loan", String(format: "** takeover book check: pod total %.2f → %.2f U over %.1f min; %.2f U the copy cannot explain — BOOKED as a bolus now (insulin on board errs high, dosing errs low) **",
                                      copy.units, podTotal, age, unexplained))
        startNote = (at, String(format: NSLocalizedString("%.2f U the watch had no record of — counted as insulin on board", comment: "Glance: unexplained insulin booked at takeover (1: units)"), unexplained))
    }

    enum DormantKeys {
        /// The stored credential. One at a time — a refresh replaces it.
        static let envelope = "PodLoanWatchController.dormantGrant"

        /// The reunion token of a seize that is actually running. Persisted so a relaunch
        /// mid-seized-loan keeps echoing it on every offer — without it the phone cannot
        /// retro-acknowledge a loan it never granted — and cleared only when the loan CLOSES.
        static let activeToken = "PodLoanWatchController.activeSeizeToken"
    }

    /// Whether this loan is a seize, for the log tags: true from the moment an activation begins
    /// until the loan closes.
    var seizeMarkerActive: Bool {
        pendingSeizeToken != nil || defaults.string(forKey: DormantKeys.activeToken) != nil
    }

    /// The handshake's budget, not the credential's — long enough for the takeover ladder with
    /// slack. A dormant credential's own age is shown in the confirmation and never enforced.
    static let seizeActivationLease: TimeInterval = 5 * 60

    static let seizeAutoHandbackDisabledKey = "PodLoanWatchController.seizeAutoHandbackDisabled"

    /// Matches the phone's reconciliation band. Below it the difference between the copy and the
    /// pod is pulse quantization, not insulin anybody missed.
    static let unexplainedInsulinBand = 0.20
}
