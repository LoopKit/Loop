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
    static let bolusUnconfirmedNotificationID = "loan.bolus.failure"

    /// A bolus that never reached the pod is silent, so the failure is announced.
    private static func notifyBolusFailure(units: Double, carbGrams: Double?, error: Swift.Error) {
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
        if let carbEntry = carbEntry {
            session.loanController.loanDidRecordCarbs(carbEntry)
        }
        if bolus > 0 {
            let units = bolus
            session.stack.loopManager.enactManualBolus(units: units, activationType: activationType) { error in
                if let error = error {
                    // No re-send: the carbs are already journaled.
                    WKInterfaceDevice.current().play(.failure)
                    SportLog.event("bolus-ui", String(
                        format: "USER ALERTED 'Bolus Unconfirmed' — %.2f U did not confirm%@ · reason: %@ · haptic=failure",
                        units,
                        carbEntry.map { String(format: " (%.0f g ALREADY logged)", $0.quantity.doubleValue(for: .gram)) } ?? "",
                        error.localizedDescription))
                    Self.notifyBolusFailure(units: units,
                                            carbGrams: carbEntry?.quantity.doubleValue(for: .gram),
                                            error: error)
                } else {
                    WKInterfaceDevice.current().play(.success)
                }
            }
        } else if carbEntry != nil {
            WKInterfaceDevice.current().play(.success)
        }
    }
}
