//
//  IntegralRetrospectiveCorrectionTests.swift
//  LoopTests
//
//  Created by Dragan Maksimovic on 11/2/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
import LoopCore
@testable import Loop

extension XCTestCase {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }
    
    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }
}

public typealias JSONDictionary = [String: Any]

extension ISO8601DateFormatter {
    static func localTimeDateFormatter() -> Self {
        let formatter = self.init()
        
        formatter.formatOptions = .withInternetDateTime
        formatter.formatOptions.subtract(.withTimeZone)
        formatter.timeZone = .current
        
        return formatter
    }
}

struct GlucoseFixtureValue: GlucoseValue {
    let startDate: Date
    let quantity: HKQuantity
    
    init(startDate: Date, quantity: HKQuantity) {
        self.startDate = startDate
        self.quantity = quantity
    }
}

class IntegralRetrospectiveCorrectionTests: XCTestCase {
    
    // IRC parameters, must match values in IntegralRetrospectiveCorrection
    let currentDiscrepancyGain: Double = 1.0
    let persistentDiscrepancyGain: Double = 5.0
    let correctionTimeConstant: TimeInterval = TimeInterval(minutes: 90.0)
    let differentialGain: Double = 2.0
    let integralForget: Double = 0.94595947
    let integralGain: Double = 0.228510979
    let proportionalGain: Double = 0.77148902
    let integrationInterval: TimeInterval = TimeInterval(minutes: 180.0)
    let maximumCorrectionEffectDuration: TimeInterval = TimeInterval(minutes: 240.0)
    
    // Fixture settings
    let insulinSensitivityFixture: HKQuantity = HKQuantity(unit: HKUnit.milligramsPerDeciliter, doubleValue: 80)
    let glucoseTargetFixture: HKQuantity = HKQuantity(unit: HKUnit.milligramsPerDeciliter, doubleValue: 100)
    let basalRateFixture = 0.5
    let glucoseUnit = HKUnit.milligramsPerDeciliter
    
    // Save settings
    let saveInsulinSensitivity = UserDefaults.appGroup?.insulinSensitivitySchedule
    let saveBasalRates = UserDefaults.appGroup?.basalRateSchedule
    let saveSettings = UserDefaults.appGroup?.loopSettings
    
    // Initialize integral retrospective correction
    let integralRC = IntegralRetrospectiveCorrection(TimeInterval.minutes(60.0))
    
