//
//  PodLoanWatchController+Seize.swift
//  WatchApp Extension
//
//  Starting a loan without the phone from the stored dormant grant. When the phone returns the loan
//  simply continues; the looper ends it the ordinary way (control row 17).
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
        DispatchQueue.main.async {
            // Only from rest, and only for the credential the offer was raised for.
            guard self.phase == .idle || self.phase == .recoveredDrain, let offer = self.seizeOffer,
                  let dormant = self.storedDormantGrant(), dormant.seizeToken == offer.token else {
                SportLog.event("seize", "offline start confirmed with no offer standing; ignored")
                return
            }
            self.seizeOffer = nil

            let newEpoch = max(dormant.grant.epoch,
                               (self.epoch ?? 0) + 1,
                               (self.journal.activeEpoch ?? 0) + 1,
                               self.persisted.highWaterEpoch + 1,
                               (self.lastRevokedEpoch ?? 0) + 1)

            let leaseUntil = self.now().addingTimeInterval(Self.seizeActivationLease)
            self.pendingSeizeToken = dormant.seizeToken

            // Drop queued requests before the pod changes hands.
            self.cancelStaleQueuedRequests(context: "seize confirmed")
            SportLog.event("seize", String(format: "offline start confirmed as loan %d, from the grant stored %@",
                                           newEpoch, DateFormatter.localizedString(from: dormant.issuedAt, dateStyle: .short, timeStyle: .short)))
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
        DispatchQueue.main.async {
            guard self.seizeOffer != nil else { return }
            self.seizeOffer = nil
            // The Start is withdrawn: a grant that still arrives for it starts nothing (transfer G).
            self.startCancelled = true
            self.cancelStaleQueuedRequests(context: "offer declined")
            SportLog.event("seize", "offline start declined")
            self.notifyUI()
        }
    }

    /// The phone in reach during a seized loan is told at once that this watch holds the pod, so it
    /// stands aside. Reachability only prompts the message; nothing is decided on it.
    func noteReachabilityChanged(_ reachable: Bool) {
        DispatchQueue.main.async {
            guard reachable, self.phase == .active, self.persisted.seizeToken != nil, !self.handbackRequested else { return }
            self.sendHoldsPodStatusReport(reason: "the phone is in reach")
        }
    }

    /// Tell the phone this watch holds the pod, so it does not read silence as a dead watch.
    func sendHoldsPodStatusReport(reason: String) {
        guard phase == .active, let current = epoch else { return }
        sendMessage(.statusReport(StatusReport(
            epoch: current,
            lastDirectGlucoseAge: loopManager.latestGlucoseAge,
            lastEventSeq: journal.lastEventSeq,
            podFault: pumpFaultDescription,
            holdsPod: true,
            knowsGrant: true,
            podReachable: podReachedLately,
            loanStartedAt: persisted.deliveredAtTakeoverAt)))
        SportLog.event("seize", "told the phone this watch holds the pod\(podReachedLately == false ? " but cannot reach it" : ""): \(reason)")
    }

    /// Latest-only: a new copy replaces the old.
    func handleDormantGrant(_ dormant: DormantGrant) {
        guard let data = try? LoanProtocol.encoder.encode(dormant) else {
            SportLog.event("seize", "grant for an offline start could not be encoded; not stored")
            return
        }
        dormantGrantStore.wrappedValue = data
        standingPumpConfiguration = dormant.grant.sharedPumpConfiguration
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
            SportLog.event("loan", String(format: "insulin check over %.1f min: pump total %.2f → %.2f U, residual %+.3f U",
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
            SportLog.event("loan", String(format: "could not book %.2f U unexplained over %.1f min: %@",
                                          unexplained, minutes, String(describing: error)))
            return
        }
        SportLog.event("loan", String(format: "booked %.2f U the records cannot explain as a bolus: pump total %.2f → %.2f U over %.1f min",
                                      unexplained, last.units, reading.units, minutes))
        DispatchQueue.main.async {
            self.startNote = (at, String(format: NSLocalizedString("%.2f U the watch had no record of — counted as insulin on board", comment: "Glance: unexplained insulin booked (1: units)"), unexplained))
            self.notifyUI()
        }
    }

    /// Bounds the handshake, not the credential.
    static let seizeActivationLease: TimeInterval = LoanControl.takeoverLease

    /// The phone's reconciliation band.
    static let unexplainedInsulinBand = 0.20

    /// Every estimate's sync identifier starts with this; no window's records include one.
    static let estimateSyncPrefix = "LOAN-WATCH-GAP"
}
