//
//  CarbAndBolusFlowViewModel+PodLoan.swift
//  WatchApp Extension
//
//  What the carb-and-bolus flow does while the WRIST holds the pod: it recommends from the
//  watch's own books, clamps the picker to the grant, delivers on the watch's pump, and says
//  so out loud when a delivery cannot be confirmed.
//

import Foundation
import LoopKit
import LoopCore
import LoopAlgorithm
import UserNotifications
import WatchKit

extension CarbAndBolusFlowViewModel {

    /// The maximum the picker may offer. DURING A LOAN THIS IS THE GRANT'S, not the phone's.
    ///
    /// The phone's value arrives in a WatchContext and is whatever it last relayed — which during
    /// a loan can be stale, and with the phone off cannot be refreshed at all. The enact path
    /// already clamps against the granted maximum, so a picker offering more than the grant allows
    /// does not deliver an unsafe dose; it offers a dose that is then refused, which reads as a
    /// failure rather than as a limit.
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

    /// A bolus the wrist could not confirm. The pod beeps only when it ACCEPTS, so a bolus that
    /// never reached it is SILENT — and silence would otherwise mean both "still working" and
    /// "it failed". This is the one signal nothing else carries.
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
            // The error text goes to the LOG, not the lock screen: these are PodCommsError /
            // PumpManagerError values whose localizedDescription is developer copy of
            // unpredictable length.
            content.body = NSLocalizedString("Loop couldn't confirm delivery. You can wait to see if it resolves.", comment: "Watch notification body when a loan-time bolus delivery is unconfirmed")
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.bolusUnconfirmedNotificationID, content: content, trigger: nil))
    }

    /// The watch-local twin of the phone round-trip above, for a live loan.
    ///
    /// A FAILURE HERE IS SAID OUT LOUD rather than left to be inferred. Leaving the amount nil
    /// sits the dial at 0, and at 0 the flow's action button reads "Save" instead of "Save and
    /// Bolus" — carbs are stored, the bolus screen is skipped, and nothing announces that a
    /// recommendation was never computed. That is a degraded recommendation, not a trap (the user
    /// can still dial a dose by hand on this same screen), but it must never arrive silently.
    func recommendLoanBolus(with entry: NewCarbEntry?, session: StockLoopSession) async {
        isComputingRecommendedBolus = true
        defer { isComputingRecommendedBolus = false }

        let result: Swift.Result<ManualBolusRecommendation, Swift.Error> = await withCheckedContinuation { continuation in
            session.stack.loopManager.recommendManualBolus(potentialCarbEntry: entry) { result in
                continuation.resume(returning: result)
            }
        }

        // Superseded while we were computing — the entry under consideration moved on, so this
        // answer describes carbs the user is no longer entering.
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
            session.stack.loopManager.addLoanCarbEntry(carbEntry)
            session.loanController.loanDidRecordCarbs(carbEntry)
        }
        if bolus > 0 {
            let units = bolus
            session.stack.loopManager.enactManualBolus(units: units, activationType: activationType) { error in
                if let error = error {
                    // FAILURE always buzzes — see notifyBolusFailure. Deliberately does NOT
                    // re-open the send window: the carbs are already journaled, so a re-tap
                    // would double-log them.
                    WKInterfaceDevice.current().play(.failure)
                    SportLog.event("bolus-ui", String(
                        format: "USER ALERTED 'Bolus Unconfirmed' — %.2f U did not confirm%@ · reason: %@ · haptic=failure",
                        units,
                        carbEntry.map { String(format: " (%.0f g ALREADY logged)", $0.quantity.doubleValue(for: .gram)) } ?? "",
                        error.localizedDescription))
                    Self.notifyBolusFailure(units: units,
                                            carbGrams: carbEntry?.quantity.doubleValue(for: .gram),
                                            error: error)
                } else if !session.stack.loopManager.podBeepsOnManualBolus {
                    // Success haptic ONLY when the pod is silent. With beeps on, the pod's
                    // acknowledgement fires at this same instant and says the same thing.
                    WKInterfaceDevice.current().play(.success)
                }
            }
        } else if carbEntry != nil {
            WKInterfaceDevice.current().play(.success)
        }
    }
}
