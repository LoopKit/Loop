//
//  MealDetectionManager.swift
//  Loop
//
//  Created by Anna Quinlan on 11/28/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import OSLog
import LoopCore
import LoopKit
import Combine

enum MissedMealStatus: Equatable {
    case hasMissedMeal(startTime: Date, carbAmount: Double)
    case noMissedMeal
}

protocol BolusStateProvider {
    var bolusState: PumpManagerStatus.BolusState? { get }
}

protocol AlgorithmDisplayStateProvider {
    var algorithmState: AlgorithmDisplayState { get async }
}

@MainActor
class MealDetectionManager {
    private let log = OSLog(category: "MealDetectionManager")

    // All math for meal detection occurs in mg/dL, with settings being converted if in mmol/L
    private let unit = HKUnit.milligramsPerDeciliter
    
    /// The last missed meal notification that was sent
    /// Internal for unit testing
    var lastMissedMealNotification: MissedMealNotification? = UserDefaults.standard.lastMissedMealNotification {
        didSet {
            UserDefaults.standard.lastMissedMealNotification = lastMissedMealNotification
        }
    }
    
    /// Debug info for missed meal detection
    /// Timeline from the most recent check for missed meals
    private var lastEvaluatedMissedMealTimeline: [(date: Date, unexpectedDeviation: Double?, mealThreshold: Double?, rateOfChangeThreshold: Double?)] = []
    
    /// Timeline from the most recent detection of an missed meal
    private var lastDetectedMissedMealTimeline: [(date: Date, unexpectedDeviation: Double?, mealThreshold: Double?, rateOfChangeThreshold: Double?)] = []

    private var algorithmStateProvider: AlgorithmDisplayStateProvider
    private var settingsProvider: SettingsWithOverridesProvider
    private var bolusStateProvider: BolusStateProvider

    private lazy var cancellables = Set<AnyCancellable>()

    // For testing only
    var test_currentDate: Date?

    init(
        algorithmStateProvider: AlgorithmDisplayStateProvider,
        settingsProvider: SettingsWithOverridesProvider,
        bolusStateProvider: BolusStateProvider
    ) {
        self.algorithmStateProvider = algorithmStateProvider
        self.settingsProvider = settingsProvider
        self.bolusStateProvider = bolusStateProvider

        if FeatureFlags.missedMealNotifications {
            NotificationCenter.default.publisher(for: .LoopCycleCompleted)
                .sink { [weak self] _ in
                    Task { await self?.run() }
                }
                .store(in: &cancellables)
        }
    }

    func run() async {
        let algoState = await algorithmStateProvider.algorithmState
        guard let input = algoState.input, let output = algoState.output else {
            self.log.debug("Skipping run with missing algorithm input/output")
            return
        }

        let date = test_currentDate ?? Date()
        let samplesStart = date.addingTimeInterval(-MissedMealSettings.maxRecency)

        guard let sensitivitySchedule = settingsProvider.insulinSensitivityScheduleApplyingOverrideHistory,
              let carbRatioSchedule = settingsProvider.carbRatioSchedule,
              let maxBolus = settingsProvider.maximumBolus else
        {
            return
        }

        generateMissedMealNotificationIfNeeded(
            at: date,
            glucoseSamples: input.glucoseHistory,
            insulinCounteractionEffects: output.effects.insulinCounteraction,
            carbEffects: output.effects.carbs,
            sensitivitySchedule: sensitivitySchedule,
            carbRatioSchedule: carbRatioSchedule,
            maxBolus: maxBolus
        )
    }

