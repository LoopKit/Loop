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

    /// While the pod is away the watch uploads glucose to the remote services, and the phone none.
    var podLoanHoldsGlucoseUploads: Bool {
        isPodLoanedToWatch
    }

    /// Moves these remote services' glucose bookmarks past what the store holds now, without
    /// uploading it: the watch confirmed it uploaded the loan's readings to them.
    func skipLoanGlucoseUploads(services identifiers: Set<String>) {
        let services = allActivePlugins.compactMap { $0 as? RemoteDataService }.filter { identifiers.contains($0.pluginIdentifier) }
        let glucoseStore = self.glucoseStore
        Task {
            for service in services {
                let saved: GlucoseStore.QueryAnchor? = UserDefaults.appGroup?.getQueryAnchor(for: service, withRemoteDataType: .glucose)
                guard let (anchor, skipped) = try? await glucoseStore.executeGlucoseQuery(fromQueryAnchor: saved ?? GlucoseStore.QueryAnchor(), limit: Int.max) else { continue }
                UserDefaults.appGroup?.setQueryAnchor(for: service, withRemoteDataType: .glucose, anchor)
                PhoneLog.event("uploads", "\(service.pluginIdentifier): skipped \(skipped.count) loan-window glucose reading(s) — the watch uploaded them")
            }
        }
    }

    /// Moves these services' dosing-decision bookmarks past the watch's decisions just added, which
    /// the watch confirmed it uploaded to them; stops at the first decision that is not one of them.
    func skipLoanDosingDecisionUploads(_ ids: Set<UUID>, in store: DosingDecisionStore, services identifiers: Set<String>) async {
        for service in allActivePlugins.compactMap({ $0 as? RemoteDataService }) where identifiers.contains(service.pluginIdentifier) {
            var anchor: DosingDecisionStore.QueryAnchor? = UserDefaults.appGroup?.getQueryAnchor(for: service, withRemoteDataType: .dosingDecision)
            var skipped = 0
            while true {
                let next: (DosingDecisionStore.QueryAnchor, [StoredDosingDecision])? = await withCheckedContinuation { continuation in
                    store.executeDosingDecisionQuery(fromQueryAnchor: anchor, limit: 1) { result in
                        if case .success(let anchor, let decisions) = result { continuation.resume(returning: (anchor, decisions)) } else { continuation.resume(returning: nil) }
                    }
                }
                guard let (nextAnchor, decisions) = next, let decision = decisions.first, ids.contains(decision.id) else { break }
                anchor = nextAnchor
                skipped += 1
            }
            if let anchor { UserDefaults.appGroup?.setQueryAnchor(for: service, withRemoteDataType: .dosingDecision, anchor) }
            PhoneLog.event("uploads", "\(service.pluginIdentifier): skipped \(skipped) of the watch's \(ids.count) loop status record(s) — the watch uploaded them")
        }
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
