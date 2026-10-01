//
//  DeviceDataManager+PodLoan.swift
//  Loop
//
//  The pod loan's read/act surface on DeviceDataManager: everything the UI asks about a loan,
//  and the one action it can take. Kept out of DeviceDataManager.swift so the stock file holds
//  only the `watchManager` back-reference these reads travel through.
//

import Foundation
import LoopKit

// MARK: - Pod loan (client API)

extension DeviceDataManager {
    /// Revoke the watch's loan and bring the pod home. Dosing stays paused until the records
    /// the watch is holding have been reconciled.
    func reclaimPodLoanFromWatch() {
        watchManager?.podLoanController.reclaimNow()
    }

    /// Any non-owner state — the pod is not this phone's to command.
    /// The TILE's read — never blocks on the loan queue. See `PodLoanPhoneController.UISnapshot`:
    /// this is drawn from the main thread, and a stalled reclaim holding that queue would freeze
    /// the whole interface behind it.
    var isPodLoanedToWatch: Bool {
        watchManager?.podLoanController.isPodLoanedOutForUI ?? false
    }

    /// Grant sent, takeover not yet confirmed: the outbound half of the handover.
    var isPodTakeoverInProgress: Bool {
        watchManager?.podLoanController.isPodTakeoverInProgressForUI ?? false
    }

    /// Actively coming home. Extends through the settle window — state can read `.owner` while
    /// the pod's BLE link is still re-establishing, and clearing the indicator at that instant
    /// would claim control the phone does not yet have.
    var isPodLoanReclaiming: Bool {
        watchManager?.podLoanController.isReclaimActivityForUI ?? false
    }

    var podReclaimProgress: PodLoanPhoneController.ReclaimProgress? {
        watchManager?.podLoanController.reclaimProgressForUI
    }
}
