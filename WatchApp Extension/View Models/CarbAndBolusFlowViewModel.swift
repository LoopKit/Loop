//
//  CarbAndBolusFlowViewModel.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/31/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import HealthKit
import WatchKit
import WatchConnectivity
import LoopKit
import LoopCore


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
    private var carbEntryUnderConsideration: NewCarbEntry?
    private var contextUpdateObservation: AnyObject?
    private var hasSentConfirmationMessage = false
    private var contextDate: Date?

    // MARK: - Constants
    private static let defaultSupportedBolusVolumes = (0...600).map { 0.05 * Double($0) } // U
    private static let defaultMaxBolus: Double = 10 // U

    // MARK: - Initialization
    let configuration: CarbAndBolusFlow.Configuration
    private let dismiss: () -> Void

    init(
        configuration: CarbAndBolusFlow.Configuration,
        dismiss: @escaping () -> Void
    ) {
        let loopManager = ExtensionDelegate.shared().loopManager
        switch configuration {
        case .carbEntry:
            break
        case .manualBolus:
            let activeContext = loopManager.activeContext
            self.contextDate = activeContext?.creationDate
            self._recommendedBolusAmount = Published(initialValue: activeContext?.recommendedBolusDose)
        }

        self._bolusPickerValues = Published(
            initialValue: BolusPickerValues(
                supportedVolumes: loopManager.supportedBolusVolumes ?? Self.defaultSupportedBolusVolumes,
                maxBolus: loopManager.settings.maximumBolus ?? Self.defaultMaxBolus
            )
        )

        self.configuration = configuration
        self.dismiss = dismiss

        contextUpdateObservation = NotificationCenter.default.addObserver(
            forName: LoopDataManager.didUpdateContextNotification,
            object: loopManager,
            queue: nil
        ) { [weak self] _ in
            guard
                let self = self,
                !self.hasSentConfirmationMessage
            else {
                return
            }
            
            self.bolusPickerValues = BolusPickerValues(
                supportedVolumes: loopManager.supportedBolusVolumes ?? Self.defaultSupportedBolusVolumes,
                maxBolus: loopManager.settings.maximumBolus ?? Self.defaultMaxBolus
            )

            switch self.configuration {
            case .carbEntry:
                // If this new context wasn't generated in response to a potential carb entry message,
                // recompute the recommended bolus for the carb entry under consideration.
                let wasContextGeneratedFromPotentialCarbEntryMessage = loopManager.activeContext?.potentialCarbEntry != nil
                if !wasContextGeneratedFromPotentialCarbEntryMessage, let entry = self.carbEntryUnderConsideration {
                    self.recommendBolus(for: entry)
                }
            case .manualBolus:
                let activeContext = loopManager.activeContext
                self.contextDate = activeContext?.creationDate
                if self.recommendedBolusAmount != activeContext?.recommendedBolusDose {
                    self.recommendedBolusAmount = activeContext?.recommendedBolusDose
                }
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

    func recommendBolus(forGrams grams: Int, eatenAt carbEntryDate: Date, absorptionTime carbAbsorptionTime: CarbAbsorptionTime, lastEntryDate: Date) {
        let entry = NewCarbEntry(
            date: lastEntryDate,
            quantity: HKQuantity(unit: .gram(), doubleValue: Double(grams)),
            startDate: carbEntryDate,
            foodType: nil,
            absorptionTime: absorptionTime(for: carbAbsorptionTime)
        )

        guard entry.quantity.doubleValue(for: .gram()) > 0 else {
            return
        }

        carbEntryUnderConsideration = entry
        recommendBolus(for: entry)
    }

    private func recommendBolus(for entry: NewCarbEntry) {
        let potentialEntry = PotentialCarbEntryUserInfo(carbEntry: entry)
        do {
            isComputingRecommendedBolus = true
            try WCSession.default.sendPotentialCarbEntryMessage(potentialEntry,
                replyHandler: { [weak self] context in
                    DispatchQueue.main.async {
                        let loopManager = ExtensionDelegate.shared().loopManager
                        loopManager.updateContext(context)

                        guard let self = self else {
                            return
                        }

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
                    }
                },
                errorHandler: { error in
                    DispatchQueue.main.async { [weak self] in
                        self?.isComputingRecommendedBolus = false
                        WKInterfaceDevice.current().play(.failure)
                        ExtensionDelegate.shared().present(error)
                    }
                }
            )
        } catch {
            isComputingRecommendedBolus = false
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

    func addCarbsWithoutBolusing() {
        guard let carbEntry = carbEntryUnderConsideration else {
            assertionFailure("Attempting to add carbs without a carb entry")
            return
        }

        sendSetBolusUserInfo(carbEntry: carbEntry, bolus: 0)
    }

    func addCarbsAndDeliverBolus(_ bolusAmount: Double) {
        sendSetBolusUserInfo(carbEntry: carbEntryUnderConsideration, bolus: bolusAmount)
    }

    private func sendSetBolusUserInfo(carbEntry: NewCarbEntry?, bolus: Double) {
        guard !hasSentConfirmationMessage else {
            return
        }
        self.hasSentConfirmationMessage = true

        let bolus = SetBolusUserInfo(value: bolus, startDate: Date(), contextDate: self.contextDate, carbEntry: carbEntry, activationType: .activationTypeFor(recommendedAmount: recommendedBolusAmount, bolusAmount: bolus))
        do {
            try WCSession.default.sendBolusMessage(bolus) { [weak self] (error) in
                DispatchQueue.main.async {
                    if let error = error {
                        ExtensionDelegate.shared().present(error)
                        self?.hasSentConfirmationMessage = false
                    } else {
                        if bolus.carbEntry != nil {
                            if bolus.value == 0 {
                                // Notify for a successful carb entry (sans bolus)
                                WKInterfaceDevice.current().play(.success)
                            }
                        }
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                self.dismiss()
            }
        } catch {
            self.error = .bolusMessageSendFailure
        }
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
