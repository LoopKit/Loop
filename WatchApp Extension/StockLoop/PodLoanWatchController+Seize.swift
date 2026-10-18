//
//  PodLoanWatchController+Seize.swift
//  WatchApp Extension
//
//  Starting a loan without the phone from the stored dormant grant, and the reunion prompt
//  when the phone returns (a prompt, never an automatic hand-back).
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController {

    /// Activates the stored credential: an epoch clear of every one this watch has seen, and a
    /// fresh lease (the credential arrives expired).
    func confirmSeize() {
        queue.async {
            // Only from rest, and only for the credential the offer was raised for.
            guard self.phase == .idle || self.phase == .recoveredDrain, let offer = self.seizeOffer,
                  let dormant = self.storedDormantGrant(), dormant.seizeToken == offer.token else {
                SportLog.event("seize", "confirm arrived with no live offer — ignored [seize]")
                return
            }
            self.seizeOffer = nil

            // The phone is back: start the ordinary way.
            if self.isPhoneReachable() {
                SportLog.event("seize", "offline start SUPERSEDED at confirm — the phone is reachable again; sending a normal Start request [seize]")
                self.requestLoan(watchBuild: BuildDetails.default.codeIdentity)
                return
            }

            let newEpoch = max(dormant.grant.epoch,
                               (self.epoch ?? 0) + 1,
                               (self.journal.activeEpoch ?? 0) + 1,
                               self.persisted.highWaterEpoch + 1,
                               (self.lastRevokedEpoch ?? 0) + 1)

            let leaseUntil = self.now().addingTimeInterval(Self.seizeActivationLease)
            self.pendingSeizeToken = dormant.seizeToken

            // Drop queued requests before the pod changes hands.
            self.cancelStaleQueuedRequests(context: "seize confirmed")
            SportLog.event("seize", String(format: "SEIZE confirmed — activating dormant grant (issued %@, epoch %d→%d, lease +%.0fs, token …%@) [seize]",
                                           DateFormatter.localizedString(from: dormant.issuedAt, dateStyle: .short, timeStyle: .short),
                                           dormant.grant.epoch, newEpoch, Self.seizeActivationLease,
                                           String(dormant.seizeToken.uuidString.suffix(8))))
            self.phase = .requested
            self.attemptStartedAt = self.now()
            // Through the ordinary grant path, so seized and granted loans cannot drift.
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

    /// The phone returning during a seized loan: it is told at once that this watch holds the pod,
    /// so it stops dosing, and the prompt asks the user. From the watch's side reachability drops
    /// whenever the app leaves the screen, so it is not required to last.
    func noteReachabilityChanged(_ reachable: Bool) {
        queue.async {
            guard reachable else {
                // The phone went out of reach while a Start waited: offer the offline start now.
                if self.phase == .requested, let work = self.requestTimeoutWork, !work.isCancelled {
                    SportLog.event("seize", "phone went out of reach during the request — offline start offered now [seize]")
                    work.perform()
                    work.cancel()
                }
                return
            }
            guard self.phase == .active, self.persisted.seizeToken != nil,
                  !self.handbackRequested, !self.reunionPromptActive else { return }
            self.sendHoldsPodStatusReport(reason: "phone reachable")
            self.raiseReunionPrompt(because: "phone REACHABLE")
        }
    }

    /// The phone has been heard during a seized loan: ask the user, once per loan. Keep is the
    /// answer for the rest of it; End on the watch stays available. On `queue`.
    func raiseReunionPrompt(because why: String) {
        guard phase == .active, persisted.seizeToken != nil,
              !handbackRequested, !reunionPromptActive, !reunionKeepChosen else { return }
        reunionPromptActive = true
        SportLog.event("seize", "\(why) during a seized loan — REUNION PROMPT raised (the hand-back stays the user's deliberate act) [seize]")
        notifyUI()
        issueReunionPromptAlert()
    }

    /// Tell the phone this watch holds the pod, so it does not read silence as a dead watch.
    func sendHoldsPodStatusReport(reason: String) {
        guard phase == .active, let current = epoch else { return }
        sendMessage(.statusReport(StatusReport(
            epoch: current,
            mode: currentMode(),
            lastDirectGlucoseAge: loopManager.latestGlucoseAge,
            lastEventSeq: journal.lastEventSeq,
            podFault: pumpFaultDescription,
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

    /// Keep: the loan continues, the phone is told again, and the prompt is not raised again this loan.
    func dismissReunionPrompt() {
        queue.async {
            guard self.reunionPromptActive else { return }
            self.reunionPromptActive = false
            self.reunionKeepChosen = true
            SportLog.event("seize", "reunion prompt: KEEP chosen — seized loan continues [seize]")
            self.notifyUI()

            self.sendHoldsPodStatusReport(reason: "Keep chosen")
        }
    }

    /// The prompt's alert half, so the phone's return is visible without the glance on screen. A
    /// routine prompt: the watch keeps dosing.
    func issueReunionPromptAlert() {
        let title = NSLocalizedString("iPhone Is Back", comment: "Watch alert title when the phone returns during a seized loan")
        let body = NSLocalizedString("Sport Mode is still running without it. Open the app to hand the pod back, or keep going.", comment: "Watch alert body when the phone returns during a seized loan")
        Task { @MainActor in
            loopManager.issueAlert(Alert(
                identifier: Alert.Identifier(managerIdentifier: "PodLoan", alertIdentifier: "seizeReunionPrompt"),
                foregroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                backgroundContent: Alert.Content(title: title, body: body, acknowledgeActionButtonLabel: "OK"),
                trigger: .immediate, interruptionLevel: .active))
        }
    }

    /// Latest-only: a new copy replaces the old.
    func handleDormantGrant(_ dormant: DormantGrant) {
        guard let data = try? LoanProtocol.encoder.encode(dormant) else {
            SportLog.event("seize", "dormant grant arrived but failed to re-encode — NOT stored [seize]")
            return
        }
        dormantGrantStore.wrappedValue = data
        standingPumpConfiguration = dormant.grant.sharedPumpConfiguration
        SportLog.event("seize", String(format: "dormant grant refreshed — issued %@, %d dose record(s), token …%@, pump %@ [seize]",
                                       DateFormatter.localizedString(from: dormant.issuedAt, dateStyle: .none, timeStyle: .medium),
                                       dormant.grant.doseHistory.count,
                                       String(dormant.seizeToken.uuidString.suffix(8)),
                                       dormant.grant.sharedPumpConfiguration?.managerIdentifier ?? "unknown"))
    }

    /// nil if absent or undecodable.
    func storedDormantGrant() -> DormantGrant? {
        guard let data = dormantGrantStore.wrappedValue else { return nil }
        return try? LoanProtocol.decoder.decode(DormantGrant.self, from: data)
    }

    // MARK: - The ledger's open window

    /// A reading starts the next window: the copy's at a grant, then every pump report's.
    func noteReading(units: Double, at: Date) {
        updateState { $0.ledgerLast = (units: units, at: at) }
    }

    /// This watch's records over a window, from its own store: the seeded history, the pod's own
    /// reports and this watch's doses. An estimate stands for insulin given before it was booked,
    /// so none is in any window.
    func ownRecords(from start: Date) async -> [LoanDoseRecord] {
        let doses = (try? await loopManager.doseStore.getNormalizedDoseEntries(start: start.addingTimeInterval(-.hours(1)))) ?? []
        return doses.filter { !($0.syncIdentifier?.hasPrefix(Self.estimateSyncPrefix) ?? false) }
            .compactMap(LoanDoseRecord.init(storeDose:))
    }

    /// Called from the pump's report, before the report completes, so the cycle the reading feeds
    /// sees the verdict. Each reading closes the open window against this watch's own records; what
    /// they cannot explain, in practice a phone's doses since the copy or while this watch was off,
    /// is booked in this watch's store only: the phone has the real records, so nothing goes home,
    /// and the booking ends with this loan's insulin book.
    func checkOwnPumpTotal(reading: (units: Double, at: Date), pulseUnits: Double, insulinType: InsulinType?) async {
        guard let last = persisted.ledgerLast else {
            noteReading(units: reading.units, at: reading.at)
            return
        }
        guard reading.at > last.at else { return }
        noteReading(units: reading.units, at: reading.at)
        // A lower total is a different pod: start again from it.
        guard reading.units >= last.units else { return }
        let records = await ownRecords(from: last.at)
        let unexplained = LoanReconciler.insulinNotInRecords(totalThen: last.units, then: last.at, totalNow: reading.units, now: reading.at,
                                                             records: records, schedule: loopManager.settings.basalRateSchedule,
                                                             pulseUnits: pulseUnits)
        let minutes = reading.at.timeIntervalSince(last.at) / 60
        guard unexplained > Self.unexplainedInsulinBand else {
            SportLog.event("loan", String(format: "[odometer] (own) %.1f min: pump total %.2f → %.2f, residual %+.3f",
                                          minutes, last.units, reading.units, unexplained))
            return
        }
        let at = now()
        let entry = DoseEntry(type: .bolus, startDate: at, endDate: at, value: unexplained, unit: .units,
                              decisionId: nil, deliveredUnits: unexplained,
                              syncIdentifier: "\(Self.estimateSyncPrefix)-\(Int(at.timeIntervalSince1970))", insulinType: insulinType)
        do {
            try await loopManager.seedInsulinHistory([entry])
        } catch {
            SportLog.event("loan", String(format: "** over the last %.1f min: %.2f U UNEXPLAINED and the booking FAILED — %@ **",
                                          minutes, unexplained, String(describing: error)))
            return
        }
        SportLog.event("loan", String(format: "** pod total %.2f → %.2f U over %.1f min; %.2f U the records cannot explain — BOOKED as a bolus now (insulin on board errs high, dosing errs low) **",
                                      last.units, reading.units, minutes, unexplained))
        queue.async {
            self.startNote = (at, String(format: NSLocalizedString("%.2f U the watch had no record of — counted as insulin on board", comment: "Glance: unexplained insulin booked (1: units)"), unexplained))
            self.notifyUI()
        }
    }

    /// For log tags, from activation until the loan closes.
    var seizeMarkerActive: Bool {
        pendingSeizeToken != nil || persisted.seizeToken != nil
    }

    /// Bounds the handshake, not the credential.
    static let seizeActivationLease: TimeInterval = 5 * 60

    /// The phone's reconciliation band.
    static let unexplainedInsulinBand = 0.20

    /// Every estimate's sync identifier starts with this; no window's records include one.
    static let estimateSyncPrefix = "LOAN-WATCH-GAP"
}
