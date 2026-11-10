//
//  PodLoanWatchController+Handback.swift
//  StockLoop
//
//  Giving the pod back, and every other way a loan ends. Two-phase: the watch keeps dosing
//  while interim offers drain the journal; the pod is released only after the final offer's
//  ack. Once released, the watch stays stopped.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController {

    /// The user's End: starts the drain; dosing continues until everything is acked. A phone
    /// without interim-offer support gets the single-phase path. `trigger` is the End tap, or the
    /// looper's Deactivate of a faulted pod.
    func beginHandback(trigger: LoanControl.Trigger = .endTapped) {
        DispatchQueue.main.async {
            guard self.phase == .active, let pumpManager = self.pumpManager else { return }
            guard !self.handbackRequested else { return }
            // Nobody takes the pod while it is giving a bolus (transfer H): End again after it.
            if let bolus = self.bolusUnderWay(pumpManager) {
                self.refuseEnd(bolus, at: "the tap")
                return
            }
            self.handbackRequested = true
            self.handbackFailure = nil
            self.handbackResendCount = 0
            self.handbackSawUnreachable = false
            self.handbackSawUrgentSendError = false
            self.urgentSendWedged = false

            // One budget for the give-up deadline and the pre-scheduled stuck alert.
            self.handbackDeadline = self.now().addingTimeInterval(HandbackStuckAlert.interval)
            self.handbackStartedAt = self.now()
            HandbackStuckAlert.arm()
            SportLog.event("loan", "hand-back requested with \(self.journal.unackedEvents().count) record(s) to send; the watch doses until the phone answers")
            // Rows 7, 8, 21, 26 and 27: the offer is the query; `LoanControl` decides what silence means.
            let tappedAt = self.now()
            self.handbackAckedAt = nil
            self.sendHandbackOffer(recovered: false)
            guard case .query(let wait, let onSilence, _) = LoanControl.decide(LoanControl.Situation(device: .watch, trigger: trigger)) else { return }
            // A timer is safe here: it starts at the looper's End tap, with Loop in front, and a late
            // firing re-checks whether the phone answered since the tap before refusing the End.
            self.schedule(after: wait.seconds, label: "handback-answer") { [weak self] in
                guard let self = self, self.phase == .active, self.handbackRequested,
                      self.handbackAckedAt.map({ $0 >= tappedAt }) != true else { return }
                switch LoanControl.afterQuery(.silence, onSilence: onSilence) {
                case .refuse:
                    self.handbackTimedOut(unreachable: true)
                case .tell(.podDeactivatedPhoneAway):
                    self.handbackTimedOut(unreachable: true)
                    // Queued: the phone ends Sport Mode when it hears (row 27).
                    self.sendHoldsPodStatusReport(reason: "the pod is deactivated and the phone did not answer the End")
                default:
                    break
                }
            }
        }
    }

    /// The watch's bolus as the bolus rule sees it: the pump's own state, or a manual bolus the
    /// watch has sent that the pump has not taken up yet.
    func bolusUnderWay(_ pumpManager: PumpManager) -> LoanControl.BolusUnderWay? {
        pumpManager.status.bolusState.underWay
            ?? (loopManager.manualBolusStartedAt != nil ? LoanControl.BolusUnderWay(endsAt: nil) : nil)
    }

    /// The End is refused and the loan continues: said on screen and felt.
    private func refuseEnd(_ bolus: LoanControl.BolusUnderWay, at moment: String) {
        refuseEnd(saying: LoanControl.bolusRefusal(bolus, now: now()),
                  why: "a bolus is being given, ending \(bolus.endsAt.map { "in \(Int($0.timeIntervalSince(now()).rounded(.up))) s" } ?? "when the pod has it")", at: moment)
    }

    private func refuseEnd(saying message: String, why: String, at moment: String) {
        handbackRequested = false
        resendWorkItem?.cancel()
        handbackDeadline = nil
        handbackStartedAt = nil
        HandbackStuckAlert.disarm()
        handbackFailure = (now(), message)
        SportLog.event("loan", "hand-back refused at \(moment): \(why)")
        playRefusal()
        notifyUI()
    }

    /// Nobody starts a bolus while the pod is being handed back: with an End waiting, a bolus asked
    /// for on the watch is refused, and this says why. Nil when a bolus may go.
    func bolusRefusalWhileEnding() -> String? {
        guard handbackRequested || phase == .handingBack else { return nil }
        return NSLocalizedString("Sport Mode is ending. Bolus on the iPhone once it has the pod.", comment: "Watch: a bolus refused while an End is waiting for the phone")
    }

    /// Where a bolus asked for on the watch goes. Refused while an End is under way: stock's route
    /// would send it to the phone, which gives it once it has the pod back.
    enum BolusRoute: Equatable {
        case watchPump, stockRouteToPhone, refused(String)
    }

    func bolusRoute(units: Double) -> BolusRoute {
        if units > 0, let refusal = bolusRefusalWhileEnding() { return .refused(refusal) }
        return isLoanActive ? .watchPump : .stockRouteToPhone
    }

    /// Cancellable until `finalizeHandback`.
    func cancelHandback() {
        DispatchQueue.main.async {
            guard self.phase == .active, self.handbackRequested else { return }
            self.handbackRequested = false
            self.resendWorkItem?.cancel()
            self.handbackDeadline = nil
            self.handbackStartedAt = nil
            HandbackStuckAlert.disarm()
            SportLog.event("loan", "hand-back cancelled; Sport Mode continues")
        }
    }

    /// No ack is coming. Before the final offer the loan simply continues; after it the watch
    /// stays stopped and becomes a parked drain.
    func handbackTimedOut(unreachable: Bool = false, refusal: String? = nil) {
        let why: String
        if let refusal { why = "refused by the phone: \(refusal)" }
        else if unreachable { why = "not possible: the phone did not answer the offer" }
        else { why = "timed out after \(Int(HandbackStuckAlert.interval)) s with no answer from the phone" }
        handbackFailure = (now(), refusal ?? (unreachable
            ? NSLocalizedString("iPhone didn't answer, so the watch is still looping. To stop automatic dosing, open the loop on the watch.", comment: "Glance message: End refused, the phone did not answer")
            : NSLocalizedString("iPhone didn't respond. The watch is still looping.", comment: "Glance transient: End failed, no ack")))
        resendWorkItem?.cancel()
        handbackDeadline = nil
        handbackStartedAt = nil
        // Read before the flags are unwound.
        let wasFinal = (phase == .handingBack)
        let wedge = HandbackWedge.classify(resendCount: handbackResendCount,
                                           sawUnreachable: handbackSawUnreachable,
                                           reachableNow: isPhoneReachable(),
                                           sendsErrored: handbackSawUrgentSendError)
        let wedgeNote: String
        switch wedge {
        case .sessionReestablishing:
            wedgeNote = "; \(handbackResendCount) offers unanswered and the sends failed: the link is re-establishing"
        case .oneWay:
            wedgeNote = "; \(handbackResendCount) offers unanswered while the phone was reachable: the link is stuck one way"
        case .none:
            wedgeNote = ""
        }
        handbackRequested = false
        finalOfferSent = false
        if wasFinal {
            SportLog.event("loan", "hand-back \(why); the pod is released and the records keep going to the phone\(wedgeNote)")
            teardownPump()
            finalOfferSentAt = nil
            deliveredAtTakeover = nil
            onLoanActiveChanged?(false)

            phase = .recoveredDrain
            sendHandbackOffer(recovered: true)
            issueProtocolAlert(title: NSLocalizedString("End Not Confirmed", comment: "Watch alert title: the phone has not confirmed a hand-back"),
                               body: NSLocalizedString("Neither device is looping. Reclaim the pod on the iPhone.", comment: "Watch alert body: released but unconfirmed hand-back"))
        } else {
            let after = podDeactivatedHere ? "the pod is deactivated; the phone ends Sport Mode when it hears" : "Sport Mode continues on the watch"
            SportLog.event("loan", "hand-back \(why); \(after)\(wedgeNote)")
        }
        // A link stuck one way, while the loan is still live and the watch still doses: a normal
        // alert. A re-establishing link self-heals in a minute or two, so it is never alerted.
        if wedge == .oneWay, !wasFinal {
            issueProtocolAlert(title: "End Not Confirmed",
                               body: "The watch is still looping. Reopening Loop on both devices usually clears this.",
                               identifier: "handbackOneWay", interruptionLevel: .active)
        }

        HandbackStuckAlert.disarm()
    }

    /// Dosing stops and the released offer goes out. The interim resend is cancelled first. The
    /// running temp is left for the phone to cancel at its verified reclaim.
    func finalizeHandback() {
        // A bolus started while the End waited for the phone: the End is refused, not finished.
        if phase == .active, let manager = pumpManager, let bolus = bolusUnderWay(manager) {
            refuseEnd(bolus, at: "the release")
            return
        }
        resendWorkItem?.cancel()
        finalOfferSent = false
        // No pump manager left: send the released offer straight away.
        guard let manager = pumpManager else {
            handbackRequested = false
            phase = .handingBack
            finalOfferSent = true
            sendHandbackOffer(recovered: false)
            return
        }
        // Dosing stops on the loop's lane, behind any cycle already sending: its dose is then
        // journaled while the loan is still live, and rides in the final offer.
        loopManager.onLane { [loopManager] in
            loopManager.pumpManager = nil
            self.finalizeHandback(releasing: manager)
        }
    }

    private func finalizeHandback(releasing manager: PumpManager) {
        // A second trigger while the first waited for the loop.
        guard phase == .active else { return }
        // Dosing has stopped: the pod is let go here, before the final offer. The driver keeps it while
        // a command to it is unconfirmed; then the End is refused and the loop doses again.
        if let control = manager as? ExclusiveDeviceControl {
            control.releaseControl()
            guard control.isControlReleased else {
                loopManager.onLane { [loopManager] in loopManager.pumpManager = manager }
                refuseEnd(saying: LoanControl.unconfirmedCommandRefusal,
                          why: "the pod driver kept the pod, as a command to it is unconfirmed", at: "the release")
                return
            }
        }
        handbackRequested = false
        phase = .handingBack

        SportLog.event("loan", "dosing stopped; finishing the hand-back")

        let runningTemp: DoseEntry? = {
            if case .tempBasal(let dose) = manager.status.basalDeliveryState { return dose }
            return nil
        }()

        if runningTemp != nil {
            SportLog.event("loan", String(format: "temp basal %.2f U/hr, ending %@, is left running for the phone to cancel",
                                          runningTemp?.unitsPerHour ?? 0,
                                          runningTemp.map { ISO8601DateFormatter().string(from: $0.endDate) } ?? "—"))
        }

        // No pod read here: the phone judges the loan by its own read after it takes the pod back.
        let pumpIdentifier = manager.pluginIdentifier, loopManager = self.loopManager
        Task {
            // The pod's alerts are the phone's from here. Closed before the final offer, so its
            // records carry the close; one left open, the phone replays at its next launch.
            await loopManager.retractStandingAlerts(ofPump: pumpIdentifier)
            DispatchQueue.main.async {
                self.finalOfferSent = true
                self.sendHandbackOffer(recovered: false)
            }
        }
    }

    /// Sends one offer, by every path, and arms the next: a late interim offer only stores records,
    /// and nothing returns the watch to dosing after the final one.
    func sendHandbackOffer(recovered: Bool) {
        guard let epoch = epoch ?? journal.activeEpoch else { return }
        // After a revoke's teardown, use the total captured before it.
        var odometer: LoanOdometerSnapshot?
        if let start = deliveredAtTakeover,
           let latest = pumpOdometer?.deliveredUnits?.units ?? revokeCapturedDelivered {
            odometer = LoanOdometerSnapshot(deliveredAtStart: start, deliveredLatest: latest,
                                            asOf: pumpOdometer?.deliveredUnits?.at ?? revokeCapturedDeliveredAt,
                                            deliveredAtStartAt: persisted.deliveredAtTakeoverAt)
        }
        let offerEvents = journal.unackedEvents()
        let offer = HandbackOffer(
            epoch: epoch,
            handedBackAt: self.now(),
            finalStatus: pumpManager.map { _ in currentPodStatus() },
            odometer: odometer,
            events: offerEvents,
            tombstones: journal.pendingTombstones(),
            recovered: recovered,
            released: phase != .active,

            // A recovered offer sends nil: a rebooted flag is not the user's.
            watchClosedLoopEnabled: recovered ? nil : loopManager.closedLoopEnabled,

            // Lets the phone retro-acknowledge a loan it never granted.
            seizeToken: persisted.seizeToken,

            lastLoopCompleted: loopManager.lastLoopCompleted,
            podDeactivated: persisted.podDeactivatedEpoch == epoch)
        if offer.released == true, finalOfferSentAt == nil { finalOfferSentAt = self.now() }
        handbackResendCount += 1

        if !isPhoneReachable() { handbackSawUnreachable = true }
        sendMessage(.handbackOffer(offer))

        resendWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Checked on each resend, so a suspended app still notices.
            if let deadline = self.handbackDeadline, self.now() >= deadline,
               self.phase == .handingBack || (self.phase == .active && self.handbackRequested) {
                self.handbackTimedOut()
                return
            }

            // The drain's ceiling; the phone already has the records.
            let drain = self.phase == .revoked || self.phase == .recoveredDrain
            if drain, self.handbackResendCount >= Self.maxDrainResends {
                let unanswered = self.handbackResendCount
                self.resendWorkItem?.cancel()
                if let closing = self.epoch ?? self.journal.activeEpoch { self.sendLoanHistoryHome(epoch: closing) }
                self.teardownPump()
                self.journal.end()
                // Closed in one save; the token goes too, or the next loan is mistaken for a seized one.
                self.updateState {
                    $0.phase = .idle
                    $0.epoch = nil
                    $0.deliveredAtTakeover = nil
                    $0.deliveredAtTakeoverAt = nil
                    $0.ledgerLast = nil
                    $0.seizeToken = nil
                }
                self.handbackDeadline = nil
                self.handbackStartedAt = nil
                self.finalOfferSentAt = nil
                self.handbackRequested = false
                self.finalOfferSent = false
                // Per-session counters and wedge flags reset with the session.
                self.handbackResendCount = 0
                self.handbackSawUnreachable = false
                self.handbackSawUrgentSendError = false
                self.urgentSendWedged = false
                HandbackStuckAlert.disarm()
                self.onLoanActiveChanged?(false)
                SportLog.event("loan", "loan closed after \(unanswered) unanswered offers; the phone already has the pod and the records")
                return
            }
            if self.phase == .handingBack || drain
                || (self.phase == .active && self.handbackRequested) {
                self.sendHandbackOffer(recovered: recovered)
            }
        }
        resendWorkItem = work
        // A timer is safe here: a late resend only sends again. The 2-minute budget is a deadline checked
        // on each run, and the looper is told on time by the system-scheduled `HandbackStuckAlert`.
        schedule(after: 15, label: "handback-resend", execute: work)
    }

    /// Advances the cursor on every ack; only an ack of a released offer releases the pod.
    func handleAck(_ ack: HandbackAck) {
        // A parked drain has no controller epoch; use the journal's.
        guard let current = epoch ?? journal.activeEpoch, ack.epoch == current else {
            SportLog.event("loan", "ignored the phone's acknowledgement for loan \(ack.epoch); ours is \((epoch ?? journal.activeEpoch).map(String.init) ?? "none")")
            return
        }
        // The phone answered the offer: the End is not refused.
        handbackAckedAt = now()
        // An empty backlog is the finalize gate.
        journal.applyAck(committedCursor: ack.committedCursor)
        guard journal.unackedEvents().isEmpty else { return }

        // Fully drained while the user is still waiting: that is what triggers finalize.
        if phase == .active && handbackRequested {
            finalizeHandback()
            return
        }
        guard phase == .handingBack || phase == .revoked || phase == .recoveredDrain else { return }

        // Only the phone's answer to a released offer closes the loan.
        guard ack.released, phase != .handingBack || finalOfferSent else { return }

        resendWorkItem?.cancel()

        let ackWait = finalOfferSentAt.map { String(format: " %.1f s after the final offer", self.now().timeIntervalSince($0)) } ?? ""
        SportLog.event("loan", "phone acknowledged the hand-back\(ackWait); releasing the pod")
        // The pod advertises for the phone again from here.
        teardownPump()
        sendLoanHistoryHome(epoch: current)
        // Closed: epoch, journal, takeover odometer and seize token go; the high-water epoch stays.
        finalOfferSentAt = nil
        journal.end()
        updateState {
            $0.phase = .idle
            $0.epoch = nil
            $0.deliveredAtTakeover = nil
            $0.deliveredAtTakeoverAt = nil
            $0.ledgerLast = nil
            $0.seizeToken = nil
        }
        handbackDeadline = nil
        handbackStartedAt = nil
        HandbackStuckAlert.disarm()
        onLoanActiveChanged?(false)
        SportLog.event("loan", "loan closed: records delivered and pod released")
    }

    /// The phone asking for the pod back. `lastRevokedEpoch` is recorded first, closing the
    /// split-brain hole; a stale revoke is answered with what this watch holds.
    func handleRevoke(_ revoke: Revoke) {
        if revoke.epoch > (lastRevokedEpoch ?? Int.min) {
            lastRevokedEpoch = revoke.epoch
        }
        guard let current = epoch ?? journal.activeEpoch, revoke.epoch == current else {
            SportLog.event("loan", "take-back for loan \(revoke.epoch) matches no loan here; grants up to that loan are refused from now on")

            if phase == .active, (epoch ?? Int.min) > revoke.epoch {
                sendHoldsPodStatusReport(reason: "a stale take-back for loan \(revoke.epoch)")
            }
            return
        }
        // The stop rides two channels: the later copy of one already acted on changes nothing.
        guard phase != .idle, phase != .revoked else { return }

        handbackRequested = false
        handbackDeadline = nil
        handbackStartedAt = nil
        HandbackStuckAlert.disarm()

        // Capture the odometer before the teardown frees the pod for the phone.
        revokeCapturedDelivered = pumpOdometer?.deliveredUnits?.units
        revokeCapturedDeliveredAt = pumpOdometer?.deliveredUnits?.at
        loopManager.pumpManager = nil
        teardownPump()
        phase = .revoked
        onLoanActiveChanged?(false)
        lastIdleNote = NSLocalizedString("Sport Mode ended. Your iPhone has the pod.", comment: "Glance note after the phone took the pod back")
        SportLog.event("loan", "phone took the pod back; sending the remaining records")
        sendHandbackOffer(recovered: true)
    }

    /// What the watch recorded in stock's stores during the loan (dosing decisions, alerts, device
    /// log) goes home once, at its close, in one background file transfer: everything stored since
    /// the last file went. Every close comes here (the ack of the final offer, the ack of a revoke's or
    /// relaunch's drain, a drain given up), so a force reclaim's history follows whenever this
    /// watch learns its loan ended. Each store's anchor advances only once the file is handed over.
    func sendLoanHistoryHome(epoch: Int) {
        let decisionsAnchor = persisted.dosingDecisionsSent.flatMap(DosingDecisionStore.QueryAnchor.init(rawValue:))
        let alertsAnchor = persisted.alertsSent.flatMap(AlertStore.QueryAnchor.init(rawValue:))
        let deviceLogAnchor = persisted.deviceLogSent
        let loopManager = self.loopManager
        Task {
            let decisions = await Self.dosingDecisions(in: loopManager.dosingDecisionStore, since: decisionsAnchor, epoch: epoch)
            let alerts = await Self.alerts(in: loopManager.settledAlertStore(), since: alertsAnchor, epoch: epoch)
            let deviceLog = await Self.deviceLogEntries(in: loopManager.deviceLog, after: deviceLogAnchor, epoch: epoch)
            DispatchQueue.main.async {
                let history = LoanHistory(epoch: epoch, decisions: decisions?.decisions ?? [], alerts: alerts?.alerts ?? [],
                                          deviceLog: deviceLog ?? [])
                let counts = "\(history.decisions.count) dosing decision(s), \(history.alerts?.count ?? 0) alert(s), \(history.deviceLog?.count ?? 0) device log line(s)"
                guard !history.decisions.isEmpty || history.alerts?.isEmpty == false || history.deviceLog?.isEmpty == false else {
                    return
                }
                guard let data = try? history.encoded(),
                      self.transferLoanHistory?(data, history.fileMetadata) == true else {
                    SportLog.event("loan", "loan history for loan \(epoch) not sent: the file could not be handed over; the next close retries")
                    return
                }
                self.updateState {
                    if let decisions { $0.dosingDecisionsSent = decisions.anchor.rawValue }
                    if let alerts { $0.alertsSent = alerts.anchor.rawValue }
                    if let newest = deviceLog?.last?.timestamp { $0.deviceLogSent = newest }
                }
                SportLog.event("loan", "loan history for loan \(epoch) sent to the phone: \(counts)")
            }
        }
    }

    /// The decisions stored since `anchor`; nil when the query failed, so its anchor stays.
    private static func dosingDecisions(in store: DosingDecisionStore?, since anchor: DosingDecisionStore.QueryAnchor?,
                                        epoch: Int) async -> (anchor: DosingDecisionStore.QueryAnchor, decisions: [StoredDosingDecision])? {
        guard let store else { return nil }
        return await withCheckedContinuation { continuation in
            store.executeDosingDecisionQuery(fromQueryAnchor: anchor, limit: maxDosingDecisionsHome) { result in
                switch result {
                case .failure(let error):
                    SportLog.event("loan", "could not read the dosing decisions for loan \(epoch): \(error)")
                    continuation.resume(returning: nil)
                case .success(let newAnchor, let decisions):
                    continuation.resume(returning: (newAnchor, decisions))
                }
            }
        }
    }

    /// The alert records added or changed since `anchor`; nil when the query failed.
    private static func alerts(in store: AlertStore?, since anchor: AlertStore.QueryAnchor?,
                               epoch: Int) async -> (anchor: AlertStore.QueryAnchor, alerts: [SyncAlertObject])? {
        guard let store else { return nil }
        do {
            let (newAnchor, alerts) = try await store.executeAlertQuery(fromQueryAnchor: anchor, limit: maxAlertsHome)
            return (newAnchor, alerts)
        } catch {
            SportLog.event("loan", "could not read the alerts for loan \(epoch): \(error)")
            return nil
        }
    }

    /// The device log lines written after `anchor`, oldest first; nil when the fetch failed. Lines
    /// past the log's age go first, as stock's export purges them: nothing else on the watch does.
    private static func deviceLogEntries(in deviceLog: PersistentDeviceLog?, after anchor: Date?,
                                         epoch: Int) async -> [LoanDeviceLogEntry]? {
        guard let deviceLog else { return nil }
        deviceLog.purgeLogEntries(before: deviceLog.earliestLogEntryDate)
        do {
            let entries = try await deviceLog.fetch(startDate: anchor ?? .distantPast, endDate: .distantFuture)
            return entries.filter { anchor == nil || $0.timestamp > anchor! }.map(LoanDeviceLogEntry.init)
        } catch {
            SportLog.event("loan", "could not read the device log for loan \(epoch): \(error)")
            return nil
        }
    }

    /// Far above a day of cycles; the query starts at the last anchor sent home, so one loan's.
    static let maxDosingDecisionsHome = 5000

    /// Far above any loan's alerts.
    static let maxAlertsHome = 1000

    /// After launch: report a takeover that died mid-flight, and restart a parked drain's resends.
    func drainRecoveredIfNeeded() {
        DispatchQueue.main.async {
            if let epoch = self.pendingInterruptedTakeoverEpoch {
                self.pendingInterruptedTakeoverEpoch = nil
                SportLog.event("loan", "takeover of loan \(epoch) was interrupted by a relaunch; telling the phone it failed")
                self.sendMessage(.takeoverFailed(TakeoverFailed(epoch: epoch, reason: "watch relaunched during takeover")))
            }
            guard self.phase == .recoveredDrain else { return }
            self.sendHandbackOffer(recovered: true)
        }
    }

    /// Claims ignorance of an epoch only when not active and behind it.
    func handleStatusQuery(_ query: StatusQuery) {
        guard let current = epoch, query.epoch == current else {
            if phase != .active, (epoch ?? Int.min) < query.epoch {
                // An explicit no lets the phone give up early.
                SportLog.event("loan", "phone asked about loan \(query.epoch), which never reached this watch; answered that it holds no pod")
                sendMessage(.statusReport(StatusReport(
                    epoch: query.epoch,
                    lastDirectGlucoseAge: nil,
                    lastEventSeq: 0,
                    podFault: nil,
                    holdsPod: false,
                    knowsGrant: false)))
            } else if phase == .active, (epoch ?? Int.min) > query.epoch {
                sendHoldsPodStatusReport(reason: "the phone asked about older loan \(query.epoch)")
            }
            return
        }
        // A holder that has not read the pod lately tries it before answering: "cannot reach" goes to the
        // phone only after a real attempt, since the phone takes the pod back on it. The question's wake,
        // then the pod's Bluetooth activity, keep the app running for the read.
        if phase == .active, podReachedLately != true, let odometer = pumpOdometer {
            SportLog.event("loan", "phone asked about loan \(current); reading the pod before answering")
            Task { [weak self] in
                // Twice: a first connect right after a wake can fail on a timeout that ran out while the
                // app slept (seen 11-03), and the second then reaches the pod.
                if await !odometer.refreshDeliveredUnits() { _ = await odometer.refreshDeliveredUnits() }
                DispatchQueue.main.async {
                    guard let self, self.epoch == current else { return }
                    self.answerStatusQuery(epoch: current)
                }
            }
            return
        }
        answerStatusQuery(epoch: current)
    }

    /// The query names our own live loan, so it is answered in full.
    private func answerStatusQuery(epoch current: Int) {
        let report = StatusReport(
            epoch: current,
            lastDirectGlucoseAge: loopManager.latestGlucoseAge,
            lastEventSeq: journal.lastEventSeq,
            podFault: pumpFaultDescription,
            holdsPod: phase == .active,
            knowsGrant: true,
            podReachable: phase == .active ? podReachedLately : nil,
            loanStartedAt: persisted.deliveredAtTakeoverAt,
            podDeactivated: persisted.podDeactivatedEpoch == current)
        sendMessage(.statusReport(report))
    }

    /// Whether this watch read the pod within the last cycle: a holder that cannot reach the pod says
    /// so, and the phone answers it like silence. Nil before any reading.
    var podReachedLately: Bool? {
        guard let reading = pumpOdometer?.deliveredUnits else { return nil }
        return now().timeIntervalSince(reading.at) <= LoanControl.watchReportOverdue
    }

    /// The phone reads reservoir and suspension itself at reclaim.
    func currentPodStatus() -> LoanPodStatus {
        LoanPodStatus(
            timestamp: self.now(),
            deliveredUnits: pumpOdometer?.deliveredUnits?.units,
            reservoirLevel: nil,
            isSuspended: false,
            faultCode: pumpFaultDescription)
    }

}

