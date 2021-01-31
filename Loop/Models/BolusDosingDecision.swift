//
//  BolusDosingDecision.swift
//  Loop
//
//  Created by Darin Krauss on 10/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

struct BolusDosingDecision {
    var insulinOnBoard: InsulinValue?
    var carbsOnBoard: CarbValue?
    var scheduleOverride: TemporaryScheduleOverride?
    var glucoseTargetRangeSchedule: GlucoseRangeSchedule?
    var effectiveGlucoseTargetRangeSchedule: GlucoseRangeSchedule?
    var predictedGlucoseIncludingPendingInsulin: [PredictedGlucoseValue]?
    var manualGlucose: GlucoseValue?
    var originalCarbEntry: StoredCarbEntry?
    var carbEntry: StoredCarbEntry?
    var recommendedBolus: ManualBolusRecommendation?
    var requestedBolus: Double?
    
    init() {}
}
