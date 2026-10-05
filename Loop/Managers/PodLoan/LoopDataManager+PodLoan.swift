//
//  LoopDataManager+PodLoan.swift
//  Loop
//
//  The loop at a loan boundary: cancel the other device's temp, and note when the watch's
//  insulin lands in the store. `isPumpConnectionReleased` gates pod commands during a loan.
//

import Foundation
import LoopKit
import LoopAlgorithm

extension LoopDataManager {

    /// Cancels the pod's temp once it is back. Not guarded on the cached delivery state, which
    /// is stale after a loan; the watch cannot do it because it has released the link.
    func cancelTempBasalAfterPodReturn() async throws {
        try await cancelTempBasalForPodLoan(reason: .pumpControlReturned)
    }

    /// A temp cancel outside loop() at a loan boundary, as stock's cancelActiveTempBasal does.
    func cancelTempBasalForPodLoan(reason: CancelActiveTempBasalReason) async throws {
        logger.default("Cancelling temp at the pod-loan boundary (%{public}@; cached basalDeliveryState was %{public}@)",
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

    /// The loan's insulin rewrote history from `date`; the next cycle reads it, so just refresh.
    func insulinHistoryRewritten(startingAt date: Date) {
        logger.default("Pod loan rewrote insulin history from %{public}@", String(describing: date))
        Task { await updateDisplayState() }
    }
}
