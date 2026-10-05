//
//  DeviceDataManager+PodLoanStatus.swift
//  Loop
//
//  The pump tile while the pod is on the watch or moving between devices; the stock chain in
//  DeviceDataManager+DeviceStatus.swift asks `podLoanStatusHighlight` after its own first checks.
//

import Foundation
import LoopKit
import LoopKitUI

extension DeviceDataManager {

    /// nil when the pod is plainly the phone's, so the pump manager's own highlight shows.
    var podLoanStatusHighlight: DeviceStatusHighlight? {
        if isPodLoanReclaiming {
            // Hand-back in flight; the label follows the reclaim's phase.
            return Self.podReclaimingStatusHighlight(phase: podReclaimProgress?.phase)
        } else if isPodTakeoverInProgress {
            // Grant out, not yet confirmed. Must precede the next branch: the link is already released.
            return Self.podHandingOverStatusHighlight
        } else if (pumpManager as? ExclusiveDeviceControl)?.isControlReleased == true || isPodLoanedToWatch {
            // On the watch: switch the tile at release rather than waiting for signal loss.
            return Self.podOnWatchStatusHighlight
        }
        return nil
    }

    static var podOnWatchStatusHighlight: PodOnWatchStatusHighlight {
        return PodOnWatchStatusHighlight()
    }

    struct PodOnWatchStatusHighlight: DeviceStatusHighlight {
        var localizedMessage: String = NSLocalizedString("Pod on Watch", comment: "Title text for the pump tile while the pod is loaned to the watch")
        var imageName: String = "applewatch"
        var state: DeviceStatusHighlightState = .normalPump
    }

    static var podHandingOverStatusHighlight: PodHandingOverStatusHighlight {
        return PodHandingOverStatusHighlight()
    }


    /// "Handing over" on the phone while the watch says "taking over": each side narrates its own half.
    struct PodHandingOverStatusHighlight: DeviceStatusHighlight {
        var localizedMessage: String = NSLocalizedString("Handing over…", comment: "Title text for the pump tile while the pod is being handed over to the watch")
        var imageName: String = "arrow.triangle.2.circlepath"
        var state: DeviceStatusHighlightState = .normalPump
    }

    static func podReclaimingStatusHighlight(phase: PodLoanPhoneController.ReclaimProgress.Phase?) -> PodReclaimingStatusHighlight {
        return PodReclaimingStatusHighlight(phase: phase)
    }

    struct PodReclaimingStatusHighlight: DeviceStatusHighlight {
        var localizedMessage: String
        var imageName: String = "arrow.triangle.2.circlepath"
        var state: DeviceStatusHighlightState = .normalPump

        /// nil phase: inside the drain's store commit, which has no deadline to name.
        init(phase: PodLoanPhoneController.ReclaimProgress.Phase? = nil) {
            switch phase {
            case .forcing?, .forceReclaimingPod?:
                // One label for the force and the settle after it.
                localizedMessage = NSLocalizedString("Forcing…", comment: "Title text for the pump tile while the phone force-reclaims the pod")
            case .reconnectingToPod?, .draining?:
                // The same label across handover and settle: one wait, one bar.
                localizedMessage = NSLocalizedString("Reclaiming…", comment: "Title text for the pump tile while the pod is coming back from the watch")
            case .watchNotAnswering?:
                localizedMessage = NSLocalizedString("No watch reply…", comment: "Title text for the pump tile when the watch has not answered within the drain promise")
            case .none:
                localizedMessage = NSLocalizedString("Reclaiming…", comment: "Title text for the pump tile while the pod is coming back from the watch")
            }
        }
    }

    /// The reclaim's progress; nil lets the stock lifecycle progress show.
    var podLoanLifecycleProgress: DeviceLifecycleProgress? {
        // Uses the tile's own progress bar, capped at 0.95 on overrun.
        if let progress = podReclaimProgress, let fraction = progress.fraction {
            return PodReclaimLifecycleProgress(percentComplete: fraction)
        }
        return nil
    }

    struct PodReclaimLifecycleProgress: DeviceLifecycleProgress {
        var percentComplete: Double
        var progressState: DeviceLifecycleProgressState = .normalPump
    }
}