// MARK: - A faulted pod, deactivated here (rows 26 and 27)

extension PodLoanWatchController {

    /// The kit's name for ending the pod while it has failed for good; nil otherwise.
    var failedPodDeactivationTitle: String? {
        guard phase == .active, !podDeactivatedHere else { return nil }
        return pumpControl?.failedDeviceDeactivationTitle
    }

    var podDeactivatedHere: Bool {
        epoch != nil && persisted.podDeactivatedEpoch == epoch
    }

    /// The looper's Deactivate: the pod is ended and forgotten, its last delivery booked here as the
    /// kit books it, and Sport Mode ends.
    func deactivateFailedPod() {
        DispatchQueue.main.async {
            guard !self.deactivatingPod, self.failedPodDeactivationTitle != nil, let control = self.pumpControl else { return }
            self.deactivatingPod = true
            self.podDeactivationError = nil
            self.notifyUI()
            SportLog.event("loan", "deactivating the faulted pod from the watch: \(self.pumpFaultDescription ?? "no fault text")")
            // Read before the pod is forgotten: the hand-back's insulin check rules on it.
            let reading = self.pumpOdometer?.deliveredUnits
            Task {
                do {
                    try await control.deactivateFailedDevice()
                    await MainActor.run { self.podWasDeactivated(lastReading: reading) }
                } catch {
                    await MainActor.run {
                        self.deactivatingPod = false
                        self.podDeactivationError = error.localizedDescription
                        SportLog.event("loan", "deactivating the pod failed, so it stays: \(error)")
                        self.notifyUI()
                    }
                }
            }
        }
    }

    private func podWasDeactivated(lastReading: (units: Double, at: Date)?) {
        deactivatingPod = false
        guard phase == .active, let current = epoch else { return }
        updateState { $0.podDeactivatedEpoch = current }
        revokeCapturedDelivered = lastReading?.units
        revokeCapturedDeliveredAt = lastReading?.at
        // Stopped on purpose: no Loop Failure ladder while the End reaches the phone.
        LoopStallWatchdog.disarm()
        SportLog.event("loan", "the pod is deactivated; Sport Mode ends")
        notifyUI()
        // Its alarms are over: closed on the wrist and in the records the offer carries, then the End.
        let pumpIdentifier = pumpManager?.pluginIdentifier, loopManager = self.loopManager
        Task {
            if let pumpIdentifier { await loopManager.retractStandingAlerts(ofPump: pumpIdentifier) }
            DispatchQueue.main.async { self.beginHandback(trigger: .podDeactivated) }
        }
    }
}
