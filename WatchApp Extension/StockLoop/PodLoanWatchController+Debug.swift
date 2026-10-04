//
//  PodLoanWatchController+Debug.swift
//  StockLoop
//
//  Read-only views of the controller for the glance and debug page. Main never syncs onto the
//  loan queue (also the pump's delegate queue); it reads the mirrors published from it.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController {
    /// One consistent reading, taken on the queue.
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

        /// The wrist-up hint under the takeover bar, or nil; and whether it reports the pod reached.
        let takeoverHint: String?
        let takeoverPodReached: Bool
        /// Resting: the next Start must find a pump this watch has never met.
        let pumpFirstContactExpected: Bool
    }

    /// Blocking. Not for main — `isLoanActiveNonBlocking` is main's answer.
    var isLoanActive: Bool {
        RuntimeStateLog.markBlockingIfMain("blocking.isLoanActive")
        defer { RuntimeStateLog.markBlockingIfMain("blocking.isLoanActive.done") }
        return queue.sync { phase == .active }
    }

    /// Safe on main; mirrored in `phase.didSet`.
    var isLoanActiveNonBlocking: Bool {
        loanActiveMirrorLock.lock()
        defer { loanActiveMirrorLock.unlock() }
        return _loanActiveMirror
    }

    /// A saved loan is still being rebuilt.
    var wristOwnsAlarmsNonBlocking: Bool {
        loanActiveMirrorLock.lock()
        defer { loanActiveMirrorLock.unlock() }
        return _wristAlarmsMirror
    }

    var isResumingNonBlocking: Bool {
        loanActiveMirrorLock.lock()
        defer { loanActiveMirrorLock.unlock() }
        return _resumingMirror
    }

    /// The last published snapshot; may be one refresh stale.
    var mirroredDebugSnapshot: DebugSnapshot? {
        snapshotMirrorLock.lock()
        defer { snapshotMirrorLock.unlock() }
        return _snapshotMirror
    }

    /// Builds and publishes a snapshot; the caller reads the mirror next pass.
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
                deliveredUnits: pumpOdometer?.deliveredUnits?.units,
                podFault: pumpFaultDescription,
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
                reunionPromptVisible: reunionPromptActive,
                takeoverHint: phase == .takingOver
                    ? Self.takeoverHint(firstContact: takeoverFirstContact, podReached: takeoverPodReached, nudged: takeoverNudges > 0)
                    : nil,
                takeoverPodReached: phase == .takingOver && takeoverPodReached,
                pumpFirstContactExpected: pumpFirstContactExpected())
    }

    /// nil: no pump manager, as opposed to a failed read.
    func debugReadStatus(completion: @escaping (Bool?) -> Void) {
        queue.async {
            guard let odometer = self.pumpOdometer else { completion(nil); return }
            odometer.refreshDeliveredUnits { ok in completion(ok) }
        }
    }

}
