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

    public init(glucoseHistory: [StoredGlucoseSample], doses: [SimpleInsulinDose], carbEntries: [StoredCarbEntry],
                predictionStart: Date, basal: [AbsoluteScheduleValue<Double>], sensitivity: [AbsoluteScheduleValue<LoopQuantity>],
                carbRatio: [AbsoluteScheduleValue<Double>], target: GlucoseRangeTimeline, suspendThreshold: LoopQuantity? = nil,
                maxBolus: Double, maxBasalRate: Double, useIntegralRetrospectiveCorrection: Bool,
                includePositiveVelocityAndRC: Bool, carbAbsorptionModel: CarbAbsorptionModel,
                recommendationInsulinModel: InsulinModel, recommendationType: DoseRecommendationType,
                automaticBolusApplicationFactor: Double? = nil, maxActiveInsulinMultiplier: Double? = nil,
                gradualTransitionsThreshold: Double? = nil, experiments: Set<ExperimentOption> = [],
                volatilityBaseline: Double? = nil) {
        self.glucoseHistory = glucoseHistory
        self.doses = doses
        self.carbEntries = carbEntries
        self.predictionStart = predictionStart
        self.basal = basal
        self.sensitivity = sensitivity
        self.carbRatio = carbRatio
        self.target = target
        self.suspendThreshold = suspendThreshold
        self.maxBolus = maxBolus
        self.maxBasalRate = maxBasalRate
        self.useIntegralRetrospectiveCorrection = useIntegralRetrospectiveCorrection
        self.includePositiveVelocityAndRC = includePositiveVelocityAndRC
        self.carbAbsorptionModel = carbAbsorptionModel
        self.recommendationInsulinModel = recommendationInsulinModel
        self.recommendationType = recommendationType
        self.automaticBolusApplicationFactor = automaticBolusApplicationFactor
        self.maxActiveInsulinMultiplier = maxActiveInsulinMultiplier
        self.gradualTransitionsThreshold = gradualTransitionsThreshold
        self.experiments = experiments
        self.volatilityBaseline = volatilityBaseline
    }
}
