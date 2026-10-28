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
import LoopCore
import UIKit

// MARK: - Pod loan (client API)

extension DeviceDataManager {
    /// nil with the flag off, so every read below is stock's "no loan" and nothing builds the controller.
    private var podLoanController: PodLoanPhoneController? {
        FeatureFlags.sportModeEnabled ? watchManager?.podLoanController : nil
    }

    /// A push from a watch that started a loan without this phone; false for anything else, which goes
    /// to the services. The phone stays awake a few seconds so standing aside completes.
    func podLoanHandlesPush(_ notification: [String: AnyObject]) -> Bool {
        guard LoanPush.isLoanPush(notification) else { return false }
        guard FeatureFlags.sportModePushEnabled, let controller = podLoanController else {
            PhoneLog.event("push", "push from the watch ignored: the feature is off in this build")
            return true
        }
        guard let push = LoanPush(userInfo: notification) else {
            PhoneLog.event("push", "push from the watch ignored: unreadable")
            return true
        }
        let task = UIApplication.shared.beginBackgroundTask(withName: "LoanPush")
        controller.handlePush(push)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            UIApplication.shared.endBackgroundTask(task)
        }
        return true
    }

    /// The loan's state for the Loop Report; nothing with Sport Mode off.
    var podLoanDiagnosticReport: [String] {
        guard let controller = podLoanController else { return [] }
        return ["", controller.generateDiagnosticReport()]
    }

    /// During a loan the watch raises the glucose alerts; never blocks.
    var podLoanWatchOwnsAlerts: Bool {
        podLoanController?.watchOwnsAlerts ?? false
    }

    /// Every pump report closes the loan ledger's open window before the report completes, so the
    /// cycle the reading feeds sees anything it books.
    func podLoanPumpDidReport() async {
        guard let controller = podLoanController else { return }
        await withCheckedContinuation { done in controller.checkOwnPumpTotal { done.resume() } }
    }

    /// Revoke the watch's loan and bring the pod home. Dosing stays paused until the records
    /// the watch is holding have been reconciled.
    func reclaimPodLoanFromWatch() {
        podLoanController?.takeBackTapped()
    }

    /// The loop's loan gate; with the flag off, only the pump's own release.
    var holdsAutomaticDosingForPodLoan: Bool {
        podLoanController?.holdsAutomaticDosing ?? ((pumpManager as? ExclusiveDeviceControl)?.isControlReleased ?? false)
    }

    /// Any non-owner state. Never blocks on the loan queue: the tile draws from main.
    var isPodLoanedToWatch: Bool {
        podLoanController?.isPodLoanedOutForUI ?? false
    }

    /// During a loan, when the watch's records last arrived.
    var podLoanLastRecordsAt: Date? {
        podLoanController?.lastRecordsAtForUI
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
