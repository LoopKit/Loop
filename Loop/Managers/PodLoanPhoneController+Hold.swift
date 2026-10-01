//
//  PodLoanPhoneController+Hold.swift
//  Loop
//
//  Noticing that the watch has gone quiet, and saying so.
//
//  Every cycle it completes, the watch sends a record batch — empty or not — stamped with the
//  time it was sent. When those stop, nobody may be adjusting insulin, so the phone warns.
//
//  It never takes the pod back on a timer. A watch that is alive but unheard is still dosing,
//  and a phone that reclaimed behind its back would dose beside a watch that knows nothing of
//  the phone's insulin. Taking the pod back stays the user's act, through the pod tile.
//

import Foundation
import LoopKit

extension PodLoanPhoneController {
    /// Three missed cycles. Shorter than this and an ordinary late report reads as silence.
    static let watchSilenceThreshold: TimeInterval = .minutes(15)

    /// Between noticing the silence and the first warning: one more chance to report, which is
    /// what a watch does within a cycle of coming back into range.
    static let watchSilenceGrace: TimeInterval = .minutes(5)

    /// Warnings after the grace, then nothing. Repeating forever trains the user to ignore it.
    static let watchSilenceWarningOffsets: [TimeInterval] = [0, .minutes(20), .minutes(40)]

    /// How fresh this phone's own sensor reading must be for it to count as near the user.
    /// A phone left at home hears nothing from the watch AND nothing from the sensor, and must
    /// not mistake its own absence for the watch's failure.
    static let nearTheBodyWindow: TimeInterval = .minutes(11)

    private enum HoldKeys {
        static let renewedAt = "PodLoanPhoneController.holdRenewedAt"
        static let noticedAt = "PodLoanPhoneController.holdLapseNoticedAt"
        static let warningsIssued = "PodLoanPhoneController.watchSilenceWarningsIssued"
    }

    /// When the watch last told us it completed a cycle. Persisted: a phone relaunch mid-session
    /// must not read as a fresh, silent watch.
    var holdRenewedAt: Date? {
        get { UserDefaults.standard.object(forKey: HoldKeys.renewedAt) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: HoldKeys.renewedAt) }
    }

    /// When the silence was first noticed, which is what the warning offsets count from.
    /// Clearing it also clears the warning count, so a watch that returns starts clean.
    var holdLapseNoticedAt: Date? {
        get { UserDefaults.standard.object(forKey: HoldKeys.noticedAt) as? Date }
        set {
            UserDefaults.standard.set(newValue, forKey: HoldKeys.noticedAt)
            if newValue == nil { UserDefaults.standard.removeObject(forKey: HoldKeys.warningsIssued) }
        }
    }

    /// How many of the warnings have gone out for this stretch of silence.
    private var watchSilenceWarningsIssued: Int {
        get { UserDefaults.standard.integer(forKey: HoldKeys.warningsIssued) }
        set { UserDefaults.standard.set(newValue, forKey: HoldKeys.warningsIssued) }
    }

    /// Forget where this loan started. An audit describes ONE loan, so every path that ends a
    /// loan calls this: anchors left behind make the next reclaim audit a session that already
    /// closed, and report its insulin as unexplained.
    func clearAuditAnchors() {
        checkpointsThisLoan = 0
        auditBase = nil
        loanStartedAt = nil
        UserDefaults.standard.removeObject(forKey: Keys.loanStartedAt)
        UserDefaults.standard.removeObject(forKey: Keys.deliveredAtTakeover)
        UserDefaults.standard.removeObject(forKey: Keys.deliveredAtGrant)
    }

    /// Record that the watch reported, judged by the time the message was SENT rather than when
    /// it arrived — a batch that sat in a queue for an hour renews nothing.
    func noteHoldRenewal(sentAt: Date?) {
        let now = deps.now()
        let stamp = min(sentAt ?? now, now)
        // Never move the stamp backwards: batches can arrive out of order.
        guard stamp > (holdRenewedAt ?? .distantPast) else { return }
        holdRenewedAt = stamp
        if holdLapseNoticedAt != nil, now.timeIntervalSince(stamp) <= Self.watchSilenceThreshold {
            holdLapseNoticedAt = nil
            handbackDiag(epoch, "watch REPORTING again — the silence warning stands down")
        }
    }

    /// Called on every phone loop cycle. All the judgement lives below, so this is almost always
    /// one enqueued no-op.
    func considerHoldLapse() {
        queue.async { self.queue_considerHoldLapse() }
    }

    func queue_considerHoldLapse() {
        // A loan the watch announced (a phoneless start) counts too: this phone is standing
        // aside for it, so its silence matters exactly as much as a loan we granted.
        let told = state == .owner && yieldingToInferredLoan
        let renewedAt = told ? [holdRenewedAt, newestForeignLoanEvidence?.at].compactMap { $0 }.max() : holdRenewedAt
        guard state == .loaned || state == .grantOffered || told, let renewed = renewedAt else {
            if holdLapseNoticedAt != nil { holdLapseNoticedAt = nil }
            return
        }
        let now = deps.now()
        let silence = now.timeIntervalSince(renewed)
        // Silent AND near the body. Away from the user the phone cannot tell a dead watch from
        // a distant one, so it says nothing rather than warning about a session that is fine.
        guard silence > Self.watchSilenceThreshold,
              let reading = deps.latestGlucoseDate(), now.timeIntervalSince(reading) <= Self.nearTheBodyWindow else {
            if holdLapseNoticedAt != nil { holdLapseNoticedAt = nil }
            return
        }
        // First sight of the silence: start the clock, warn at the next cycle that still sees it.
        guard let noticed = holdLapseNoticedAt else {
            holdLapseNoticedAt = now
            handbackDiag(epoch, String(format: "watch SILENT — no report for %.0f min with this phone beside the body; first warning in %.0f min unless it reports",
                                       silence / 60, Self.watchSilenceGrace / 60))
            return
        }
        let issued = watchSilenceWarningsIssued
        guard issued < Self.watchSilenceWarningOffsets.count,
              now.timeIntervalSince(noticed) >= Self.watchSilenceGrace + Self.watchSilenceWarningOffsets[issued] else { return }
        watchSilenceWarningsIssued = issued + 1
        handbackDiag(epoch, String(format: "watch SILENT %.0f min — warning %d of %d issued; the pod stays assigned to the watch until the user takes it back",
                                   silence / 60, issued + 1, Self.watchSilenceWarningOffsets.count))
        deps.issueUrgentNotice(
            NSLocalizedString("Watch Not Reporting", comment: "Phone warning title: the watch has stopped reporting loop cycles during a session"),
            String(format: NSLocalizedString("The watch hasn't reported a loop for %1$.0f minutes. The pod is still assigned to it. If the watch is off or out of battery, tap the pod tile to bring the pod back to this phone.", comment: "Phone warning body: watch silent mid-session (1: minutes)"), (silence / 60).rounded()))
    }
}