    // MARK: Meal Detection
    func hasMissedMeal(
        at date: Date,
        glucoseSamples: [some GlucoseSampleValue],
        insulinCounteractionEffects: [GlucoseEffectVelocity],
        carbEffects: [GlucoseEffect],
        sensitivitySchedule: InsulinSensitivitySchedule,
        carbRatioSchedule: CarbRatioSchedule
    ) -> MissedMealStatus
    {
        let delta = TimeInterval(minutes: 5)

        let intervalStart = date.addingTimeInterval(-MissedMealSettings.maxRecency)
        let intervalEnd = date.addingTimeInterval(-MissedMealSettings.minRecency)
        let now = date

        let filteredGlucoseValues = glucoseSamples.filter { intervalStart <= $0.startDate && $0.startDate <= now }
        
        /// Only try to detect if there's a missed meal if there are no calibration/user-entered BGs,
        /// since these can cause large jumps
        guard !filteredGlucoseValues.containsUserEntered() else {
            return .noMissedMeal
        }
        
        let filteredCarbEffects = carbEffects.filterDateRange(intervalStart, now)
            
        /// Compute how much of the ICE effect we can't explain via our entered carbs
        /// Effect caching inspired by `LoopMath.predictGlucose`
        var effectValueCache: [Date: Double] = [:]

        /// Carb effects are cumulative, so we have to subtract the previous effect value
        var previousEffectValue: Double = filteredCarbEffects.first?.quantity.doubleValue(for: unit) ?? 0

        /// Counteraction effects only take insulin into account, so we need to account for the carb effects when computing the unexpected deviations
        for effect in filteredCarbEffects {
            let value = effect.quantity.doubleValue(for: unit)
            /// We do `-1 * (value - previousEffectValue)` because this will compute the carb _counteraction_ effect
            effectValueCache[effect.startDate] = (effectValueCache[effect.startDate] ?? 0) +  -1 * (value - previousEffectValue)
            previousEffectValue = value
        }

        let processedICE = insulinCounteractionEffects
            .filterDateRange(intervalStart, now)
            .compactMap {
                /// Clamp starts & ends to `intervalStart...now` since our algorithm assumes all effects occur within that interval
                let start = max($0.startDate, intervalStart)
                let end = min($0.endDate, now)

                guard let effect = $0.effect(from: start, to: end) else {
                    let item: GlucoseEffect? = nil // FIXME: we get a compiler error if we try to return `nil` directly
                    return item
                }

                return GlucoseEffect(startDate: effect.endDate.dateCeiledToTimeInterval(delta),
                                     quantity: effect.quantity)
            }
        
        for effect in processedICE {
            let value = effect.quantity.doubleValue(for: unit)
            effectValueCache[effect.startDate] = (effectValueCache[effect.startDate] ?? 0) + value
        }
        
        var unexpectedDeviation: Double = 0
        var mealTime = now
        
        /// Dates the algorithm uses when computing effects
        /// Have the range go from newest -> oldest time
        let summationRange = LoopMath.simulationDateRange(from: intervalStart,
                                                to: now,
                                                delta: delta)
                                      .reversed()
        
        /// Dates the algorithm is allowed to check for the presence of a missed meal
        let dateSearchRange = Set(LoopMath.simulationDateRange(from: intervalStart,
                                                     to: intervalEnd,
                                                     delta: delta))
        
        /// Timeline used for debug purposes
        var missedMealTimeline: [(date: Date, unexpectedDeviation: Double?, mealThreshold: Double?, rateOfChangeThreshold: Double?)] = []
        
        for pastTime in summationRange {
            guard let unexpectedEffect = effectValueCache[pastTime] else {
                missedMealTimeline.append((pastTime, nil, nil, nil))
                continue
            }
            
            unexpectedDeviation += unexpectedEffect

            guard dateSearchRange.contains(pastTime) else {
                /// This time is too recent to check for a missed meal
                missedMealTimeline.append((pastTime, unexpectedDeviation, nil, nil))
                continue
            }
            
            /// Find the threshold based on a minimum of `missedMealGlucoseRiseThreshold` of change per minute
            let minutesAgo = now.timeIntervalSince(pastTime).minutes
            let rateThreshold = MissedMealSettings.glucoseRiseThreshold * minutesAgo
           
            let carbRatio = carbRatioSchedule.value(at: pastTime)
            let insulinSensitivity = sensitivitySchedule.value(for: unit, at: pastTime)

            /// Find the total effect we'd expect to see for a meal with `carbThreshold`-worth of carbs that started at `pastTime`
            guard let mealThreshold = self.effectThreshold(
                carbRatio: carbRatio,
                insulinSensitivity: insulinSensitivity,
                carbsInGrams: MissedMealSettings.minCarbThreshold
            ) else {
                continue
            }
            
            missedMealTimeline.append((pastTime, unexpectedDeviation, mealThreshold, rateThreshold))
            
            /// Use the higher of the 2 thresholds to ensure noisy CGM data doesn't cause false-positives for more recent times
            let effectThreshold = max(rateThreshold, mealThreshold)

            if unexpectedDeviation >= effectThreshold {
                mealTime = pastTime
            }
        }
        
        self.lastEvaluatedMissedMealTimeline = missedMealTimeline.reversed()
        
        let mealTimeTooRecent = now.timeIntervalSince(mealTime) < MissedMealSettings.minRecency
        guard !mealTimeTooRecent else {
            return .noMissedMeal
        }

        self.lastDetectedMissedMealTimeline = missedMealTimeline.reversed()

        let carbRatio = carbRatioSchedule.value(at: mealTime)
        let insulinSensitivity = sensitivitySchedule.value(for: unit, at: mealTime)

        let carbAmount = self.determineCarbs(
            carbRatio: carbRatio,
            insulinSensitivity: insulinSensitivity,
            unexpectedDeviation: unexpectedDeviation
        )
        return .hasMissedMeal(startTime: mealTime, carbAmount: carbAmount ?? MissedMealSettings.minCarbThreshold)
    }
    
