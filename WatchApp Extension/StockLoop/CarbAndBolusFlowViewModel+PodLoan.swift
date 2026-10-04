//
//  CarbAndBolusFlowViewModel+PodLoan.swift
//  WatchApp Extension
//
//  The carb and bolus flow while the wrist holds the pod: recommend from the watch's books,
//  clamp to the grant, deliver on the watch's pump.
//

import Foundation
import LoopKit
import LoopCore
import LoopAlgorithm
import UserNotifications
import WatchKit

extension CarbAndBolusFlowViewModel {

    /// During a loan the grant's maximum; the phone's relayed value can be stale.
    static func activeMaxBolus(_ loopManager: LoopDataManager) -> Double {
        if let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
           session.loanController.isLoanActiveNonBlocking,
           let granted = session.stack.loopManager.grantedMaximumBolus {
            return granted
        }
        return loopManager.watchInfo.loopSettings.maximumBolus ?? Self.defaultMaxBolus
    }

    /// Shared so a verdict path can retract this once the pod's answer is in.
    nonisolated static let bolusUnconfirmedNotificationID = "loan.bolus.failure"

    /// A bolus that never reached the pod is silent, so the failure is announced.
    nonisolated private static func notifyBolusFailure(units: Double, carbGrams: Double?, error: Swift.Error) {
        let content = UNMutableNotificationContent()
        let unitsText = NumberFormatter.localizedString(from: NSNumber(value: units), number: .decimal)
        content.title = String(
            format: NSLocalizedString("Bolus Unconfirmed: %@ U", comment: "Watch notification title for a loan-time bolus whose delivery could not be confirmed (1: units)"),
            unitsText)
        if let carbGrams = carbGrams {
            content.body = String(
                format: NSLocalizedString("%@ g was saved. Loop couldn't confirm delivery. You can wait to see if it resolves.", comment: "Watch notification body when carbs were saved but bolus delivery is unconfirmed (1: grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: Int(carbGrams.rounded())), number: .none))
        } else {
            // The error text goes to the log only.
            content.body = NSLocalizedString("Loop couldn't confirm delivery. You can wait to see if it resolves.", comment: "Watch notification body when a loan-time bolus delivery is unconfirmed")
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.bolusUnconfirmedNotificationID, content: content, trigger: nil))
    }

    /// Local recommendation during a loan; a failure is announced, not left as a 0 dial.
    func recommendLoanBolus(with entry: NewCarbEntry?, session: StockLoopSession) async {
        isComputingRecommendedBolus = true
        defer { isComputingRecommendedBolus = false }

        let result: Swift.Result<ManualBolusRecommendation, Swift.Error> = await withCheckedContinuation { continuation in
            session.stack.loopManager.recommendManualBolus(potentialCarbEntry: entry) { result in
                continuation.resume(returning: result)
            }
        }

        // Superseded: the carbs under consideration changed.
        guard entry == carbEntryUnderConsideration else { return }

        switch result {
        case .success(let recommendation):
            SportLog.event("bolus-ui", String(format: "REC carb %.0fg (watch-local): %.2f U",
                                              entry?.quantity.doubleValue(for: .gram) ?? 0,
                                              recommendation.amount))
            if recommendedBolusAmount != recommendation.amount {
                recommendedBolusAmount = recommendation.amount
            }
        case .failure(let error):
            SportLog.event("bolus-ui", "REC carb (watch-local) FAILED — \(error) · dial stays 0, button reads Save")
            recommendedBolusAmount = nil
        }
    }

    /// Called from `sendSetBolusUserInfo(carbEntry:bolus:)` while a loan is live.
    func podLoanDeliverOnWrist(carbEntry: NewCarbEntry?, bolus: Double, session: StockLoopSession) {
        let activationType: BolusActivationType = .activationTypeFor(recommendedAmount: recommendedBolusAmount, bolusAmount: bolus)
        Self.podLoanDeliver(carbEntry: carbEntry, bolus: bolus, activationType: activationType, session: session)
    }

    /// As stock's `WatchDataManager.addCarbEntryAndBolusFromWatchMessage`: the carbs are saved
    /// first, and the bolus is sent from the save's completion only once they are, with the stored
    /// entry in its decision. Off main: the save completes on the carb store's queue.
    nonisolated private static func podLoanDeliver(carbEntry: NewCarbEntry?, bolus: Double,
                                                   activationType: BolusActivationType, session: StockLoopSession) {
        guard let carbEntry else {
            if bolus > 0 {
                deliverLoanBolus(units: bolus, activationType: activationType, carbEntry: nil, storedCarbEntry: nil, session: session)
            }
            return
        }
        session.loanController.loanDidRecordCarbs(carbEntry) { result in
            switch result {
            case .success(let stored):
                if bolus > 0 {
                    deliverLoanBolus(units: bolus, activationType: activationType, carbEntry: carbEntry, storedCarbEntry: stored, session: session)
                } else {
                    // Carbs alone: stock stores a watchBolus decision for these too.
                    session.stack.loopManager.storeWatchCarbsOnlyDosingDecision(carbEntry: carbEntry, storedCarbEntry: stored)
                    DispatchQueue.main.async { WKInterfaceDevice.current().play(.success) }
                }
            case .failure(let error):
                // As stock: carbs that could not be saved are not bolused for.
                SportLog.event("bolus-ui", String(format: "BOLUS NOT SENT — %.0f g could not be saved: %@ · haptic=failure",
                                                  carbEntry.quantity.doubleValue(for: .gram), String(describing: error)))
                DispatchQueue.main.async { WKInterfaceDevice.current().play(.failure) }
            }
        }
    }

    nonisolated private static func deliverLoanBolus(units: Double, activationType: BolusActivationType, carbEntry: NewCarbEntry?,
                                                     storedCarbEntry: StoredCarbEntry?, session: StockLoopSession) {
        session.stack.loopManager.enactManualBolus(units: units, activationType: activationType,
                                                   carbEntry: carbEntry, storedCarbEntry: storedCarbEntry) { error in
            let carbGrams = carbEntry?.quantity.doubleValue(for: .gram)
            // `enactManualBolus` completes on main.
            MainActor.assumeIsolated {
                if let error = error {
                    // No re-send: the carbs are already journaled.
                    WKInterfaceDevice.current().play(.failure)
                    SportLog.event("bolus-ui", String(
                        format: "USER ALERTED 'Bolus Unconfirmed' — %.2f U did not confirm%@ · reason: %@ · haptic=failure",
                        units,
                        carbGrams.map { String(format: " (%.0f g ALREADY logged)", $0) } ?? "",
                        error.localizedDescription))
                    notifyBolusFailure(units: units,
                                       carbGrams: carbGrams,
                                       error: error)
                } else {
                    WKInterfaceDevice.current().play(.success)
                }
            }
        }
    }
}
