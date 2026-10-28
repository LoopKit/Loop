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
