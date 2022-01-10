//
//  BolusDosingDecision.swift
//  Loop
//
//  Created by Darin Krauss on 10/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

struct BolusDosingDecision {
    enum Reason: String {
        case normalBolus
        case simpleBolus
        case watchBolus
    }

    var reason: Reason
    var scheduleOverride: TemporaryScheduleOverride?
    var historicalGlucose: [HistoricalGlucoseValue]?
    var originalCarbEntry: StoredCarbEntry?
    var carbEntry: StoredCarbEntry?
    var manualGlucoseSample: StoredGlucoseSample?
    var carbsOnBoard: CarbValue?
    var insulinOnBoard: InsulinValue?
    var glucoseTargetRangeSchedule: GlucoseRangeSchedule?
    var predictedGlucose: [PredictedGlucoseValue]?
    var manualBolusRecommendation: ManualBolusRecommendationWithDate?
    var manualBolusRequested: Double?
    
    init(for reason: Reason) {
        self.reason = reason
    }
}
