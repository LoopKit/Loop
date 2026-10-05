//
//  PodLoanPhoneController+UIReads.swift
//  Loop
//
//  What the pump tile reads about a loan. The UI reads a lock-guarded snapshot and never
//  `queue.sync`s: a stalled settle can hold the queue for minutes.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    /// Holds anchors, not elapsed values, so a stale snapshot still renders the right time.
    struct UISnapshot: Equatable {
        var isLoanedOut = false
        var isTakeoverInProgress = false
        var isSettlingOnly = false
        var ladderIsRunning = false
        var ladderStartedAt: Date?
        var ladderPhase: ReclaimProgress.Phase = .draining
        var ladderForceAt: Date?
        var isOwner = true
        var reclaimStartedAt: Date?
        var reclaimVerified = true
        var auditIsForceReclaim = false
        var displayAnchor: Date?
    }

    /// Must be called on the controller's queue — it reads the live state machine.
    func uiSnapshot() -> UISnapshot {
        var s = UISnapshot()

        // A yield counts as loaned out.
        s.isLoanedOut = state != .owner || yieldingToInferredLoan
        s.isTakeoverInProgress = state == .grantOffered
        s.isSettlingOnly = state == .owner && reclaimStartedAt != nil && reclaimVerifiedAt == nil
        if let ladder = reclaimLadder {
            s.ladderIsRunning = state == .reclaimPending || state == .reconciling
            s.ladderStartedAt = ladder.startedAt
            s.ladderPhase = ladder.phase
            s.ladderForceAt = ladder.forceAt
        }
        s.isOwner = state == .owner
        s.reclaimStartedAt = reclaimStartedAt
        s.reclaimVerified = reclaimVerifiedAt != nil
        s.auditIsForceReclaim = pendingHandbackAudit?.flavor == .forceReclaim
        s.displayAnchor = reclaimDisplayAnchor
        return s
    }

    /// Synchronous publish; transitions call it before notifying observers.
    func syncUIMirror() {
        let s = uiSnapshot()
        uiMirrorLock.lock()
        uiMirror = s
        uiMirrorLock.unlock()
    }

    /// Updates the mirror for the next read.
    func refreshUIMirror() {
        queue.async { [weak self] in
            guard let self else { return }
            let s = self.uiSnapshot()
            self.uiMirrorLock.lock()
            self.uiMirror = s
            self.uiMirrorLock.unlock()
        }
    }

    /// The UI's only entry point; never waits on the controller's queue.
    var uiState: UISnapshot {
        refreshUIMirror()
        uiMirrorLock.lock()
        defer { uiMirrorLock.unlock() }
        return uiMirror
    }

    /// Pure: snapshot plus clock. Covers the drain (ladder) and the settle after it.
    static func reclaimProgress(from s: UISnapshot, now: Date) -> ReclaimProgress? {
        if s.ladderIsRunning, let ladderStartedAt = s.ladderStartedAt {
            let elapsed = max(now.timeIntervalSince(ladderStartedAt), 0)

            var phase = s.ladderPhase
            var fraction: Double?
            // Only the drain has an expectation; overrun shows the force deadline instead.
            if phase == .draining {
                fraction = min(elapsed / Self.liveHandoverExpectation, 0.95)
                if elapsed >= Self.liveHandoverExpectation { phase = .watchNotAnswering }
            }
            return ReclaimProgress(phase: phase, startedAt: ladderStartedAt,
                                   expectedBy: phase == .draining
                                       ? ladderStartedAt.addingTimeInterval(Self.liveHandoverExpectation)
                                       : (s.ladderForceAt ?? ladderStartedAt),
                                   fraction: fraction,
                                   elapsed: elapsed)
        }

        // The settle: owner again, round-trip not yet verified.
        if s.isOwner, let started = s.reclaimStartedAt, !s.reclaimVerified,
           now.timeIntervalSince(started) < Self.reclaimSettleTimeout {
            let elapsed = max(now.timeIntervalSince(started), 0)

            // A force reclaim is worded as the phone taking the pod.
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

    /// True across the ladder and the settle, so the tile does not flicker between them.
    var isReclaimActivityForUI: Bool {
        let s = uiState
        return s.isSettlingOnly || s.ladderIsRunning
    }
    var isPodLoanedOutForUI: Bool { return uiState.isLoanedOut }
    var isPodTakeoverInProgressForUI: Bool { return uiState.isTakeoverInProgress }
    var reclaimProgressForUI: ReclaimProgress? {
        return Self.reclaimProgress(from: uiState, now: Date())
    }

}
