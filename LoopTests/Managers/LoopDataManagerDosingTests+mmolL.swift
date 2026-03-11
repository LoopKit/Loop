//
//  LoopDataManagerDosingTests+mmolL.swift
//  LoopTests
//
//  Created to test mmol/L unit handling in dosing calculations
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
@testable import LoopCore
@testable import Loop

extension LoopDataManagerDosingTests {
    
    /// Helper to convert mg/dL ISF values to mmol/L
    /// 1 mmol/L ≈ 18.0182 mg/dL for glucose
    private func mgdLToMmolL(_ mgdL: Double) -> Double {
        return mgdL / 18.0182
    }
    
    /// Helper to convert mg/dL glucose values to mmol/L
    private func glucoseMgdLToMmolL(_ mgdL: Double) -> Double {
        return mgdL / 18.0182
    }
    
    /// Setup test with mmol/L units instead of mg/dL
    /// This mirrors the standard setUp but uses mmol/L for ISF and glucose target
    func setUpMmolL(for test: DosingTestScenario,
                    basalDeliveryState: PumpManagerStatus.BasalDeliveryState? = nil,
                    maxBolus: Double = 10,
                    maxBasalRate: Double = 5.0,
                    dosingStrategy: AutomaticDosingStrategy = .tempBasalOnly)
    {
        let basalRateSchedule = loadBasalRateScheduleFixture("basal_profile")
        
        // Convert ISF from mg/dL to mmol/L
        // Standard test uses 45 mg/dL and 55 mg/dL
        let insulinSensitivitySchedule = InsulinSensitivitySchedule(
            unit: .millimolesPerLiter,
            dailyItems: [
                RepeatingScheduleValue(startTime: 0, value: mgdLToMmolL(45)),      // ~2.5 mmol/L
                RepeatingScheduleValue(startTime: 32400, value: mgdLToMmolL(55))   // ~3.05 mmol/L
            ],
            timeZone: .utcTimeZone
        )!
        
        let carbRatioSchedule = CarbRatioSchedule(
            unit: .gram(),
            dailyItems: [
                RepeatingScheduleValue(startTime: 0.0, value: 10.0),
            ],
            timeZone: .utcTimeZone
        )!
        
        // Convert glucose target range to mmol/L
        // Standard test uses 100-110 mg/dL
        let glucoseTargetRangeScheduleMmolL = GlucoseRangeSchedule(unit: HKUnit.milligramsPerDeciliter, dailyItems: [
                RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 100, maxValue: 110)),
                RepeatingScheduleValue(startTime: TimeInterval(28800), value: DoubleRange(minValue: 90, maxValue: 100)),
                RepeatingScheduleValue(startTime: TimeInterval(75600), value: DoubleRange(minValue: 100, maxValue: 110))
        ], timeZone: .utcTimeZone)!.schedule(for: HKUnit.millimolesPerLiter)        
        
        // Convert suspend threshold to mmol/L (standard is 75 mg/dL)
        let suspendThresholdMmolL = GlucoseThreshold(unit: .millimolesPerLiter, value: glucoseMgdLToMmolL(75))  // ~4.16 mmol/L

        let settings = LoopSettings(
            dosingEnabled: false,
            glucoseTargetRangeSchedule: glucoseTargetRangeScheduleMmolL,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule,
            carbRatioSchedule: carbRatioSchedule,
            maximumBasalRatePerHour: maxBasalRate,
            maximumBolus: maxBolus,
            suspendThreshold: suspendThresholdMmolL,
            automaticDosingStrategy: dosingStrategy
        )
        
        let doseStore = MockDoseStore(for: test)
        doseStore.basalProfile = basalRateSchedule
        doseStore.basalProfileApplyingOverrideHistory = doseStore.basalProfile
        doseStore.sensitivitySchedule = insulinSensitivitySchedule
        let glucoseStore = MockGlucoseStore(for: test)
        let carbStore = MockCarbStore(for: test)
        carbStore.insulinSensitivitySchedule = insulinSensitivitySchedule
        carbStore.carbRatioSchedule = carbRatioSchedule
        
        let currentDate = glucoseStore.latestGlucose!.startDate
        now = currentDate
        
        dosingDecisionStore = MockDosingDecisionStore()
        automaticDosingStatus = AutomaticDosingStatus(automaticDosingEnabled: true, isAutomaticDosingAllowed: true)
        loopDataManager = LoopDataManager(
            lastLoopCompleted: currentDate,
            basalDeliveryState: basalDeliveryState ?? .active(currentDate),
            settings: settings,
            overrideHistory: TemporaryScheduleOverrideHistory(),
            analyticsServicesManager: AnalyticsServicesManager(),
            localCacheDuration: .days(1),
            doseStore: doseStore,
            glucoseStore: glucoseStore,
            carbStore: carbStore,
            dosingDecisionStore: dosingDecisionStore,
            latestStoredSettingsProvider: MockLatestStoredSettingsProvider(),
            now: { currentDate },
            pumpInsulinType: .novolog,
            automaticDosingStatus: automaticDosingStatus,
            trustedTimeOffset: { 0 }
        )
    }
    
    // MARK: - mmol/L Tests
    // These tests should produce the same dosing recommendations as the mg/dL versions

    func testHighAndStable_mmolL() {
        setUpMmolL(for: .highAndStable)
        let predictedGlucoseOutput = loadLocalDateGlucoseEffect("high_and_stable_predicted_glucose")

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var predictedGlucose: [PredictedGlucoseValue]?
        var recommendedBasal: TempBasalRecommendation?
        self.loopDataManager.getLoopState { _, state in
            predictedGlucose = state.predictedGlucose
            recommendedBasal = state.recommendedAutomaticDose?.recommendation.basalAdjustment
            updateGroup.leave()
        }
        updateGroup.wait()

        XCTAssertNotNil(predictedGlucose)
        XCTAssertEqual(predictedGlucoseOutput.count, predictedGlucose!.count)
        
        // Verify predictions match (convert to common unit for comparison)
        for (expected, calculated) in zip(predictedGlucoseOutput, predictedGlucose!) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(
                expected.quantity.doubleValue(for: .milligramsPerDeciliter),
                calculated.quantity.doubleValue(for: .milligramsPerDeciliter),
                accuracy: defaultAccuracy
            )
        }
        
        // Verify basal recommendation matches mg/dL version
        XCTAssertEqual(getDosageForHighAndStableTempBasal(4.63), recommendedBasal!.unitsPerHour, accuracy: defaultAccuracy)
    }
    
    func testHighAndRisingWithCOB_mmolL() {
        setUpMmolL(for: .highAndRisingWithCOB)
        let predictedGlucoseOutput = loadLocalDateGlucoseEffect("high_and_rising_with_cob_predicted_glucose")

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var predictedGlucose: [PredictedGlucoseValue]?
        var recommendedBolus: ManualBolusRecommendation?
        self.loopDataManager.getLoopState { _, state in
            predictedGlucose = state.predictedGlucose
            recommendedBolus = try? state.recommendBolus(consideringPotentialCarbEntry: nil, replacingCarbEntry: nil, considerPositiveVelocityAndRC: true)
            updateGroup.leave()
        }
        updateGroup.wait()

        XCTAssertNotNil(predictedGlucose)
        XCTAssertEqual(predictedGlucoseOutput.count, predictedGlucose!.count)
        
        for (expected, calculated) in zip(predictedGlucoseOutput, predictedGlucose!) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(
                expected.quantity.doubleValue(for: .milligramsPerDeciliter),
                calculated.quantity.doubleValue(for: .milligramsPerDeciliter),
                accuracy: defaultAccuracy
            )
        }

        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(1.6, recommendedBolus!.amount, accuracy: defaultAccuracy)
    }
}
