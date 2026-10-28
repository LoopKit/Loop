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

public struct StoredDataAlgorithmInput: AlgorithmInput {
    public typealias CarbType = StoredCarbEntry

    public typealias GlucoseType = StoredGlucoseSample

    public typealias InsulinDoseType = SimpleInsulinDose

    public var glucoseHistory: [StoredGlucoseSample]
    
    public var doses: [SimpleInsulinDose]

    public var carbEntries: [StoredCarbEntry]
    
    public var predictionStart: Date
    
    public var basal: [AbsoluteScheduleValue<Double>]
    
    public var sensitivity: [AbsoluteScheduleValue<LoopQuantity>]
    
    public var carbRatio: [AbsoluteScheduleValue<Double>]
    
    public var target: GlucoseRangeTimeline
    
    public var suspendThreshold: LoopQuantity?
    
    public var maxBolus: Double
    
    public var maxBasalRate: Double
    
    public var useIntegralRetrospectiveCorrection: Bool
    
    public var includePositiveVelocityAndRC: Bool
    
    public var carbAbsorptionModel: CarbAbsorptionModel
    
    public var recommendationInsulinModel: InsulinModel
    
    public var recommendationType: DoseRecommendationType
    
    public var automaticBolusApplicationFactor: Double?

    public let useMidAbsorptionISF: Bool = true

    public var maxActiveInsulinMultiplier: Double? = nil

    public var gradualTransitionsThreshold: Double? = nil

    public var experiments: Set<ExperimentOption> = []

    public var volatilityBaseline: Double? = nil
}
