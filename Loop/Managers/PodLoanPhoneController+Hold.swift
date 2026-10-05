//
//  PodLoanPhoneController+Hold.swift
//  Loop
//
//  Noticing a silent watch and warning. The phone never takes the pod back on a timer: a
//  live but unheard watch is still dosing, so taking it back stays the user's act.
//

import Foundation
import LoopKit

extension PodLoanPhoneController {
    /// Three missed cycles. Shorter than this and an ordinary late report reads as silence.
    static let watchSilenceThreshold: TimeInterval = .minutes(15)

    /// Grace before the first warning: one more cycle for a watch coming back into range.
    static let watchSilenceGrace: TimeInterval = .minutes(5)

    /// Warnings after the grace, then nothing. Repeating forever trains the user to ignore it.
    static let watchSilenceWarningOffsets: [TimeInterval] = [0, .minutes(20), .minutes(40)]

    /// The phone warns only if its own sensor reading is this fresh, i.e. it is near the user.
    static let nearTheBodyWindow: TimeInterval = .minutes(11)

    /// When the watch last reported a cycle. Persisted, so a relaunch is not read as silence.
    var holdRenewedAt: Date? {
        get { persisted.holdRenewedAt }
        set { updateState { $0.holdRenewedAt = newValue } }
    }

    /// When the silence was noticed; clearing it also resets the warning count.
    var holdLapseNoticedAt: Date? {
        get { persisted.holdLapseNoticedAt }
        set {
            updateState {
                $0.holdLapseNoticedAt = newValue
                if newValue == nil { $0.watchSilenceWarningsIssued = 0 }
            }
        }
    }

    /// How many of the warnings have gone out for this stretch of silence.
    private var watchSilenceWarningsIssued: Int {
        get { persisted.watchSilenceWarningsIssued }
        set { updateState { $0.watchSilenceWarningsIssued = newValue } }
    }

    /// The watch raises this user's glucose alerts while it has the pod and is being heard from: any
    /// loan, unless the phone has noticed the watch silent beside the body. Read on main by the
    /// phone's alert managers, so it never waits on the loan queue.
    var watchOwnsAlerts: Bool {
        isLoanedOutForUI && persisted.holdLapseNoticedAt == nil
    }

    /// An audit describes one loan, so every path that ends a loan clears its anchors.
    func clearAuditAnchors() {
        updateState { $0.audit = .init() }
    }

    /// Judged by send time: a batch that sat in a queue renews nothing.
    func noteHoldRenewal(sentAt: Date?) {
        let now = deps.now()
        let stamp = min(sentAt ?? now, now)
        // Never move the stamp backwards: batches can arrive out of order.
        guard stamp > (holdRenewedAt ?? .distantPast) else { return }
        holdRenewedAt = stamp
        if holdLapseNoticedAt != nil, now.timeIntervalSince(stamp) <= Self.watchSilenceThreshold {
            holdLapseNoticedAt = nil
            handbackDiag(epoch, "watch REPORTING again — the silence warning stands down; glucose alerts back to the watch")
        }
    }

    /// Called every phone cycle; almost always a no-op.
    func considerHoldLapse() {
        queue.async { self.queue_considerHoldLapse() }
    }

    func queue_considerHoldLapse() {
        // A loan the watch announced (phoneless start) counts too.
        let told = state == .owner && yieldingToInferredLoan
        let renewedAt = told ? [holdRenewedAt, newestForeignLoanEvidence?.at].compactMap { $0 }.max() : holdRenewedAt
        guard state == .loaned || state == .grantOffered || told, let renewed = renewedAt else {
            if holdLapseNoticedAt != nil { holdLapseNoticedAt = nil }
            return
        }
        let now = deps.now()
        let silence = now.timeIntervalSince(renewed)
        // Only near the body: away from the user a dead watch and a distant one look the same.
        guard silence > Self.watchSilenceThreshold,
              let reading = deps.latestGlucoseDate(), now.timeIntervalSince(reading) <= Self.nearTheBodyWindow else {
            if holdLapseNoticedAt != nil { holdLapseNoticedAt = nil }
            return
        }
        // First sight of the silence: start the clock, warn at the next cycle that still sees it.
        guard let noticed = holdLapseNoticedAt else {
            holdLapseNoticedAt = now
            handbackDiag(epoch, String(format: "watch SILENT — no report for %.0f min with this phone beside the body; glucose alerts back on this phone; first warning in %.0f min unless it reports",
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
