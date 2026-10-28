//
//  BolusDosingDecision.swift
//  Loop
//
//  Created by Darin Krauss on 10/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopAlgorithm

public struct BolusDosingDecision {
    public enum Reason: String {
        case normalBolus
        case simpleBolus
        case watchBolus
    }

    public var id: UUID
    public var reason: Reason
    public var scheduleOverride: TemporaryScheduleOverride?
    public var historicalGlucose: [HistoricalGlucoseValue]?
    public var originalCarbEntry: StoredCarbEntry?
    public var carbEntry: StoredCarbEntry?
    public var manualGlucoseSample: StoredGlucoseSample?
    public var carbsOnBoard: CarbValue?
    public var insulinOnBoard: InsulinValue?
    public var glucoseTargetRangeSchedule: GlucoseRangeSchedule?
    public var predictedGlucose: [PredictedGlucoseValue]?
    public var manualBolusRecommendation: ManualBolusRecommendationWithDate?
    public var manualBolusRequested: Double?
    
    public init(for reason: Reason) {
        self.id = UUID()
        self.reason = reason
    }
}

extension BolusDosingDecision {
    /// The record of a bolus asked for on the watch: what the watch was shown, from one display run.
    /// `glucoseTargetRangeSchedule` is the correction range in effect, as the device's presets work it out.
    public static func watchBolus(displayState: AlgorithmDisplayState, recommendation: ManualBolusRecommendation?,
                                  scheduleOverride: TemporaryScheduleOverride?, glucoseTargetRangeSchedule: GlucoseRangeSchedule?,
                                  now: Date = Date()) -> BolusDosingDecision {
        var decision = BolusDosingDecision(for: .watchBolus)
        decision.carbsOnBoard = displayState.activeCarbs
        decision.manualBolusRecommendation = recommendation.map { ManualBolusRecommendationWithDate(recommendation: $0, date: now) }
        if let input = displayState.input, let latest = input.glucoseHistory.last {
            let historicalGlucoseStartDate = now.addingTimeInterval(-LoopCoreConstants.dosingDecisionHistoricalGlucoseInterval)
            let start = min(historicalGlucoseStartDate, latest.startDate)
            decision.historicalGlucose = input.glucoseHistory.filterDateRange(start, nil)
                .filter { $0.startDate >= historicalGlucoseStartDate }
                .map { HistoricalGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) }
        }
        decision.insulinOnBoard = displayState.activeInsulin
        decision.predictedGlucose = displayState.output?.predictedGlucose
        decision.scheduleOverride = scheduleOverride
        decision.glucoseTargetRangeSchedule = glucoseTargetRangeSchedule
        return decision
    }
}
