//
//  LoopDataManagerTests.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/4/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
@testable import LoopCore
@testable import Loop

public typealias JSONDictionary = [String: Any]

enum DataManagerTestType {
    case flatAndStable
    case highAndStable
    case highAndRisingWithCOB
    case lowAndFallingWithCOB
    case lowWithLowTreatment
    case highAndFalling
}

extension TimeZone {
    static var fixtureTimeZone: TimeZone {
        return TimeZone(secondsFromGMT: 25200)!
    }
    
    static var utcTimeZone: TimeZone {
        return TimeZone(secondsFromGMT: 0)!
    }
}

extension ISO8601DateFormatter {
    static func localTimeDate(timeZone: TimeZone = .fixtureTimeZone) -> Self {
        let formatter = self.init()

        formatter.formatOptions = .withInternetDateTime
        formatter.formatOptions.subtract(.withTimeZone)
        formatter.timeZone = timeZone

        return formatter
    }
}

class LoopDataManagerDosingTests: XCTestCase {
    // MARK: Constants for testing
    let retrospectiveCorrectionEffectDuration = TimeInterval(hours: 1)
    let retrospectiveCorrectionGroupingInterval = 1.01
    let retrospectiveCorrectionGroupingIntervalMultiplier = 1.01
    let inputDataRecencyInterval = TimeInterval(minutes: 15)
    let dateFormatter = ISO8601DateFormatter.localTimeDate()
    let defaultAccuracy = 1.0 / 40.0
    
    // MARK: Settings
    let maxBasalRate = 5.0
    let maxBolus = 10.0
    
    var suspendThreshold: GlucoseThreshold {
        return GlucoseThreshold(unit: HKUnit.milligramsPerDeciliter, value: 75)
    }
    
