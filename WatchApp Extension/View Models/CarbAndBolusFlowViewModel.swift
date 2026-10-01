//
//  CarbAndBolusFlowViewModel.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/31/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import LoopAlgorithm
import WatchKit
import WatchConnectivity
import LoopKit
import LoopCore

@MainActor
final class CarbAndBolusFlowViewModel: ObservableObject {
    enum Error: Swift.Error {
        case potentialCarbEntryMessageSendFailure
        case bolusMessageSendFailure
    }

    // MARK: - Published state
    @Published var isComputingRecommendedBolus = false
    @Published var recommendedBolusAmount: Double?
    @Published var bolusPickerValues: BolusPickerValues
    @Published var error: Error?

    // MARK: - Other state
    let interactionStartDate = Date()
    var carbEntryUnderConsideration: NewCarbEntry?   // CarbAndBolusFlowViewModel+PodLoan.swift reads it
    private var contextUpdateObservation: AnyObject?
    private var contextDate: Date?

    // MARK: - Constants
    private static let defaultSupportedBolusVolumes = (0...600).map { 0.05 * Double($0) } // U
    static let defaultMaxBolus: Double = 10 // U

    // MARK: - Initialization
    let configuration: CarbAndBolusFlow.Configuration

    init(
        configuration: CarbAndBolusFlow.Configuration
    ) {
        let loopManager = LoopDataManager.shared
        self.configuration = configuration

        self._bolusPickerValues = Published(
            initialValue: BolusPickerValues(
                supportedVolumes: loopManager.supportedBolusVolumes ?? Self.defaultSupportedBolusVolumes,
                maxBolus: Self.activeMaxBolus(loopManager)
            )
        )

        switch configuration {
        case .carbEntry:
            break
        case .manualBolus:
            // If we start out on the manual bolus screen, fetch a fresh recommendation immediately
            Task { @MainActor in
                await recommendBolus()
            }
        }

        contextUpdateObservation = NotificationCenter.default.addObserver(
            forName: LoopDataManager.didUpdateContextNotification,
            object: loopManager,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleContextUpdate(loopManager: loopManager)
            }
        }
    }

    func handleContextUpdate(loopManager: LoopDataManager) {

        self.bolusPickerValues = BolusPickerValues(
            supportedVolumes: loopManager.supportedBolusVolumes ?? Self.defaultSupportedBolusVolumes,
            maxBolus: Self.activeMaxBolus(loopManager)
        )

        switch self.configuration {
        case .carbEntry:
            // If this new context wasn't generated in response to a potential carb entry message,
            // recompute the recommended bolus for the carb entry under consideration.
            let wasContextGeneratedFromPotentialCarbEntryMessage = loopManager.activeContext?.potentialCarbEntry != nil
            if !wasContextGeneratedFromPotentialCarbEntryMessage, let entry = self.carbEntryUnderConsideration {
                Task { @MainActor in
                    await self.recommendBolus(with: entry)
                }
            }
        case .manualBolus:
            let activeContext = loopManager.activeContext
            self.contextDate = activeContext?.creationDate
            if self.recommendedBolusAmount != activeContext?.recommendedBolusDose {
                self.recommendedBolusAmount = activeContext?.recommendedBolusDose
            }
        }
    }

    deinit {
        if let observation = contextUpdateObservation {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    func discardCarbEntryUnderConsideration() {
        carbEntryUnderConsideration = nil
        recommendedBolusAmount = nil
    }

    func recommendBolus(forGrams grams: Int, eatenAt carbEntryDate: Date, absorptionTime carbAbsorptionTime: CarbAbsorptionTime, lastEntryDate: Date) async {
        let entry = NewCarbEntry(
            date: lastEntryDate,
            quantity: LoopQuantity(unit: .gram, doubleValue: Double(grams)),
            startDate: carbEntryDate,
            foodType: carbAbsorptionTime.emoji,
            absorptionTime: absorptionTime(for: carbAbsorptionTime)
        )

        guard entry.quantity.doubleValue(for: .gram) > 0 else {
            return
        }

        carbEntryUnderConsideration = entry
        await recommendBolus(with: entry)
    }

    private func recommendBolus(with entry: NewCarbEntry? = nil) async {
        // DURING A LOAN THE PHONE IS THE WRONG DEVICE TO ASK. It released its pod link at the
        // grant and its books have been frozen since, so its IOB, COB and prediction are the ones
        // it held when it handed the pod over — an answer computed from the wrong device's data.
        // With the phone switched off it cannot answer at all, which is exactly the case Sport
        // Mode exists for, and the failure surfaces as "Unable to Reach iPhone" at the bolus step
        // (field 2026-08-16, 23:33, phone off deliberately).
        //
        // The watch holds the pod, ran the loop, and owns the only current books — so it computes
        // its own recommendation.
        if let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
           session.loanController.isLoanActive {
            await recommendLoanBolus(with: entry, session: session)
            return
        }

        do {
            isComputingRecommendedBolus = true
            let context = try await WCSession.default.fetchBolusRecommendation(entry)

            // Only update if this recommendation corresponds to the current carb entry under consideration.
            guard context.potentialCarbEntry == self.carbEntryUnderConsideration else {
                return
            }

            defer {
                self.isComputingRecommendedBolus = false
            }

            self.contextDate = context.creationDate

            // Don't publish a new value if the recommendation has not changed.
            guard self.recommendedBolusAmount != context.recommendedBolusDose else {
                return
            }

            self.recommendedBolusAmount = context.recommendedBolusDose
        } catch {
            isComputingRecommendedBolus = false
            WKInterfaceDevice.current().play(.failure)
            self.error = .potentialCarbEntryMessageSendFailure
        }
    }

    private func absorptionTime(for carbAbsorptionTime: CarbAbsorptionTime) -> TimeInterval {
        let defaultTimes = LoopCoreConstants.defaultCarbAbsorptionTimes

        switch carbAbsorptionTime {
        case .fast:
            return defaultTimes.fast
        case .medium:
            return defaultTimes.medium
        case .slow:
            return defaultTimes.slow
        }
    }

    func addCarbsWithoutBolusing() async throws {
        guard let carbEntry = carbEntryUnderConsideration else {
            assertionFailure("Attempting to add carbs without a carb entry")
            return
        }

        try await sendSetBolusUserInfo(carbEntry: carbEntry, bolus: 0)
    }

    func addCarbsAndDeliverBolus(_ bolusAmount: Double) async throws {
        try await sendSetBolusUserInfo(carbEntry: carbEntryUnderConsideration, bolus: bolusAmount)
    }

    private func sendSetBolusUserInfo(carbEntry: NewCarbEntry?, bolus: Double) async throws {
        // PODLOAN: during an active loan the PHONE has RELEASED its pod link, so a bolus relayed
        // there dies undelivered — found on the wrist 2026-07-18, and again on this branch
        // 2026-08-16 when two boluses entered from these screens reached neither the pod nor the
        // phone's books. Deliver on the WATCH's pump instead.
        //
        // Carbs take both paths deliberately: the LOCAL store so this loop's COB sees them on the
        // very next cycle, and the loan JOURNAL — resend-until-ack — as the durable record that
        // reaches the phone even while it is unreachable, which is the entire point of Sport Mode.
        // The stock WC relay is skipped, not merely zeroed: it cannot deliver and its carb write
        // would race the journal's.
        if let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
           session.loanController.isLoanActive {
            podLoanDeliverOnWrist(carbEntry: carbEntry, bolus: bolus, session: session)
            return
        }

        let bolus = SetBolusUserInfo(value: bolus, startDate: Date(), contextDate: self.contextDate, carbEntry: carbEntry, activationType: .activationTypeFor(recommendedAmount: recommendedBolusAmount, bolusAmount: bolus))
        let updatedContext = try await WCSession.default.sendBolusMessage(bolus)
        if bolus.carbEntry != nil {
            // The carb entry has now been saved on the phone (and is reflected in
            // COB). Stop treating it as a pending entry, otherwise the context
            // update below re-requests a recommendation that passes it as a
            // potential entry on top of the COB it is now part of — double
            // counting the carbs and roughly doubling the recommended bolus.
            carbEntryUnderConsideration = nil
            if bolus.value == 0 {
                // Notify for a successful carb entry (sans bolus)
                WKInterfaceDevice.current().play(.success)
            }
        }
        LoopDataManager.shared.updateContext(updatedContext)
    }
}

extension CarbAndBolusFlowViewModel.Error: LocalizedError {
    var failureReason: String? {
        switch self {
        case .potentialCarbEntryMessageSendFailure:
            return NSLocalizedString("Unable to Reach iPhone", comment: "The title of the alert controller displayed after a potential carb entry send attempt fails")
        case .bolusMessageSendFailure:
            return NSLocalizedString("Bolus Failed", comment: "The title of the alert controller displayed after a bolus attempt fails")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .potentialCarbEntryMessageSendFailure:
            return NSLocalizedString("Make sure your iPhone is nearby and try again.", comment: "The recovery message displayed after a potential carb entry send attempt fails")
        case .bolusMessageSendFailure:
            return NSLocalizedString("Make sure your iPhone is nearby and try again.", comment: "The recovery message displayed after a bolus attempt fails")
        }
    }
}

extension CarbAndBolusFlowViewModel.Error: Identifiable {
    var id: Self { self }
}
