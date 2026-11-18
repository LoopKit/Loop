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
import UserNotifications
import WatchKit

extension CarbAndBolusFlowViewModel {

    /// During a loan the grant's maximum; the phone's relayed value can be stale.
    static func activeMaxBolus(_ loopManager: LoopDataManager) -> Double {
        if let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
           session.loanController.isLoanActive,
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

        if let refused = error as? BolusRefusedWhileEnding {
            content.title = NSLocalizedString("Bolus Not Sent", comment: "Watch notification title: a bolus refused while an End is waiting")
            content.body = refused.reason
            return content
        }

        if case .uncertainDelivery? = error as? PumpManagerError {
            let unitsText = NumberFormatter.localizedString(from: NSNumber(value: units), number: .decimal)
            content.title = String(
                format: NSLocalizedString("Bolus Unconfirmed: %@ U", comment: "Watch notification title for a loan-time bolus whose delivery could not be confirmed (1: units)"),
                unitsText)
            if let carbGrams = carbGrams {
                content.body = String(
                    format: NSLocalizedString("%@ g saved. Don't bolus again until Loop confirms it.", comment: "Watch notification body when carbs were saved but bolus delivery is unconfirmed (1: grams)"),
                    NumberFormatter.localizedString(from: NSNumber(value: Int(carbGrams.rounded())), number: .none))
            } else {
                content.body = NSLocalizedString("Don't bolus again until Loop confirms it.", comment: "Watch notification body when a loan-time bolus delivery is unconfirmed")
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

    /// The Sport Mode session, loan or not.
    var podLoanSession: StockLoopSession? {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession
    }

    /// The Sport Mode session while a loan is live; nil otherwise.
    var loanSessionIfActive: StockLoopSession? {
        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
              session.loanController.isLoanActive else { return nil }
        return session
    }

    /// During a loan the watch computes the recommendation: the phone's books are frozen, and it
    /// may be off. A failure is announced, not left as a 0 dial.
    ///
    /// One at a time: the watch's display updates ask again every few seconds after a reading (the
    /// cycle's display run, then each store change its dose makes), and each run takes a second or
    /// more. A request made while one is out is remembered and run once when it returns, so the number
    /// shown at rest was always computed after the last request. "Calculating" shows only while the
    /// number on screen is not for the entry considered; a recompute of the same entry keeps its number
    /// until the new one replaces it (stock's flow then leaves the confirmation, as for any change).
    func recommendLoanBolus(with entry: NewCarbEntry?, session: StockLoopSession) {
        if !(loanRecommendationIsForEntry && recommendedBolusAmount != nil) {
            isComputingRecommendedBolus = true
        }
        if loanRecommendationInFlight {
            loanRecommendationStale = true
            return
        }
        loanRecommendationInFlight = true
        session.stack.loopManager.recommendManualBolus(potentialCarbEntry: entry) { [weak self] result in
            Task { @MainActor in self?.loanRecommendationArrived(result, for: entry, session: session) }
        }
    }

    private func loanRecommendationArrived(_ result: Swift.Result<ManualBolusRecommendation?, Swift.Error>,
                                           for entry: NewCarbEntry?, session: StockLoopSession) {
        loanRecommendationInFlight = false
        let askedAgain = loanRecommendationStale
        loanRecommendationStale = false

        // Superseded otherwise: the carbs under consideration changed.
        if entry == carbEntryUnderConsideration {
            switch result {
            case .success(let recommendation):
                SportLog.event("bolus-ui", String(format: "bolus recommended for %.0f g carbs: %.2f U",
                                                  entry?.quantity.doubleValue(for: .gram) ?? 0,
                                                  recommendation?.amount ?? 0))
                if recommendedBolusAmount != recommendation?.amount {
                    recommendedBolusAmount = recommendation?.amount
                }
                loanRecommendationIsForEntry = true
            case .failure(let error):
                SportLog.event("bolus-ui", "bolus recommendation failed: \(error)")
                recommendedBolusAmount = nil
                loanRecommendationIsForEntry = false
            }
        }
        isComputingRecommendedBolus = false

        // Asked again meanwhile (a change of entry asks too): once more, for the entry considered now. A carb
        // screen with no entry (sent, or back at the carb dial) has nothing to recommend for.
        let current = carbEntryUnderConsideration
        if askedAgain, configuration == .manualBolus || current != nil,
           session.loanController.isLoanActive {
            recommendLoanBolus(with: current, session: session)
        }
    }

    /// The watch's cycle asks at each decision, so the recommendation is recomputed ahead of the
    /// cycle's display run and does not wait for the display update that follows it.
    func observeLoanDecisions() {
        podLoanSession?.stack.loopManager.recommendAfterDecision = { [weak self] in
            guard let self, let session = self.loanSessionIfActive else { return false }
            // A carb screen with no entry has nothing to recommend for; the bolus screen always has.
            let entry = self.carbEntryUnderConsideration
            guard self.configuration == .manualBolus || entry != nil else { return false }
            self.recommendLoanBolus(with: entry, session: session)
            return true
        }
    }

    /// An End is under way: the pod is going back to the phone, so no bolus starts, by the watch's
    /// pump or stock's route (nor its carbs, which the looper enters with it on the phone).
    func podLoanRefuseBolus(_ bolus: Double, reason: String) {
        SportLog.event("bolus-ui", String(format: "bolus of %.2f U refused: an End is waiting", bolus))
        Self.notifyBolusFailure(units: bolus, carbGrams: nil, error: BolusRefusedWhileEnding(reason: reason))
        WKInterfaceDevice.current().play(.failure)
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
    /// entry in its decision.
    private static func podLoanDeliver(carbEntry: NewCarbEntry?, bolus: Double,
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
                SportLog.event("bolus-ui", String(format: "bolus not sent because the %.0f g carb entry could not be saved: %@",
                                                  carbEntry.quantity.doubleValue(for: .gram), String(describing: error)))
                DispatchQueue.main.async { WKInterfaceDevice.current().play(.failure) }
            }
        }
    }

    private static func deliverLoanBolus(units: Double, activationType: BolusActivationType, carbEntry: NewCarbEntry?,
                                         storedCarbEntry: StoredCarbEntry?, session: StockLoopSession) {
        session.stack.loopManager.enactManualBolus(units: units, activationType: activationType,
                                                   carbEntry: carbEntry, storedCarbEntry: storedCarbEntry) { error in
            let carbGrams = carbEntry?.quantity.doubleValue(for: .gram)
            if let error = error {
                // No re-send: the carbs are already journaled.
                WKInterfaceDevice.current().play(.failure)
                notifyBolusFailure(units: units,
                                   carbGrams: carbGrams,
                                   error: error)
            } else {
                WKInterfaceDevice.current().play(.success)
            }
        }
    }
}

/// A bolus asked for while an End waits for the phone.
struct BolusRefusedWhileEnding: Error {
    let reason: String
}
