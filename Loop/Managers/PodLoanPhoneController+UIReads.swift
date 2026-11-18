//
//  PodLoanPhoneController+UIReads.swift
//  Loop
//
//  What the pump tile reads about a loan, from the live state on the main actor.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications

extension PodLoanPhoneController {
    /// The loan's state, for the Loop Report.
    func generateDiagnosticReport() -> String {
        let saved = persisted
        return [
            "## Sport Mode",
            "* phase: \(saved.phase)",
            "* loan: \(saved.epoch), started \(String(describing: saved.loanStartedAt))",
            "* standing aside for a loan started without this phone: \(saved.yieldingToInferredLoan)",
            "* watch last reported a cycle: \(String(describing: saved.holdRenewedAt))",
            "* took the pod back on silence: \(String(describing: saved.tookOverOnSilenceAt))",
            "* copy out for a start without the phone: \(saved.seizeToken != nil)",
            "* take-back insulin check owed: \(saved.pendingForceAudit != nil)",
            "* insulin estimates standing: \(saved.ledger.bookings.count)",
            "* automatic dosing held: \(holdsAutomaticDosing)",
        ].joined(separator: "\n")
    }

    /// Holds anchors, not elapsed values, so a stale snapshot still renders the right time.
    struct UISnapshot: Equatable {
        var isLoanedOut = false
        var isTakeoverInProgress = false
        var isSettlingOnly = false
        var takeBackStartedAt: Date?
        var isOwner = true
        var reclaimStartedAt: Date?
        var reclaimVerified = true
        var auditIsForceReclaim = false
        var displayAnchor: Date?
        /// During a loan: the phone's stores hold every carb and insulin record made by this time.
        var lastRecordsAt: Date?
    }

    func uiSnapshot() -> UISnapshot {
        var s = UISnapshot()

        // A yield counts as loaned out.
        s.isLoanedOut = state != .owner || yieldingToInferredLoan
        s.isTakeoverInProgress = state == .grantOffered
        s.isSettlingOnly = state == .owner && reclaimStartedAt != nil && reclaimVerifiedAt == nil
        s.takeBackStartedAt = state == .reclaimPending ? takeBackStartedAt : nil
        s.isOwner = state == .owner
        s.reclaimStartedAt = reclaimStartedAt
        s.reclaimVerified = reclaimVerifiedAt != nil
        s.auditIsForceReclaim = pendingHandbackAudit?.flavor == .forceReclaim
        s.displayAnchor = reclaimDisplayAnchor
        s.lastRecordsAt = s.isLoanedOut ? persisted.recordsCurrentAt : nil
        return s
    }

    /// What the screens read, built from the live state.
    var uiState: UISnapshot { uiSnapshot() }

    /// Pure: snapshot plus clock. Covers a take-back's reach for the pod and the settle after it.
    static func reclaimProgress(from s: UISnapshot, now: Date) -> ReclaimProgress? {
        if let started = s.takeBackStartedAt {
            let elapsed = max(now.timeIntervalSince(started), 0)
            return ReclaimProgress(phase: .reachingPod, startedAt: started,
                                   expectedBy: started.addingTimeInterval(Self.takeBackLinkLimit),
                                   fraction: min(elapsed / Self.takeBackLinkLimit, 0.95),
                                   elapsed: elapsed)
        }

        // The settle: owner again, round-trip not yet verified.
        if s.isOwner, let started = s.reclaimStartedAt, !s.reclaimVerified,
           now.timeIntervalSince(started) < Self.reclaimSettleTimeout {
            let elapsed = max(now.timeIntervalSince(started), 0)

            if s.auditIsForceReclaim {
                return ReclaimProgress(
                    phase: .forceReclaimingPod, startedAt: started,
                    expectedBy: started.addingTimeInterval(Self.reclaimSettleExpectation),
                    fraction: min(elapsed / Self.reclaimSettleExpectation, 0.95),
                    elapsed: elapsed)
            }

            // The display anchor survives a reopened window, so the bar does not restart.
            let anchor = s.displayAnchor ?? started
            let waitElapsed = max(now.timeIntervalSince(anchor), 0)
            return ReclaimProgress(
                phase: .reconnectingToPod, startedAt: anchor,
                expectedBy: anchor.addingTimeInterval(Self.reclaimSettleExpectation),
                fraction: min(waitElapsed / Self.reclaimSettleExpectation, 0.95),
                elapsed: waitElapsed)
        }
        return nil
    }

    var isLoanedOutForUI: Bool { return uiState.isLoanedOut }

    /// True across the reach and the settle, so the tile does not flicker between them.
    var isReclaimActivityForUI: Bool {
        let s = uiState
        return s.isSettlingOnly || s.takeBackStartedAt != nil
    }
    var isPodLoanedOutForUI: Bool { return uiState.isLoanedOut }
    var isPodTakeoverInProgressForUI: Bool { return uiState.isTakeoverInProgress }
    var lastRecordsAtForUI: Date? { return uiState.lastRecordsAt }
    var reclaimProgressForUI: ReclaimProgress? {
        return Self.reclaimProgress(from: uiState, now: Date())
    }

}
