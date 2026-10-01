//
//  LoopDataManager+PodLoan.swift
//  Loop
//
//  What the loop does at a pod-loan boundary: cancel the temp the other device left running,
//  and take notice when the watch's insulin lands in the store.
//
//  `isPumpConnectionReleased` is a stored property and so stays on LoopDataManager. Its
//  rationale, verbatim from where it was written:
//
//  True while the pod's BLE connection is loaned out (or being released) — no pod
//  command can succeed then, and a doomed cancel strands CrashRecoveryManager's
//  in-flight marker (stock never disarms it on a thrown enact). Injected at wiring;
//  defaults false so tests and non-loan configurations are unaffected.
//

import Foundation
import LoopKit
import LoopAlgorithm

extension LoopDataManager {

    /// Cancel whatever temp the pod is running now that it is back under this phone's control.
    ///
    /// Deliberately NOT guarded on `basalDeliveryState == .tempBasal` the way the general
    /// version above is. That guard is exactly what makes a post-loan cancel dead code: while
    /// the watch held the pod this phone enacted nothing, so its cached delivery state is
    /// whatever it was before the loan, and the pod's real program is only knowable from the
    /// pod. A redundant cancel costs one round-trip on a link we are already holding and moves
    /// toward less insulin; a skipped cancel leaves someone else's temp running.
    ///
    /// It is the phone that does this rather than the watch because the watch cannot reach the
    /// pod at hand-back — it releases the BLE link between dose windows, so its cancel fails in
    /// about a millisecond with podNotConnected. The phone is holding a verified round-trip at
    /// the moment this is called.
    func cancelTempBasalAfterPodReturn() async throws {
        try await cancelTempBasalForPodLoan(reason: .podReturnedFromWatch)
    }

    /// PUMPLOAN: a bare temp cancel outside loop(), at a loan boundary — before the pod is lent
    /// (`.podLoanGrant`) and after it returns (`.podReturnedFromWatch`). Stock's own off-cycle
    /// cancel idiom (see cancelActiveTempBasal), with the loan's reason on the dosing decision.
    func cancelTempBasalForPodLoan(reason: CancelActiveTempBasalReason) async throws {
        logger.default("PODLOAN: cancelling temp at the loan boundary (%{public}@; cached basalDeliveryState was %{public}@)",
                       reason.rawValue, String(describing: deliveryDelegate?.basalDeliveryState))

        let recommendation = AutomaticDoseRecommendation(basalAdjustment: .cancel, direction: .decrease)
        var dosingDecision = StoredDosingDecision(reason: reason.rawValue)
        dosingDecision.settings = StoredDosingDecision.Settings(settingsProvider.settings)
        dosingDecision.automaticDoseRecommendation = recommendation

        do {
            try await deliveryDelegate?.enact(bolus: recommendation.bolusUnits,
                                              tempBasal: recommendation.basalAdjustment,
                                              decisionId: dosingDecision.id)
        } catch {
            dosingDecision.appendError(error as? LoopError ?? .unknownError(error))
            await dosingDecisionStore.storeDosingDecision(dosingDecision)
            throw error
        }

        await dosingDecisionStore.storeDosingDecision(dosingDecision)
        await updateDisplayState(forceStoreRemoteRecommendation: true)
    }

    /// The loan's insulin has landed in the store and rewritten history from `date`.
    ///
    /// On the old stateful loop this had to drop cached effects. The algorithm holds nothing
    /// between runs, so the next cycle reads the rewritten books by itself and this only has to
    /// refresh what is displayed.
    func insulinHistoryRewritten(startingAt date: Date) {
        logger.default("PODLOAN: insulin history rewritten from %{public}@", String(describing: date))
        Task { await updateDisplayState() }
    }
}