    /// Setup fixture settings
    override func setUp() {
        let insulinSensitivity = InsulinSensitivitySchedule(unit: glucoseUnit, dailyItems: [RepeatingScheduleValue(startTime: TimeInterval(0), value: insulinSensitivityFixture.doubleValue(for: glucoseUnit))])
        let basalRate = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: TimeInterval(0), value: basalRateFixture)])
        let glucoseTargetRange = GlucoseRangeSchedule(unit: glucoseUnit, dailyItems: [RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: glucoseTargetFixture.doubleValue(for: glucoseUnit), maxValue: glucoseTargetFixture.doubleValue(for: glucoseUnit)))], overrideRanges: [:])
        UserDefaults.appGroup?.insulinSensitivitySchedule = insulinSensitivity
        UserDefaults.appGroup?.basalRateSchedule = basalRate
        UserDefaults.appGroup?.loopSettings = LoopSettings()
        UserDefaults.appGroup?.loopSettings?.glucoseTargetRangeSchedule = glucoseTargetRange
    }

    /// Restore settings
    override func tearDown() {
        UserDefaults.appGroup?.insulinSensitivitySchedule = saveInsulinSensitivity
        UserDefaults.appGroup?.basalRateSchedule = saveBasalRates
        UserDefaults.appGroup?.loopSettings = saveSettings
    }
    
    /// Function used to load 5-min discrepancy fixtures
    private func loadGlucoseEffectFixture(_ resourceName: String) -> [GlucoseEffect] {
        let fixture: [JSONDictionary] = loadFixture(resourceName)
        let dateFormatter = ISO8601DateFormatter.localTimeDateFormatter()
        
        return fixture.map {
            return GlucoseEffect(startDate: dateFormatter.date(from: $0["date"] as! String)!, quantity: HKQuantity(unit: HKUnit(from: $0["unit"] as! String), doubleValue:$0["value"] as! Double))
        }
    }
    
    /// Print glucose effects for debugging purposes
    private func printEffectFixture(_ glucoseEffect: [GlucoseEffect]) {
        let unit = self.glucoseUnit
        
        print("\n\n")
        print(String(data: try! JSONSerialization.data(
            withJSONObject: glucoseEffect.map({ (value) -> [String: Any] in
                return [
                    "date": String(describing: value.startDate),
                    "value": value.quantity.doubleValue(for: unit),
                    "unit": unit.unitString
                ]
            }),
            options: .prettyPrinted), encoding: .utf8)!)
        print("\n\n")
    }
    
    /// Print glucose changes for debugging purposes
    private func printChangeFixture(_ glucoseChange: [GlucoseChange]) {
        let unit = self.glucoseUnit
        
        print("\n\n")
        print(String(data: try! JSONSerialization.data(
            withJSONObject: glucoseChange.map({ (value) -> [String: Any] in
                return [
                    "start": String(describing: value.startDate),
                    "end": String(describing: value.endDate),
                    "value": value.quantity.doubleValue(for: unit),
                    "unit": unit.unitString
                ]
            }),
            options: .prettyPrinted), encoding: .utf8)!)
        print("\n\n")
    }
    
    /// Real-time sampled glucose discrepancies
    func testSampledDiscrepancies() {
        let retrospectiveGlucoseDiscrepancies = loadGlucoseEffectFixture("glucose_discrepancies_sampled")
        let retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepancies.combinedSums(of: (saveSettings?.retrospectiveCorrectionGroupingInterval)! * 1.01)
        let glucoseDate = (retrospectiveGlucoseDiscrepanciesSummed.last?.endDate)!
        let glucose = GlucoseFixtureValue(startDate: glucoseDate, quantity: HKQuantity(unit: glucoseUnit, doubleValue: 150))
        let glucoseCorrectionEffect = integralRC.updateRetrospectiveCorrectionEffect(glucose, retrospectiveGlucoseDiscrepanciesSummed)
        let totalRetrospectiveCorrection = integralRC.totalGlucoseCorrectionEffect
        if let totalCorrectionValue = totalRetrospectiveCorrection?.doubleValue(for: glucoseUnit) {
            XCTAssertEqual(-9.0213, totalCorrectionValue, accuracy: 0.001, "Given sampled glucose discrepancies, IRC returned unexpected total correction value")
        } else {
            XCTFail("Given sampled glucose discrepancies, IRC returned nil")
        }
        XCTAssertEqual(25, glucoseCorrectionEffect.count, "Given sampled glucose discrepancies, IRC returned unexpected glucose correction length")
    }
    
    /// Discrepanies are stale compared to the latest glucose
    func testStaleDiscrepancies() {
        let retrospectiveGlucoseDiscrepancies = loadGlucoseEffectFixture("glucose_discrepancies_sampled")
        let retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepancies.combinedSums(of: (saveSettings?.retrospectiveCorrectionGroupingInterval)! * 1.01)
        let date = (retrospectiveGlucoseDiscrepanciesSummed.last?.endDate)!
        let staleMinutes = (saveSettings?.recencyInterval.minutes)! + 1.0
        let glucoseDate = date.addingTimeInterval(.minutes(staleMinutes))
        let glucose = GlucoseFixtureValue(startDate: glucoseDate, quantity: HKQuantity(unit: glucoseUnit, doubleValue: 120))
        _ = integralRC.updateRetrospectiveCorrectionEffect(glucose, retrospectiveGlucoseDiscrepanciesSummed)
        let totalRetrospectiveCorrection = integralRC.totalGlucoseCorrectionEffect
        XCTAssertNil(totalRetrospectiveCorrection, "IRC should return nil if discrepancies are stale compared to glucose by more than recencyInterval")
    }

    /// Constant discrepanies, integral effect within limits
    func testConstantPositiveDiscrepancies() {
        let retrospectiveGlucoseDiscrepancies = loadGlucoseEffectFixture("glucose_discrepancies_constant_positive")
        var retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepancies.combinedSums(of: (saveSettings?.retrospectiveCorrectionGroupingInterval)! * 1.01)
        let glucoseDate = (retrospectiveGlucoseDiscrepanciesSummed.last?.endDate)!
        let retrospectionIntegrationStart = glucoseDate.addingTimeInterval(-.minutes(integrationInterval.minutes - 1.0))
        retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepanciesSummed.filterDateRange(retrospectionIntegrationStart, nil)
        let glucose = GlucoseFixtureValue(startDate: glucoseDate, quantity: HKQuantity(unit: glucoseUnit, doubleValue: 180))
        let glucoseCorrectionEffect = integralRC.updateRetrospectiveCorrectionEffect(glucose, retrospectiveGlucoseDiscrepanciesSummed)

        // Expected total correction based on IRC filter math
        let expectedCorrectionNormalizedValue = 1.0 - exp( -integrationInterval.minutes / correctionTimeConstant.minutes )

        var totalCorrectionNormalizedValue = 0.0
        if let totalCorrection = integralRC.totalGlucoseCorrectionEffect,
            let discrepancy = retrospectiveGlucoseDiscrepanciesSummed.last {
            totalCorrectionNormalizedValue = totalCorrection.doubleValue(for: glucoseUnit) / discrepancy.quantity.doubleValue(for: glucoseUnit) / persistentDiscrepancyGain
            XCTAssertEqual(totalCorrectionNormalizedValue, expectedCorrectionNormalizedValue, accuracy: 0.025, "Given constant discrepancies, IRC returned unexpected normalized correction value")
        } else {
            XCTFail("Given constant glucose discrepancies, IRC returned nil")
        }
        
        let expectedCount = Int(maximumCorrectionEffectDuration.minutes / 5.0) + 1
        XCTAssertEqual(expectedCount, glucoseCorrectionEffect.count, "Given constant glucose discrepancies, IRC returned unexpected glucose correction length")
    }
    
    /// Constant discrepanies, integral effect hits a safety limit
    func testConstantPositiveDiscrepanciesIntegralLimit() {
        let retrospectiveGlucoseDiscrepancies = loadGlucoseEffectFixture("glucose_discrepancies_constant_positive")
        var retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepancies.combinedSums(of: (saveSettings?.retrospectiveCorrectionGroupingInterval)! * 1.01)
        let glucoseDate = (retrospectiveGlucoseDiscrepanciesSummed.last?.endDate)!
        let retrospectionIntegrationStart = glucoseDate.addingTimeInterval(-.minutes(integrationInterval.minutes - 1.0))
        retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepanciesSummed.filterDateRange(retrospectionIntegrationStart, nil)
        let glucose = GlucoseFixtureValue(startDate: glucoseDate, quantity: HKQuantity(unit: glucoseUnit, doubleValue: 100))
        let glucoseCorrectionEffect = integralRC.updateRetrospectiveCorrectionEffect(glucose, retrospectiveGlucoseDiscrepanciesSummed)
        
        if let totalCorrection = integralRC.totalGlucoseCorrectionEffect,
            let discrepancy = retrospectiveGlucoseDiscrepanciesSummed.last {
            let totalCorrectionValue = totalCorrection.doubleValue(for: glucoseUnit)
            let discrepancyValue = discrepancy.quantity.doubleValue(for: glucoseUnit)
            let integralEffectLimit = insulinSensitivityFixture.doubleValue(for: glucoseUnit) * basalRateFixture
            let expectedTotalCorrectionValue = proportionalGain * discrepancyValue + integralEffectLimit
            XCTAssertEqual(totalCorrectionValue, expectedTotalCorrectionValue, accuracy: 0.001, "Given constant glucose discrepancies with integral effect limit, IRC returned unexpected glucose correction value")
        } else {
            XCTFail("Given constant glucose discrepancies with integral effect limit, IRC returned nil")
        }
        
        let expectedCount = Int(maximumCorrectionEffectDuration.minutes / 5.0) + 1
        XCTAssertEqual(expectedCount, glucoseCorrectionEffect.count, "Given constant glucose discrepancies with integral effect limit, IRC returned unexpected glucose correction length")
    }
    
    func testSingeNegativeDiscrepancy() {
        let retrospectiveGlucoseDiscrepancies = loadGlucoseEffectFixture("glucose_discrepancies_single_same_sign")
        let retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepancies.combinedSums(of: (saveSettings?.retrospectiveCorrectionGroupingInterval)! * 1.01)
        let glucoseDate = (retrospectiveGlucoseDiscrepanciesSummed.last?.endDate)!
        let glucose = GlucoseFixtureValue(startDate: glucoseDate, quantity: HKQuantity(unit: glucoseUnit, doubleValue: 100))
        let glucoseCorrectionEffect = integralRC.updateRetrospectiveCorrectionEffect(glucose, retrospectiveGlucoseDiscrepanciesSummed)

        if let totalCorrection = integralRC.totalGlucoseCorrectionEffect,
            let lastDiscrepancy = retrospectiveGlucoseDiscrepanciesSummed.last {
            let totalCorrectionValue = totalCorrection.doubleValue(for: glucoseUnit)
            let expectedTotalCorrectionValue = lastDiscrepancy.quantity.doubleValue(for: glucoseUnit)
            XCTAssertEqual(totalCorrectionValue, expectedTotalCorrectionValue, accuracy: 0.00001, "Given single negative discrepancy, IRC returned unexpected glucose correction value")
        } else {
            XCTFail("Given single negative discrepancy, IRC returned nil")
        }

        let expectedCount = Int(60.0 / 5.0) + 1
        XCTAssertEqual(expectedCount, glucoseCorrectionEffect.count, "Given constant glucose discrepancies with integral effect limit, IRC returned unexpected glucose correction length")
    }

    func testEmptyDiscrepancyArray() {
        let retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange] = []
        let glucoseDate = Date()
        let glucose = GlucoseFixtureValue(startDate: glucoseDate, quantity: HKQuantity(unit: glucoseUnit, doubleValue: 100))
        let glucoseEffect = integralRC.updateRetrospectiveCorrectionEffect(glucose, retrospectiveGlucoseDiscrepanciesSummed)
        XCTAssertEqual(glucoseEffect, [], "Given empty discrepancy array, IRC should return empty effects array")
    }
    
    func testSingeDiscrepancy() {
        let retrospectiveGlucoseDiscrepancies = loadGlucoseEffectFixture("glucose_discrepancies_sampled")
        var retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepancies.combinedSums(of: (saveSettings?.retrospectiveCorrectionGroupingInterval)! * 1.01)
        let glucoseDate = (retrospectiveGlucoseDiscrepanciesSummed.last?.endDate)!
        let glucose = GlucoseFixtureValue(startDate: glucoseDate, quantity: HKQuantity(unit: glucoseUnit, doubleValue: 100))
        retrospectiveGlucoseDiscrepanciesSummed = [retrospectiveGlucoseDiscrepanciesSummed.last] as! [GlucoseChange]
        let glucoseCorrectionEffect = integralRC.updateRetrospectiveCorrectionEffect(glucose, retrospectiveGlucoseDiscrepanciesSummed)

        if let totalCorrection = integralRC.totalGlucoseCorrectionEffect,
            let lastDiscrepancy = retrospectiveGlucoseDiscrepanciesSummed.last {
            let totalCorrectionValue = totalCorrection.doubleValue(for: glucoseUnit)
            let expectedTotalCorrectionValue = lastDiscrepancy.quantity.doubleValue(for: glucoseUnit)
            XCTAssertEqual(totalCorrectionValue, expectedTotalCorrectionValue, accuracy: 0.00001, "Given single discrepancy, IRC returned unexpected glucose correction value")
        } else {
            XCTFail("Given single discrepancy, IRC returned nil")
        }
        
        let expectedCount = Int(60.0 / 5.0) + 1
        XCTAssertEqual(expectedCount, glucoseCorrectionEffect.count, "Given single doscrepancy, IRC returned unexpected glucose correction length")
    }

    func testSingleContiguousDiscrepancy() {
        let retrospectiveGlucoseDiscrepancies = loadGlucoseEffectFixture("glucose_discrepancies_sampled")
        var retrospectiveGlucoseDiscrepanciesSummed = retrospectiveGlucoseDiscrepancies.combinedSums(of: (saveSettings?.retrospectiveCorrectionGroupingInterval)! * 1.01)
        let glucoseDate = (retrospectiveGlucoseDiscrepanciesSummed.last?.endDate)!
        let glucose = GlucoseFixtureValue(startDate: glucoseDate, quantity: HKQuantity(unit: glucoseUnit, doubleValue: 100))
        let numberOfDiscrepancies = retrospectiveGlucoseDiscrepanciesSummed.count
        retrospectiveGlucoseDiscrepanciesSummed.remove(at: numberOfDiscrepancies - 2)
        retrospectiveGlucoseDiscrepanciesSummed.remove(at: numberOfDiscrepancies - 3)
        retrospectiveGlucoseDiscrepanciesSummed.remove(at: numberOfDiscrepancies - 4)
        let glucoseCorrectionEffect = integralRC.updateRetrospectiveCorrectionEffect(glucose, retrospectiveGlucoseDiscrepanciesSummed)
        
        if let totalCorrection = integralRC.totalGlucoseCorrectionEffect,
            let lastDiscrepancy = retrospectiveGlucoseDiscrepanciesSummed.last {
            let totalCorrectionValue = totalCorrection.doubleValue(for: glucoseUnit)
            let expectedTotalCorrectionValue = lastDiscrepancy.quantity.doubleValue(for: glucoseUnit)
            XCTAssertEqual(totalCorrectionValue, expectedTotalCorrectionValue, accuracy: 0.00001, "Given single contiguous discrepancy, IRC returned unexpected glucose correction value")
        } else {
            XCTFail("Given single contiguous discrepancy, IRC returned nil")
        }
        
        let expectedCount = Int(60.0 / 5.0) + 1
        XCTAssertEqual(expectedCount, glucoseCorrectionEffect.count, "Given single contiguous discrepancy, IRC returned unexpected glucose correction length")
    }

}