    var adultExponentialInsulinModel: InsulinModel = ExponentialInsulinModel(actionDuration: 21600.0, peakActivityTime: 4500.0)

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule {
        return GlucoseRangeSchedule(unit: HKUnit.milligramsPerDeciliter, dailyItems: [
            RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 100, maxValue: 110)),
            RepeatingScheduleValue(startTime: TimeInterval(28800), value: DoubleRange(minValue: 90, maxValue: 100)),
            RepeatingScheduleValue(startTime: TimeInterval(75600), value: DoubleRange(minValue: 100, maxValue: 110))
        ], timeZone: .utcTimeZone)!
    }
    
    // MARK: Mock stores
    var loopDataManager: LoopDataManager!
    
    func setUp(for test: DataManagerTestType, basalDeliveryState: PumpManagerStatus.BasalDeliveryState? = nil) {
        let settings = LoopSettings(
            dosingEnabled: false,
            glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
            maximumBasalRatePerHour: maxBasalRate,
            maximumBolus: maxBolus,
            suspendThreshold: suspendThreshold
        )
        
        let doseStore = MockDoseStore(for: test)
        doseStore.basalProfileApplyingOverrideHistory = loadBasalRateScheduleFixture("basal_profile")
        let glucoseStore = MockGlucoseStore(for: test)
        let carbStore = MockCarbStore(for: test)
        
        let currentDate = glucoseStore.latestGlucose!.startDate
        
        loopDataManager = LoopDataManager(
            lastLoopCompleted: currentDate,
            basalDeliveryState: basalDeliveryState ?? .active(currentDate),
            settings: settings,
            overrideHistory: TemporaryScheduleOverrideHistory(),
            lastPumpEventsReconciliation: nil, // this date is only used to init the doseStore if a DoseStoreProtocol isn't passed in, so this date can be nil
            analyticsServicesManager: AnalyticsServicesManager(),
            localCacheDuration: .days(1),
            doseStore: doseStore,
            glucoseStore: glucoseStore,
            carbStore: carbStore,
            dosingDecisionStore: MockDosingDecisionStore(),
            settingsStore: MockSettingsStore(),
            now: { currentDate },
            pumpInsulinType: .novolog,
            automaticDosingStatus: AutomaticDosingStatus(isClosedLoop: false, isClosedLoopAllowed: false)
        )
    }
    
    override func tearDownWithError() throws {
        loopDataManager = nil
    }
    
    // MARK: Functions to load fixtures
    func loadGlucoseEffect(_ name: String) -> [GlucoseEffect] {
        let fixture: [JSONDictionary] = loadFixture(name)
        let dateFormatter = ISO8601DateFormatter.localTimeDate()

        return fixture.map {
            return GlucoseEffect(startDate: dateFormatter.date(from: $0["date"] as! String)!, quantity: HKQuantity(unit: HKUnit(from: $0["unit"] as! String), doubleValue:$0["amount"] as! Double))
        }
    }
    
    // MARK: Tests
    func testFlatAndStable() {
        setUp(for: .flatAndStable)
        let predictedGlucoseOutput = loadGlucoseEffect("flat_and_stable_predicted_glucose")

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var predictedGlucose: [PredictedGlucoseValue]?
        var recommendedDose: AutomaticDoseRecommendation?
        self.loopDataManager.getLoopState { _, state in
            predictedGlucose = state.predictedGlucose
            recommendedDose = state.recommendedAutomaticDose?.recommendation
            updateGroup.leave()
        }
        // We need to wait until the task completes to get outputs
        updateGroup.wait()

        XCTAssertNotNil(predictedGlucose)
        XCTAssertEqual(predictedGlucoseOutput.count, predictedGlucose!.count)
        
        for (expected, calculated) in zip(predictedGlucoseOutput, predictedGlucose!) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.quantity.doubleValue(for: .milligramsPerDeciliter), calculated.quantity.doubleValue(for: .milligramsPerDeciliter), accuracy: defaultAccuracy)
        }
        
        let recommendedTempBasal = recommendedDose?.basalAdjustment

        XCTAssertEqual(1.40, recommendedTempBasal!.unitsPerHour, accuracy: defaultAccuracy)
    }
    
    func testHighAndStable() {
        setUp(for: .highAndStable)
        let predictedGlucoseOutput = loadGlucoseEffect("high_and_stable_predicted_glucose")

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var predictedGlucose: [PredictedGlucoseValue]?
        var recommendedBasal: TempBasalRecommendation?
        self.loopDataManager.getLoopState { _, state in
            predictedGlucose = state.predictedGlucose
            recommendedBasal = state.recommendedAutomaticDose?.recommendation.basalAdjustment
            updateGroup.leave()
        }
        // We need to wait until the task completes to get outputs
        updateGroup.wait()

        XCTAssertNotNil(predictedGlucose)
        XCTAssertEqual(predictedGlucoseOutput.count, predictedGlucose!.count)
        
        for (expected, calculated) in zip(predictedGlucoseOutput, predictedGlucose!) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.quantity.doubleValue(for: .milligramsPerDeciliter), calculated.quantity.doubleValue(for: .milligramsPerDeciliter), accuracy: defaultAccuracy)
        }

        XCTAssertEqual(4.63, recommendedBasal!.unitsPerHour, accuracy: defaultAccuracy)
    }
    
    func testHighAndFalling() {
        setUp(for: .highAndFalling)
        let predictedGlucoseOutput = loadGlucoseEffect("high_and_falling_predicted_glucose")

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var predictedGlucose: [PredictedGlucoseValue]?
        var recommendedTempBasal: TempBasalRecommendation?
        self.loopDataManager.getLoopState { _, state in
            predictedGlucose = state.predictedGlucose
            recommendedTempBasal = state.recommendedAutomaticDose?.recommendation.basalAdjustment
            updateGroup.leave()
        }
        // We need to wait until the task completes to get outputs
        updateGroup.wait()

        XCTAssertNotNil(predictedGlucose)
        XCTAssertEqual(predictedGlucoseOutput.count, predictedGlucose!.count)
        
        for (expected, calculated) in zip(predictedGlucoseOutput, predictedGlucose!) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.quantity.doubleValue(for: .milligramsPerDeciliter), calculated.quantity.doubleValue(for: .milligramsPerDeciliter), accuracy: defaultAccuracy)
        }

        XCTAssertEqual(0, recommendedTempBasal!.unitsPerHour, accuracy: defaultAccuracy)
    }
    
    func testHighAndRisingWithCOB() {
        setUp(for: .highAndRisingWithCOB)
        let predictedGlucoseOutput = loadGlucoseEffect("high_and_rising_with_cob_predicted_glucose")

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var predictedGlucose: [PredictedGlucoseValue]?
        var recommendedBolus: ManualBolusRecommendation?
        self.loopDataManager.getLoopState { _, state in
            predictedGlucose = state.predictedGlucose
            recommendedBolus = state.recommendedBolus?.recommendation
            updateGroup.leave()
        }
        // We need to wait until the task completes to get outputs
        updateGroup.wait()

        XCTAssertNotNil(predictedGlucose)
        XCTAssertEqual(predictedGlucoseOutput.count, predictedGlucose!.count)
        
        for (expected, calculated) in zip(predictedGlucoseOutput, predictedGlucose!) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.quantity.doubleValue(for: .milligramsPerDeciliter), calculated.quantity.doubleValue(for: .milligramsPerDeciliter), accuracy: defaultAccuracy)
        }

        XCTAssertEqual(1.6, recommendedBolus!.amount, accuracy: defaultAccuracy)
    }
    
    func testLowAndFallingWithCOB() {
        setUp(for: .lowAndFallingWithCOB)
        let predictedGlucoseOutput = loadGlucoseEffect("low_and_falling_predicted_glucose")

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var predictedGlucose: [PredictedGlucoseValue]?
        var recommendedTempBasal: TempBasalRecommendation?
        self.loopDataManager.getLoopState { _, state in
            predictedGlucose = state.predictedGlucose
            recommendedTempBasal = state.recommendedAutomaticDose?.recommendation.basalAdjustment
            updateGroup.leave()
        }
        // We need to wait until the task completes to get outputs
        updateGroup.wait()

        XCTAssertNotNil(predictedGlucose)
        XCTAssertEqual(predictedGlucoseOutput.count, predictedGlucose!.count)
        
        for (expected, calculated) in zip(predictedGlucoseOutput, predictedGlucose!) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.quantity.doubleValue(for: .milligramsPerDeciliter), calculated.quantity.doubleValue(for: .milligramsPerDeciliter), accuracy: defaultAccuracy)
        }

        XCTAssertEqual(0, recommendedTempBasal!.unitsPerHour, accuracy: defaultAccuracy)
    }
    
    func testLowWithLowTreatment() {
        setUp(for: .lowWithLowTreatment)
        let predictedGlucoseOutput = loadGlucoseEffect("low_with_low_treatment_predicted_glucose")

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var predictedGlucose: [PredictedGlucoseValue]?
        var recommendedTempBasal: TempBasalRecommendation?
        self.loopDataManager.getLoopState { _, state in
            predictedGlucose = state.predictedGlucose
            recommendedTempBasal = state.recommendedAutomaticDose?.recommendation.basalAdjustment
            updateGroup.leave()
        }
        // We need to wait until the task completes to get outputs
        updateGroup.wait()

        XCTAssertNotNil(predictedGlucose)
        XCTAssertEqual(predictedGlucoseOutput.count, predictedGlucose!.count)
        
        for (expected, calculated) in zip(predictedGlucoseOutput, predictedGlucose!) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.quantity.doubleValue(for: .milligramsPerDeciliter), calculated.quantity.doubleValue(for: .milligramsPerDeciliter), accuracy: defaultAccuracy)
        }

        XCTAssertEqual(0, recommendedTempBasal!.unitsPerHour, accuracy: defaultAccuracy)
    }
    
    class MockDelegate: LoopDataManagerDelegate {
        var recommendation: AutomaticDoseRecommendation?
        var error: Error?
        func loopDataManager(_ manager: LoopDataManager, didRecommend automaticDose: (recommendation: AutomaticDoseRecommendation, date: Date), completion: @escaping (Error?) -> Void) {
            self.recommendation = automaticDose.recommendation
            completion(error)
        }
        func loopDataManager(_ manager: LoopDataManager, roundBasalRate unitsPerHour: Double) -> Double { unitsPerHour }
        func loopDataManager(_ manager: LoopDataManager, roundBolusVolume units: Double) -> Double { units }
        var pumpManagerStatus: PumpManagerStatus?
        var cgmManagerStatus: CGMManagerStatus?
    }

    func waitOnDataQueue(timeout: TimeInterval = 1.0) {
        let e = expectation(description: "dataQueue")
        loopDataManager.getLoopState { _, _ in
            e.fulfill()
        }
        wait(for: [e], timeout: timeout)
    }
    
    func testValidateMaxTempBasalDoesntCancelTempBasalIfHigher() {
        let dose = DoseEntry(type: .tempBasal, startDate: Date(), endDate: nil, value: 3.0, unit: .unitsPerHour, deliveredUnits: nil, description: nil, syncIdentifier: nil, scheduledBasalRate: nil)
        setUp(for: .highAndStable, basalDeliveryState: .tempBasal(dose))
        // This wait is working around the issue presented by LoopDataManager.init().  It cancels the temp basal if
        // `isClosedLoop` is false (which it is from `setUp` above). When that happens, it races with
        // `maxTempBasalSavePreflight` below.  This ensures only one happens at a time.
        waitOnDataQueue()
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate
        var error: Error?
        let exp = expectation(description: #function)
        XCTAssertNil(delegate.recommendation)
        loopDataManager.maxTempBasalSavePreflight(unitsPerHour: 5.0) {
            error = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertNil(error)
        XCTAssertNil(delegate.recommendation)
    }
    
    func testValidateMaxTempBasalCancelsTempBasalIfLower() {
        let dose = DoseEntry(type: .tempBasal, startDate: Date(), endDate: nil, value: 5.0, unit: .unitsPerHour, deliveredUnits: nil, description: nil, syncIdentifier: nil, scheduledBasalRate: nil)
        setUp(for: .highAndStable, basalDeliveryState: .tempBasal(dose))
        // This wait is working around the issue presented by LoopDataManager.init().  It cancels the temp basal if
        // `isClosedLoop` is false (which it is from `setUp` above). When that happens, it races with
        // `maxTempBasalSavePreflight` below.  This ensures only one happens at a time.
        waitOnDataQueue()
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate
        var error: Error?
        let exp = expectation(description: #function)
        XCTAssertNil(delegate.recommendation)
        loopDataManager.maxTempBasalSavePreflight(unitsPerHour: 3.0) {
            error = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertNil(error)
        XCTAssertEqual(TempBasalRecommendation.cancel, delegate.recommendation?.basalAdjustment)
    }
    
    func testChangingMaxBasalCausesLoop() {
        setUp(for: .highAndStable)
        waitOnDataQueue()
        var looped = false
        let exp = expectation(description: #function)
        let observer = NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: nil, queue: nil) { _ in
            looped = true
            exp.fulfill()
        }
        XCTAssertFalse(looped)
        loopDataManager.mutateSettings { $0.maximumBasalRatePerHour = 2.0 }
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(looped)
        NotificationCenter.default.removeObserver(observer)
    }
}

extension LoopDataManagerDosingTests {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }
    
    func loadBasalRateScheduleFixture(_ resourceName: String) -> BasalRateSchedule {
        let fixture: [JSONDictionary] = loadFixture(resourceName)

        let items = fixture.map {
            return RepeatingScheduleValue(startTime: TimeInterval(minutes: $0["minutes"] as! Double), value: $0["rate"] as! Double)
        }

        return BasalRateSchedule(dailyItems: items, timeZone: .utcTimeZone)!
    }
}