    private func determineCarbs(carbRatio: Double, insulinSensitivity: Double, unexpectedDeviation: Double) -> Double? {
        var mealCarbs: Double? = nil
        
        /// Search `carbAmount`s from `minCarbThreshold` to `maxCarbThreshold` in 5-gram increments,
        /// seeing if the deviation is at least `carbAmount` of carbs
        for carbAmount in stride(from: MissedMealSettings.minCarbThreshold, through: MissedMealSettings.maxCarbThreshold, by: 5) {
            if
                let modeledCarbEffect = effectThreshold(carbRatio: carbRatio, insulinSensitivity: insulinSensitivity, carbsInGrams: carbAmount),
                unexpectedDeviation >= modeledCarbEffect
            {
                mealCarbs = carbAmount
            }
        }
        
        return mealCarbs
    }
    

    /// Calculates effect threshold.
    ///
    /// - Parameters:
    ///    - carbRatio: Carb ratio in grams per unit in effect at the start of the meal.
    ///    - insulinSensitivity: Insulin sensitivity in mg/dL/U in effect at the start of the meal.
    ///    - carbsInGrams: Carbohydrate amount for the meal in grams
    private func effectThreshold(carbRatio: Double, insulinSensitivity: Double, carbsInGrams: Double) -> Double? {
        return carbsInGrams / carbRatio * insulinSensitivity
    }
    
