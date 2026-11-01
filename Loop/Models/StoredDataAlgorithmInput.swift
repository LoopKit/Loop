//
//  StoredDataAlgorithmInput.swift
//  Loop
//
//  Created by Pete Schwamb on 2/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

struct StoredDataAlgorithmInput: AlgorithmInput {
    typealias CarbType = StoredCarbEntry

    typealias GlucoseType = StoredGlucoseSample

    typealias InsulinDoseType = SimpleInsulinDose

    var glucoseHistory: [StoredGlucoseSample]
    
    var doses: [SimpleInsulinDose]

    var carbEntries: [StoredCarbEntry]
    
    var predictionStart: Date
    
    var basal: [LoopAlgorithm.AbsoluteScheduleValue<Double>]
    
    var sensitivityMgdlPerUnit: [LoopAlgorithm.AbsoluteScheduleValue<Double>]
    
    var carbRatio: [LoopAlgorithm.AbsoluteScheduleValue<Double>]
    
    var targetMgdl: LoopAlgorithm.GlucoseRangeTimeline
    
    var suspendThresholdMgdl: Double?
    
    var maxBolus: Double
    
    var maxBasalRate: Double
    
    var useIntegralRetrospectiveCorrection: Bool
    
    var includePositiveVelocityAndRC: Bool
    
    var carbAbsorptionModel: CarbAbsorptionModel
    
    var recommendationInsulinModel: LoopAlgorithm.InsulinModel
    
    var recommendationType: DoseRecommendationType
    
    var automaticBolusApplicationFactor: Double?

    let useMidAbsorptionISF: Bool = true

    var maxActiveInsulinMultiplier: Double? = nil

    var gradualTransitionsThreshold: Double? = nil

    var experiments: Set<ExperimentOption> = []

    var volatilityBaseline: Double? = nil
}
