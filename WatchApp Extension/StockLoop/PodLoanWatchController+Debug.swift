//
//  PodLoanWatchController+Debug.swift
//  StockLoop
//
//  Part of PodLoanWatchController (see PodLoanWatchController.swift). Split by concern; stored properties live in the core class.
//
//  Read-only views of the controller, for the glance and the debug page.
//
//  MAIN MUST NEVER SYNC ONTO THE LOAN QUEUE. That queue is also the pump manager's delegate
//  queue, so anything waiting on it waits for the length of a bolus, a takeover or a reclaim —
//  long enough for watchOS to kill the app for a wedged main thread. Main reads the lock-guarded
//  mirrors here, which are published FROM the queue; the blocking variants are for callers that
//  are already off main.
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
    /// One consistent reading of the controller, taken on its queue. Everything the debug page
    /// and the glance need is captured here rather than fetched field by field, so what they draw
    /// cannot mix two different moments.
    struct DebugSnapshot {
        let phase: Phase
        let epoch: Int?
        let mode: LoanDosingMode
        let hasPumpManager: Bool
        let deliveredUnits: Double?
        let podFault: String?
        let lastEventSeq: Int
        let unackedCount: Int
        let lastIdleNote: String?

        let startedAt: Date?

        let handbackPending: Bool

        let handbackStartedAt: Date?

        let phoneReachable: Bool

        let handbackFailedAt: Date?
        let handbackFailureText: String?
        let startNoteAt: Date?
        let startNoteText: String?

        let seizeOfferIssuedAt: Date?

        let reunionPromptVisible: Bool
    }

    /// Blocking. Not for main — `isLoanActiveNonBlocking` is main's answer.
    var isLoanActive: Bool {
        RuntimeStateLog.markBlockingIfMain("blocking.isLoanActive")
        defer { RuntimeStateLog.markBlockingIfMain("blocking.isLoanActive.done") }
        return queue.sync { phase == .active }
    }

    /// Whether the pod will beep for a manual bolus. The glance suppresses its own success haptic
    /// when it will: the pod's acknowledgement fires at the same instant and says the same thing.
    var podBeepsOnManualBolus: Bool {
        pumpManager?.podLoanBeepsOnManualBolus ?? false
    }

    /// Safe on main at any time. Mirrored synchronously inside `phase.didSet`, so a UI action
    /// taken immediately after a transition sees the value that transition set.
    var isLoanActiveNonBlocking: Bool {
        loanActiveMirrorLock.lock()
        defer { loanActiveMirrorLock.unlock() }
        return _loanActiveMirror
    }

    /// True between a launch discovering a saved loan and the rebuild finishing. The stock pages
    /// use it to distinguish "no loan" from "a loan that is still being rebuilt".
    var isResumingNonBlocking: Bool {
        loanActiveMirrorLock.lock()
        defer { loanActiveMirrorLock.unlock() }
        return _resumingMirror
    }

    /// The last snapshot published from the loan queue, or nil before the first refresh. It can
    /// be one refresh stale; that is the price of never blocking main.
    var mirroredDebugSnapshot: DebugSnapshot? {
        snapshotMirrorLock.lock()
        defer { snapshotMirrorLock.unlock() }
        return _snapshotMirror
    }

    /// Build a snapshot on the queue and publish it. The debug page ticks this and then reads
    /// the mirror on the next pass; it never waits for the queue.
    func refreshDebugSnapshot() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let snap = self.buildDebugSnapshot()
            self.snapshotMirrorLock.lock()
            self._snapshotMirror = snap
            self.snapshotMirrorLock.unlock()
        }
    }

    /// Blocking snapshot, for callers already off main (tests, queue-side logging).
    func debugSnapshot() -> DebugSnapshot {
        RuntimeStateLog.markBlockingIfMain("blocking.debugSnapshot")
        defer { RuntimeStateLog.markBlockingIfMain("blocking.debugSnapshot.done") }
        return queue.sync { buildDebugSnapshot() }
    }

    /// Must run ON the queue — it reads the phase, the journal and the pump manager unguarded.
    private func buildDebugSnapshot() -> DebugSnapshot {
        return DebugSnapshot(
                phase: phase,
                epoch: epoch ?? journal.activeEpoch,
                mode: currentMode(),
                hasPumpManager: pumpManager != nil,
                deliveredUnits: pumpManager?.podLoanInsulinDelivered,
                podFault: pumpManager?.podLoanFaultDescription,
                lastEventSeq: journal.lastEventSeq,
                unackedCount: journal.unackedEvents().count,
                lastIdleNote: lastIdleNote,
                startedAt: attemptStartedAt,
                handbackPending: handbackRequested,
                handbackStartedAt: handbackStartedAt,
                phoneReachable: isPhoneReachable(),
                handbackFailedAt: handbackFailure?.at,
                handbackFailureText: handbackFailure?.text,
                startNoteAt: startNote?.at,
                startNoteText: startNote?.text,
                seizeOfferIssuedAt: seizeOffer?.issuedAt,
                reunionPromptVisible: reunionPromptActive)
    }

    /// Force a pod status read from the debug page. nil means there is no pump manager at all,
    /// which is a different answer from a read that was attempted and failed.
    func debugReadStatus(completion: @escaping (Bool?) -> Void) {
        queue.async {
            guard let manager = self.pumpManager else { completion(nil); return }
            manager.podLoanReadStatus { ok in completion(ok) }
        }
    }

}
