//
//  DeviceDataManager+PodLoanStatus.swift
//  Loop
//
//  What the pump tile shows while the pod is on the watch: the three loan highlights and the
//  reclaim's progress bar. The branches that CHOOSE between them stay in the stock chain in
//  DeviceDataManager+DeviceStatus.swift — their order is the decision; these are the answers.
//

import Foundation
import LoopKit
import LoopKitUI

extension DeviceDataManager {

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


    /// The outbound twin of `PodReclaimingStatusHighlight` — same in-transit idiom, same symbol,
    /// opposite direction.
    ///
    /// "HANDING over", deliberately, while the watch says "taking over" for the same instant:
    /// each device narrates the handover from its own side, so a user glancing between them reads
    /// one event from two viewpoints rather than the same words twice. The state predicates keep
    /// the protocol's vocabulary (`isPodTakeoverInProgress`) — it is one takeover either way;
    /// only the label is perspectival.
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

        /// nil phase = the reclaim is inside the drain's store commit, which has no deadline to
        /// name; plain "Reclaiming…" is the honest label for it.
        ///
        /// NO elapsed counter (lean ruling, 2026-08-23). The climbing seconds were the right
        /// honesty for a settle that ranged 4-190 s — you cannot promise a duration you do not
        /// know, so you show elapsed instead. With settles in a tight 5-10 s band the counter
        /// narrated a wait too short to read, and the deterministic bar behind the label is now
        /// truthful nearly every time; the rare overrun holds near-full until the verify lands.
        init(phase: PodLoanPhoneController.ReclaimProgress.Phase? = nil) {
            switch phase {
            case .forcing?, .forceReclaimingPod?:
                // One label across the force rung AND the settle that follows it, so the force
                // reads as a single operation rather than a chain of renamed waits.
                localizedMessage = NSLocalizedString("Forcing…", comment: "Title text for the pump tile while the phone force-reclaims the pod")
            case .reconnectingToPod?, .draining?:
                // Same string across the handover/settle boundary on purpose: to the user a
                // live reclaim is ONE wait behind one continuous bar.
                localizedMessage = NSLocalizedString("Reclaiming…", comment: "Title text for the pump tile while the pod is coming back from the watch")
            case .watchNotAnswering?:
                localizedMessage = NSLocalizedString("No watch reply…", comment: "Title text for the pump tile when the watch has not answered within the drain promise")
            case .none:
                localizedMessage = NSLocalizedString("Reclaiming…", comment: "Title text for the pump tile while the pod is coming back from the watch")
            }
        }
    }

    /// The reclaim's share of the pump tile's progress bar; nil whenever no reclaim is running,
    /// so the stock lifecycle progress shows through.
    var podLoanLifecycleProgress: DeviceLifecycleProgress? {
        // A live reclaim's deterministic bar rides the tile's NATIVE progress mechanism —
        // the same element stock uses for pod expiry — instead of custom UI. The elapsed
        // counter this replaces was removed 2026-08-23 (it narrated waits too short to read),
        // which left "Reclaiming…" with no motion at all; a bar filling against the 10 s
        // promise is the calm version of the same honesty. Cap-and-hold semantics come from
        // the fraction itself (0.95 on overrun, ceiling still the 5-minute backstop).
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