    // MARK: Notification Generation
    /// Searches for any potential missed meals and sends a notification.
    /// A missed meal notification can be delivered a maximum of every  `MissedMealSettings.maxRecency - MissedMealSettings.minRecency` minutes.
    ///
    /// - Parameters:
    ///    - insulinCounteractionEffects: the current insulin counteraction effects that have been observed
    ///    - carbEffects: the effects of any active carb entries. Must include effects from `currentDate() - MissedMealSettings.maxRecency` until `currentDate()`.
    func generateMissedMealNotificationIfNeeded(
        at date: Date,
        glucoseSamples: [some GlucoseSampleValue],
        insulinCounteractionEffects: [GlucoseEffectVelocity],
        carbEffects: [GlucoseEffect],
        sensitivitySchedule: InsulinSensitivitySchedule,
        carbRatioSchedule: CarbRatioSchedule,
        maxBolus: Double
    ) {
        let status = hasMissedMeal(
            at: date,
            glucoseSamples: glucoseSamples,
            insulinCounteractionEffects: insulinCounteractionEffects,
            carbEffects: carbEffects,
            sensitivitySchedule: sensitivitySchedule,
            carbRatioSchedule: carbRatioSchedule
        )

        manageMealNotifications(
            at: date,
            for: status
        )
    }
    
    
    // Internal for unit testing
    func manageMealNotifications(
        at date: Date,
        for status: MissedMealStatus
    ) {
        // We should remove expired notifications regardless of whether or not there was a meal
        NotificationManager.removeExpiredMealNotifications()
        
        // Figure out if we should deliver a notification
        let now = date
        let notificationTimeTooRecent = now.timeIntervalSince(lastMissedMealNotification?.deliveryTime ?? .distantPast) < (MissedMealSettings.maxRecency - MissedMealSettings.minRecency)
        
        guard
            case .hasMissedMeal(let startTime, let carbAmount) = status,
            !notificationTimeTooRecent,
            UserDefaults.standard.missedMealNotificationsEnabled
        else {
            // No notification needed!
            return
        }
        
        let currentCarbRatio = settingsProvider.carbRatioSchedule!.quantity(at: now).doubleValue(for: .gram())
        let maxAllowedCarbAutofill = settingsProvider.maximumBolus! * currentCarbRatio
        let clampedCarbAmount = min(carbAmount, maxAllowedCarbAutofill)

        log.debug("Delivering a missed meal notification")

        /// Coordinate the missed meal notification time with any pending autoboluses that `update` may have started
        /// so that the user doesn't have to cancel the current autobolus to bolus in response to the missed meal notification
        if let estimatedBolusDuration = bolusStateProvider.bolusTimeRemaining(at: now),
           estimatedBolusDuration < MissedMealSettings.maxNotificationDelay,
           estimatedBolusDuration > 0
        {
            NotificationManager.sendMissedMealNotification(mealStart: startTime, amountInGrams: clampedCarbAmount, delay: estimatedBolusDuration)
            lastMissedMealNotification = MissedMealNotification(deliveryTime: now.advanced(by: estimatedBolusDuration),
                                                  carbAmount: clampedCarbAmount)
        } else {
            NotificationManager.sendMissedMealNotification(mealStart: startTime, amountInGrams: clampedCarbAmount)
            lastMissedMealNotification = MissedMealNotification(deliveryTime: now, carbAmount: clampedCarbAmount)
        }
    }
    
    // MARK: Logging
    
    /// Generates a diagnostic report about the current state
    ///
    /// - parameter completionHandler: A closure called once the report has been generated. The closure takes a single argument of the report string.
    func generateDiagnosticReport() async -> String {
        await withCheckedContinuation { continuation in
            let report = [
                "## MealDetectionManager",
                "",
                "* lastMissedMealNotificationTime: \(String(describing: lastMissedMealNotification?.deliveryTime))",
                "* lastMissedMealCarbEstimate: \(String(describing: lastMissedMealNotification?.carbAmount))",
                "* lastEvaluatedMissedMealTimeline:",
                lastEvaluatedMissedMealTimeline.reduce(into: "", { (entries, entry) in
                    entries.append("  * date: \(entry.date), unexpectedDeviation: \(entry.unexpectedDeviation ?? -1), meal-based threshold: \(entry.mealThreshold ?? -1), change-based threshold: \(entry.rateOfChangeThreshold ?? -1) \n")
                }),
                "* lastDetectedMissedMealTimeline:",
                lastDetectedMissedMealTimeline.reduce(into: "", { (entries, entry) in
                    entries.append("  * date: \(entry.date), unexpectedDeviation: \(entry.unexpectedDeviation ?? -1), meal-based threshold: \(entry.mealThreshold ?? -1), change-based threshold: \(entry.rateOfChangeThreshold ?? -1) \n")
                })
            ]

            continuation.resume(returning: report.joined(separator: "\n"))
        }
    }
}

fileprivate extension BidirectionalCollection where Element: GlucoseSampleValue, Index == Int {
    /// Returns whether there are any user-entered or calibration points
    /// Runtime: O(n)
    func containsUserEntered() -> Bool {
        return containsCalibrations() || filter({ $0.wasUserEntered }).count != 0
    }
}

extension BolusStateProvider {
    func bolusTimeRemaining(at date: Date = Date()) -> TimeInterval? {
        guard case .inProgress(let dose) = bolusState else {
            return nil
        }
        return max(0, dose.endDate.timeIntervalSince(date))
    }
}

