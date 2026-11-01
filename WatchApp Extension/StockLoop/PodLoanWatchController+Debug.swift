//
//  PodLoanWatchController+Debug.swift
//  StockLoop
//
//  Read-only views of the controller for the glance and debug page.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import WatchKit
import os.log

extension PodLoanWatchController {
    /// One consistent reading of the controller.
    struct DebugSnapshot {
        let phase: Phase
        let epoch: Int?
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
        let lastHeardFromPhoneAt: Date?
        let startNoteAt: Date?
        let startNoteText: String?

        let seizeOfferIssuedAt: Date?


        /// The wrist-up hint under the takeover bar, or nil; and whether it reports the pod reached.
        let takeoverHint: String?
        let takeoverPodReached: Bool
        /// Resting: the next Start must find a pump this watch has never met.
        let pumpFirstContactExpected: Bool
    }

    var isLoanActive: Bool {
        phase == .active
    }

    /// Taking over, live, handing back, draining or resuming: the phone has left the alarms here.
    var wristOwnsAlarms: Bool {
        [.takingOver, .active, .handingBack, .recoveredDrain].contains(phase)
    }

    func debugSnapshot() -> DebugSnapshot {
        return DebugSnapshot(
                phase: phase,
                epoch: epoch ?? journal.activeEpoch,
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
                lastHeardFromPhoneAt: lastHeardFromPhoneAt,
                startNoteAt: startNote?.at,
                startNoteText: startNote?.text,
                seizeOfferIssuedAt: seizeOffer?.issuedAt,
                takeoverHint: phase == .takingOver
                    ? Self.takeoverHint(firstContact: takeoverFirstContact, podReached: takeoverPodReached, nudged: takeoverNudges > 0)
                    : nil,
                takeoverPodReached: phase == .takingOver && takeoverPodReached,
                pumpFirstContactExpected: pumpFirstContactExpected())
    }

    /// nil: no pump manager, as opposed to a failed read.
    func debugReadStatus(completion: @escaping (Bool?) -> Void) {
        DispatchQueue.main.async {
            guard let odometer = self.pumpOdometer else { completion(nil); return }
            Task { completion(await odometer.refreshDeliveredUnits()) }
        }
    }

}
