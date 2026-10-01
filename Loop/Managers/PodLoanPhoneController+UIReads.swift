//
//  PodLoanPhoneController+UIReads.swift
//  Loop
//
//  Part of PodLoanPhoneController (see PodLoanPhoneController.swift). Split by concern; stored
//  properties live in the core class.
//
//  Everything the pump tile reads about a loan, and the one rule that governs it: the UI takes a
//  lock-guarded snapshot and NEVER `queue.sync`s onto the controller's serial queue. A settle
//  that stalls holds that queue for minutes, and a tile waiting behind it freezes the whole app
//  on the main thread.
//
//  The snapshot therefore stores the reclaim's INPUTS, not a rendered progress value, and
//  `reclaimProgress(from:now:)` re-derives against a fresh clock. The elapsed counter keeps
//  ticking truthfully even while the queue is wedged.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import UserNotifications
import os.log

extension PodLoanPhoneController {
    /// A plain value copy of the loan state the tile draws. No dates are pre-differenced here;
    /// holding the anchors instead lets a stale snapshot still render a correct elapsed time.
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

        // A yield counts as loaned out even though the state is .owner: the phone has stood
        // aside for a loan it did not grant, and the tile must say so.
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

    /// Publish the mirror synchronously. Every transition the tile draws calls this BEFORE it
    /// notifies observers: the async refresh alone loses the race, so the re-render reads the
    /// previous state and nothing renders again afterwards.
    func syncUIMirror() {
        let s = uiSnapshot()
        uiMirrorLock.lock()
        uiMirror = s
        uiMirrorLock.unlock()
    }

    /// Asynchronous republish, for reads that arrive from outside the queue. It updates the
    /// mirror for the NEXT read, which is why every state transition also publishes
    /// synchronously.
    func refreshUIMirror() {
        queue.async { [weak self] in
            guard let self else { return }
            let s = self.uiSnapshot()
            self.uiMirrorLock.lock()
            self.uiMirror = s
            self.uiMirrorLock.unlock()
        }
    }

    /// The UI's only door. It kicks off a refresh for next time and returns what is already
    /// published, so a caller on main never waits on the controller's queue.
    var uiState: UISnapshot {
        refreshUIMirror()
        uiMirrorLock.lock()
        defer { uiMirrorLock.unlock() }
        return uiMirror
    }

    /// Derives what the tile shows from a snapshot plus a clock, and nothing else. Static and
    /// value-only on purpose: the settle predicate is restated inline below rather than calling
    /// `isReclaimSettling`, which would dispatch onto the controller's serial queue.
    ///
    /// Two stretches can be in progress. The ladder covers the watch draining and handing back;
    /// the settle afterwards covers the phone re-establishing the pod link and reading it.
    static func reclaimProgress(from s: UISnapshot, now: Date) -> ReclaimProgress? {
        if s.ladderIsRunning, let ladderStartedAt = s.ladderStartedAt {
            let elapsed = max(now.timeIntervalSince(ladderStartedAt), 0)

            var phase = s.ladderPhase
            var fraction: Double?
            // Only the drain has an expectation to measure against. Once it is overrun the bar
            // stops pretending to know: the phase becomes "watch not answering" and the UI shows
            // the force deadline instead. Fractions cap below 1 so nothing reads as finished
            // before it is.
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

        // The settle: .owner again, but the pod round-trip that proves it has not landed yet.
        // Past the ceiling the controller has given up, so the tile stops showing progress too.
        if s.isOwner, let started = s.reclaimStartedAt, !s.reclaimVerified,
           now.timeIntervalSince(started) < Self.reclaimSettleTimeout {
            let elapsed = max(now.timeIntervalSince(started), 0)

            // Same one-stage expectation either way; only the wording differs, because after a
            // force reclaim the user did not hand the pod back and should be told the phone is
            // taking it.
            if s.auditIsForceReclaim {
                return ReclaimProgress(
                    phase: .forceReclaimingPod, startedAt: started,
                    expectedBy: started.addingTimeInterval(Self.reclaimSettleExpectation),
                    fraction: min(elapsed / Self.reclaimSettleExpectation, 0.95),
                    elapsed: elapsed)
            }

            // Measure from the display anchor, which survives a settle window re-opening a
            // moment after the last one closed. Restarting the bar there would tell the user
            // the wait had begun again when it had not.
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

    /// True through both halves of a take-back — the ladder and the settle after it — so the
    /// tile does not flicker back to a finished state in the gap between them.
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
