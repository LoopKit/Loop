//
//  SimpleBolusCalculatorTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 9/28/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation

import XCTest
import HealthKit
import LoopKit

@testable import Loop

class SimpleBolusCalculatorTests: XCTestCase {
    
    let correctionRangeSchedule = GlucoseRangeSchedule(
        unit: .milligramsPerDeciliter,
        dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100.0, maxValue: 110.0))
    ])!

    let carbRatioSchedule = CarbRatioSchedule(unit: .gram(), dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10)])!
    let sensitivitySchedule = InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: 80)])!

    func testMealRecommendation() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: HKQuantity(unit: .gram(), doubleValue: 40),
            manualGlucose: nil,
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: 0),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(4.0, recommendation.doubleValue(for: .internationalUnit()))
    }
    
    func testCorrectionRecommendation() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: nil,
            manualGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 180),
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: 0),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(0.94, recommendation.doubleValue(for: .internationalUnit()), accuracy: 0.01)
    }
    
    func testCorrectionRecommendationWithIOB() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: nil,
            manualGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 180),
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: 10),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(0.0, recommendation.doubleValue(for: .internationalUnit()), accuracy: 0.01)
    }
    
    func testCorrectionRecommendationWithNegativeIOB() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: nil,
            manualGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 180),
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: -1),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(0.94, recommendation.doubleValue(for: .internationalUnit()), accuracy: 0.01)
    }


    func testCorrectionRecommendationWhenInRange() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: nil,
            manualGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 110),
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: 0),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(0.0, recommendation.doubleValue(for: .internationalUnit()), accuracy: 0.01)
    }

    func testCorrectionAndCarbsRecommendationWhenBelowRange() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: HKQuantity(unit: .gram(), doubleValue: 40),
            manualGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 70),
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: 0),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(3.56, recommendation.doubleValue(for: .internationalUnit()), accuracy: 0.01)
    }
    
    func testCarbsEntryWithActiveInsulinAndNoGlucose() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: HKQuantity(unit: .gram(), doubleValue: 20),
            manualGlucose: nil,
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: 4),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(2, recommendation.doubleValue(for: .internationalUnit()), accuracy: 0.01)
    }
    
    func testCarbsEntryWithActiveInsulinAndCarbsAndNoCorrection() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: HKQuantity(unit: .gram(), doubleValue: 20),
            manualGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 100),
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: 4),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(2, recommendation.doubleValue(for: .internationalUnit()), accuracy: 0.01)
    }
    
    func testPredictionShouldBeZeroWhenGlucoseBelowMealBolusRecommendationLimit() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: HKQuantity(unit: .gram(), doubleValue: 20),
            manualGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 54),
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: 4),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(0, recommendation.doubleValue(for: .internationalUnit()), accuracy: 0.01)
    }
    
    func testPredictionShouldBeZeroWhenGlucoseBelowBolusRecommendationLimit() {
        let recommendation = SimpleBolusCalculator.recommendedInsulin(
            mealCarbs: nil,
            manualGlucose: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 69),
            activeInsulin: HKQuantity(unit: .internationalUnit(), doubleValue: 4),
            carbRatioSchedule: carbRatioSchedule,
            correctionRangeSchedule: correctionRangeSchedule,
            sensitivitySchedule: sensitivitySchedule)
        
        XCTAssertEqual(0, recommendation.doubleValue(for: .internationalUnit()), accuracy: 0.01)
    }

}
