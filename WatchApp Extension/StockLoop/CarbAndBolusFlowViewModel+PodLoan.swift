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

    /// One wrist bolus notification at a time, as stock's one bolus-failure identifier.
    nonisolated static let bolusFailureNotificationID = "loan.bolus.failure"

    /// A bolus that never reached the pod is silent, so the failure is announced.
    nonisolated private static func notifyBolusFailure(units: Double, carbGrams: Double?, error: Swift.Error) {
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.bolusFailureNotificationID,
                                  content: bolusFailureContent(units: units, carbGrams: carbGrams, error: error), trigger: nil))
    }

    /// An uncertain delivery keeps the wrist's "unconfirmed, wait" wording (stock stays silent
    /// there); any other error gets stock's wording, built from the error.
    nonisolated static func bolusFailureContent(units: Double, carbGrams: Double?, error: Swift.Error) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default

        if case .uncertainDelivery? = error as? PumpManagerError {
            let unitsText = NumberFormatter.localizedString(from: NSNumber(value: units), number: .decimal)
            content.title = String(
                format: NSLocalizedString("Bolus Unconfirmed: %@ U", comment: "Watch notification title for a loan-time bolus whose delivery could not be confirmed (1: units)"),
                unitsText)
            if let carbGrams = carbGrams {
                content.body = String(
                    format: NSLocalizedString("%@ g was saved. Loop couldn't confirm delivery. You can wait to see if it resolves.", comment: "Watch notification body when carbs were saved but bolus delivery is unconfirmed (1: grams)"),
                    NumberFormatter.localizedString(from: NSNumber(value: Int(carbGrams.rounded())), number: .none))
            } else {
                content.body = NSLocalizedString("Loop couldn't confirm delivery. You can wait to see if it resolves.", comment: "Watch notification body when a loan-time bolus delivery is unconfirmed")
            }
            return content
        }

        // A labelled copy of stock `NotificationManager.sendBolusFailureNotification`'s title and
        // body (phone-only), for any error rather than only a `PumpManagerError`.
        content.title = NSLocalizedString("Bolus Issue", comment: "The notification title for a bolus issue")

        let fullStopCharacter = NSLocalizedString(".", comment: "Full stop character")
        let sentenceFormat = NSLocalizedString("%1@%2@", comment: "Adds a full-stop to a statement (1: statement, 2: full stop character)")

        let localizedError = error as? LocalizedError
        let body = [localizedError?.errorDescription ?? error.localizedDescription, localizedError?.failureReason, localizedError?.recoverySuggestion].compactMap({ $0 }).map({
            // Avoids the double period at the end of a sentence.
            $0.hasSuffix(fullStopCharacter) ? $0 : String(format: sentenceFormat, $0, fullStopCharacter)
        }).joined(separator: " ")

        content.body = body
        return content
    }

    /// The Sport Mode session while a loan is live; nil otherwise.
    var loanSessionIfActive: StockLoopSession? {
        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
              session.loanController.isLoanActive else { return nil }
        return session
    }

    /// During a loan the watch computes the recommendation: the phone's books are frozen, and it
    /// may be off. A failure is announced, not left as a 0 dial.
    func recommendLoanBolus(with entry: NewCarbEntry?, session: StockLoopSession) async {
        isComputingRecommendedBolus = true
        defer { isComputingRecommendedBolus = false }

        let result: Swift.Result<ManualBolusRecommendation?, Swift.Error> = await withCheckedContinuation { continuation in
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
                                              recommendation?.amount ?? 0))
            if recommendedBolusAmount != recommendation?.amount {
                recommendedBolusAmount = recommendation?.amount
            }
        case .failure(let error):
            SportLog.event("bolus-ui", "REC carb (watch-local) FAILED — \(error) · dial stays 0, button reads Save")
            recommendedBolusAmount = nil
        }
    }

    /// Called from `sendSetBolusUserInfo(carbEntry:bolus:)` while a loan is live: the phone has
    /// released the pod, so the bolus goes to the watch's pump, and the carbs to the local store
    /// and the loan journal rather than the stock relay.
    func podLoanDeliverOnWrist(carbEntry: NewCarbEntry?, bolus: Double, session: StockLoopSession) {
        // As stock (#2556): the entry is no longer pending once sent. The watch saves it into COB and
        // posts a context update, and a still-pending entry would be recommended for a second time.
        carbEntryUnderConsideration = nil
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
                    let title = bolusFailureContent(units: units, carbGrams: carbGrams, error: error).title
                    SportLog.event("bolus-ui", String(
                        format: "USER ALERTED '%@' — %.2f U did not confirm%@ · reason: %@ · haptic=failure",
                        title,
                        units,
                        carbGrams.map { String(format: " (%.0f g ALREADY logged)", $0) } ?? "",
                        String(describing: error)))
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
