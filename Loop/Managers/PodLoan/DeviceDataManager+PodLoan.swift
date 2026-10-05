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
    /// nil with the flag off, so every read below is stock's "no loan" and nothing builds the controller.
    private var podLoanController: PodLoanPhoneController? {
        FeatureFlags.sportModeEnabled ? watchManager?.podLoanController : nil
    }

    /// During a loan the watch raises the glucose alerts; never blocks.
    var podLoanWatchOwnsAlerts: Bool {
        podLoanController?.watchOwnsAlerts ?? false
    }

    /// Revoke the watch's loan and bring the pod home. Dosing stays paused until the records
    /// the watch is holding have been reconciled.
    func reclaimPodLoanFromWatch() {
        podLoanController?.reclaimNow()
    }

    /// The loop's loan gate; with the flag off, only the pump's own release.
    var holdsAutomaticDosingForPodLoan: Bool {
        podLoanController?.holdsAutomaticDosing ?? ((pumpManager as? ExclusiveDeviceControl)?.isControlReleased ?? false)
    }

    /// Any non-owner state. Never blocks on the loan queue: the tile draws from main.
    var isPodLoanedToWatch: Bool {
        podLoanController?.isPodLoanedOutForUI ?? false
    }

    /// Grant sent, takeover not yet confirmed: the outbound half of the handover.
    var isPodTakeoverInProgress: Bool {
        podLoanController?.isPodTakeoverInProgressForUI ?? false
    }

    /// Includes the settle window, while the pod's link is still coming back.
    var isPodLoanReclaiming: Bool {
        podLoanController?.isReclaimActivityForUI ?? false
    }

    var podReclaimProgress: PodLoanPhoneController.ReclaimProgress? {
        podLoanController?.reclaimProgressForUI
    }
}
