//
//  LoopDataManagerDosingTests.swift
//  LoopTests
//
//  Created by Anna Quinlan on 10/19/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
@testable import LoopCore
@testable import Loop

class MockDelegate: LoopDataManagerDelegate {
    let pumpManager = MockPumpManager()
    
    var bolusUnits: Double?
    func loopDataManager(_ manager: Loop.LoopDataManager, estimateBolusDuration units: Double) -> TimeInterval? {
        self.bolusUnits = units
        return pumpManager.estimatedDuration(toBolus: units)
    }
    
    var recommendation: AutomaticDoseRecommendation?
    var error: LoopError?
    func loopDataManager(_ manager: LoopDataManager, didRecommend automaticDose: (recommendation: AutomaticDoseRecommendation, date: Date), completion: @escaping (LoopError?) -> Void) {
        self.recommendation = automaticDose.recommendation
        completion(error)
    }
    func roundBasalRate(unitsPerHour: Double) -> Double { Double(Int(unitsPerHour / 0.05)) * 0.05 }
    func roundBolusVolume(units: Double) -> Double { Double(Int(units / 0.05)) * 0.05 }
    var pumpManagerStatus: PumpManagerStatus?
    var cgmManagerStatus: CGMManagerStatus?
    var pumpStatusHighlight: DeviceStatusHighlight?
}

class LoopDataManagerDosingTests: LoopDataManagerTests {
    // MARK: Functions to load fixtures
    func loadLocalDateGlucoseEffect(_ name: String) -> [GlucoseEffect] {
        let fixture: [JSONDictionary] = loadFixture(name)
        let localDateFormatter = ISO8601DateFormatter.localTimeDate()

        return fixture.map {
            return GlucoseEffect(startDate: localDateFormatter.date(from: $0["date"] as! String)!, quantity: HKQuantity(unit: HKUnit(from: $0["unit"] as! String), doubleValue:$0["amount"] as! Double))
        }
    }

    func loadPredictedGlucoseFixture(_ name: String) -> [PredictedGlucoseValue] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let url = bundle.url(forResource: name, withExtension: "json")!
        return try! decoder.decode([PredictedGlucoseValue].self, from: try! Data(contentsOf: url))
    }

    // MARK: Tests
    func testForecastFromLiveCaptureInputData() {

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let url = bundle.url(forResource: "live_capture_input", withExtension: "json")!
        let predictionInput = try! decoder.decode(LoopPredictionInput.self, from: try! Data(contentsOf: url))

        // Therapy settings in the "live capture" input only have one value, so we can fake some schedules
        // from the first entry of each therapy setting's history.
        let basalRateSchedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: predictionInput.settings.basal.first!.value)
        ])
        let insulinSensitivitySchedule = InsulinSensitivitySchedule(
            unit: .milligramsPerDeciliter,
            dailyItems: [
                RepeatingScheduleValue(startTime: 0, value: predictionInput.settings.sensitivity.first!.value.doubleValue(for: .milligramsPerDeciliter))
            ],
            timeZone: .utcTimeZone
        )!
        let carbRatioSchedule = CarbRatioSchedule(
            unit: .gram(),
            dailyItems: [
                RepeatingScheduleValue(startTime: 0.0, value: predictionInput.settings.carbRatio.first!.value)
            ],
            timeZone: .utcTimeZone
        )!

        let settings = LoopSettings(
            dosingEnabled: false,
            glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            basalRateSchedule: basalRateSchedule,
            carbRatioSchedule: carbRatioSchedule,
            maximumBasalRatePerHour: 10,
            maximumBolus: 5,
            suspendThreshold: predictionInput.settings.suspendThreshold,
            automaticDosingStrategy: .automaticBolus
        )

        let glucoseStore = MockGlucoseStore()
        glucoseStore.storedGlucose = predictionInput.glucoseHistory

        let currentDate = glucoseStore.latestGlucose!.startDate
        now = currentDate

        let doseStore = MockDoseStore()
        doseStore.basalProfile = basalRateSchedule
        doseStore.basalProfileApplyingOverrideHistory = doseStore.basalProfile
        doseStore.sensitivitySchedule = insulinSensitivitySchedule
        doseStore.doseHistory = predictionInput.doses
        doseStore.lastAddedPumpData = predictionInput.doses.last!.startDate
        let carbStore = MockCarbStore()
        carbStore.insulinSensitivityScheduleApplyingOverrideHistory = insulinSensitivitySchedule
        carbStore.carbRatioSchedule = carbRatioSchedule
        carbStore.carbRatioScheduleApplyingOverrideHistory = carbRatioSchedule
        carbStore.carbHistory = predictionInput.carbEntries


        dosingDecisionStore = MockDosingDecisionStore()
        automaticDosingStatus = AutomaticDosingStatus(automaticDosingEnabled: true, isAutomaticDosingAllowed: true)
        loopDataManager = LoopDataManager(
            lastLoopCompleted: currentDate,
            basalDeliveryState: .active(currentDate),
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

        let expectedPredictedGlucose = loadPredictedGlucoseFixture("live_capture_predicted_glucose")

        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var predictedGlucose: [PredictedGlucoseValue]?
        var recommendedBasal: TempBasalRecommendation?
        self.loopDataManager.getLoopState { _, state in
            predictedGlucose = state.predictedGlucoseIncludingPendingInsulin
            recommendedBasal = state.recommendedAutomaticDose?.recommendation.basalAdjustment
            updateGroup.leave()
        }
        // We need to wait until the task completes to get outputs
        updateGroup.wait()

        XCTAssertNotNil(predictedGlucose)

        XCTAssertEqual(expectedPredictedGlucose.count, predictedGlucose!.count)

        for (expected, calculated) in zip(expectedPredictedGlucose, predictedGlucose!) {
            XCTAssertEqual(expected.startDate, calculated.startDate)
            XCTAssertEqual(expected.quantity.doubleValue(for: .milligramsPerDeciliter), calculated.quantity.doubleValue(for: .milligramsPerDeciliter), accuracy: defaultAccuracy)
        }
    }


    func testFlatAndStable() {
        setUp(for: .flatAndStable)
        let predictedGlucoseOutput = loadLocalDateGlucoseEffect("flat_and_stable_predicted_glucose")

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
        let predictedGlucoseOutput = loadLocalDateGlucoseEffect("high_and_falling_predicted_glucose")

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
        let predictedGlucoseOutput = loadLocalDateGlucoseEffect("low_and_falling_predicted_glucose")

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
        let predictedGlucoseOutput = loadLocalDateGlucoseEffect("low_with_low_treatment_predicted_glucose")

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
        XCTAssertTrue(dosingDecisionStore.dosingDecisions.isEmpty)
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
        XCTAssertEqual(delegate.recommendation, AutomaticDoseRecommendation(basalAdjustment: .cancel))
        XCTAssertEqual(dosingDecisionStore.dosingDecisions.count, 1)
        XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].reason, "maximumBasalRateChanged")
        XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].automaticDoseRecommendation, AutomaticDoseRecommendation(basalAdjustment: .cancel))
    }
    
    func testChangingMaxBasalUpdatesLoopData() {
        setUp(for: .highAndStable)
        waitOnDataQueue()
        var loopDataUpdated = false
        let exp = expectation(description: #function)
        let observer = NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: nil, queue: nil) { _ in
            loopDataUpdated = true
            exp.fulfill()
        }
        XCTAssertFalse(loopDataUpdated)
        loopDataManager.mutateSettings { $0.maximumBasalRatePerHour = 2.0 }
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(loopDataUpdated)
        NotificationCenter.default.removeObserver(observer)
    }

    func testOpenLoopCancelsTempBasal() {
        let dose = DoseEntry(type: .tempBasal, startDate: Date(), value: 1.0, unit: .unitsPerHour)
        setUp(for: .highAndStable, basalDeliveryState: .tempBasal(dose))
        waitOnDataQueue()
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate
        let exp = expectation(description: #function)
        let observer = NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: nil, queue: nil) { _ in
            exp.fulfill()
        }
        automaticDosingStatus.automaticDosingEnabled = false
        wait(for: [exp], timeout: 1.0)
        let expectedAutomaticDoseRecommendation = AutomaticDoseRecommendation(basalAdjustment: .cancel)
        XCTAssertEqual(delegate.recommendation, expectedAutomaticDoseRecommendation)
        XCTAssertEqual(dosingDecisionStore.dosingDecisions.count, 1)
        XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].reason, "automaticDosingDisabled")
        XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].automaticDoseRecommendation, expectedAutomaticDoseRecommendation)
        NotificationCenter.default.removeObserver(observer)
    }

    func testReceivedUnreliableCGMReadingCancelsTempBasal() {
        let dose = DoseEntry(type: .tempBasal, startDate: Date(), value: 5.0, unit: .unitsPerHour)
        setUp(for: .highAndStable, basalDeliveryState: .tempBasal(dose))
        waitOnDataQueue()
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate
        let exp = expectation(description: #function)
        let observer = NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: nil, queue: nil) { _ in
            exp.fulfill()
        }
        loopDataManager.receivedUnreliableCGMReading()
        wait(for: [exp], timeout: 1.0)
        let expectedAutomaticDoseRecommendation = AutomaticDoseRecommendation(basalAdjustment: .cancel)
        XCTAssertEqual(delegate.recommendation, expectedAutomaticDoseRecommendation)
        XCTAssertEqual(dosingDecisionStore.dosingDecisions.count, 1)
        XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].reason, "unreliableCGMData")
        XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].automaticDoseRecommendation, expectedAutomaticDoseRecommendation)
        NotificationCenter.default.removeObserver(observer)
    }

    func testLoopEnactsTempBasalWithoutManualBolusRecommendation() {
        setUp(for: .highAndStable)
        waitOnDataQueue()
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate
        let exp = expectation(description: #function)
        let observer = NotificationCenter.default.addObserver(forName: .LoopCompleted, object: nil, queue: nil) { _ in
            exp.fulfill()
        }
        loopDataManager.loop()
        wait(for: [exp], timeout: 1.0)
        let expectedAutomaticDoseRecommendation = AutomaticDoseRecommendation(basalAdjustment: TempBasalRecommendation(unitsPerHour: 4.55, duration: .minutes(30)))
        XCTAssertEqual(delegate.recommendation, expectedAutomaticDoseRecommendation)
        XCTAssertEqual(dosingDecisionStore.dosingDecisions.count, 1)
        if dosingDecisionStore.dosingDecisions.count == 1 {
            XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].reason, "loop")
            XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].automaticDoseRecommendation, expectedAutomaticDoseRecommendation)
            XCTAssertNil(dosingDecisionStore.dosingDecisions[0].manualBolusRecommendation)
            XCTAssertNil(dosingDecisionStore.dosingDecisions[0].manualBolusRequested)
        }
        NotificationCenter.default.removeObserver(observer)
    }

    func testLoopRecommendsTempBasalWithoutEnactingIfOpenLoop() {
        setUp(for: .highAndStable)
        automaticDosingStatus.automaticDosingEnabled = false
        waitOnDataQueue()
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate
        let exp = expectation(description: #function)
        let observer = NotificationCenter.default.addObserver(forName: .LoopCompleted, object: nil, queue: nil) { _ in
            exp.fulfill()
        }
        loopDataManager.loop()
        wait(for: [exp], timeout: 1.0)
        let expectedAutomaticDoseRecommendation = AutomaticDoseRecommendation(basalAdjustment: TempBasalRecommendation(unitsPerHour: 4.55, duration: .minutes(30)))
        XCTAssertNil(delegate.recommendation)
        XCTAssertEqual(dosingDecisionStore.dosingDecisions.count, 1)
        XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].reason, "loop")
        XCTAssertEqual(dosingDecisionStore.dosingDecisions[0].automaticDoseRecommendation, expectedAutomaticDoseRecommendation)
        XCTAssertNil(dosingDecisionStore.dosingDecisions[0].manualBolusRecommendation)
        XCTAssertNil(dosingDecisionStore.dosingDecisions[0].manualBolusRequested)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func dummyReplacementEntry() -> StoredCarbEntry{
        StoredCarbEntry(startDate: now, quantity: HKQuantity(unit: .gram(), doubleValue: -1))
    }
    
    func dummyCarbEntry() -> NewCarbEntry {
        NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 1E-50), startDate: now.addingTimeInterval(TimeInterval(days: -2)),
                     foodType: nil, absorptionTime: TimeInterval(hours: 3))
    }
    
    func correctionRange(_ value: Double) -> GlucoseRangeSchedule {
        correctionRange(value, value)
    }

    func correctionRange(_ minValue: Double, _ maxValue: Double) -> GlucoseRangeSchedule {
        GlucoseRangeSchedule(unit: HKUnit.milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: minValue, maxValue: maxValue))])!
    }

    func testLoopGetStateRecommendsManualBolus() {
        setUp(for: .flatAndStable, correctionRanges: correctionRange(106.26136802382213 - 1.82 * 55), suspendThresholdValue: 0.0)
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: nil, replacingCarbEntry: nil, considerPositiveVelocityAndRC: true)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 1.82, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, 1.82, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 0, accuracy: 0.01)
        XCTAssertNil(recommendedBolus!.missingAmount)
    }
    
    func testLoopGetStateRecommendsManualBolusMaxBolusClamping() {
        setUp(for: .flatAndStable, maxBolus: 1, correctionRanges: correctionRange(106.26136802382213 - 1.82 * 55), suspendThresholdValue: 0.0)
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: nil, replacingCarbEntry: nil, considerPositiveVelocityAndRC: true)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 1, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, 1.82, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.missingAmount!, 0.82, accuracy: 0.01)
    }
        
    func testLoopGetStateRecommendsManualBolusForCob() {
        // note that the default setup for .highAndStable has a _carb_effect file reflecting a 5g carb effect (with 45 ISF)
        // predicted glucose starts from 200 and goes down to 176.21882841682697 (taking into account _insulin_effect)
        let isf = 45.0
        let cir = 10.0

        let expectedCobCorrectionAmount = 0.5
        let expectedBgCorrectionAmount = 1.82 + (200 - 176.21882841682697) / isf // COB correction is to 200. BG correction is the rest
        
        let carbValue = 5.0 + cir * ((200 - 176.21882841682697) / isf + expectedCobCorrectionAmount)
        
        setUp(for: .highAndStable, predictCarbGlucoseEffects: true,
              carbHistorySupplier: {[StoredCarbEntry(startDate: $0, quantity: HKQuantity(unit: .gram(), doubleValue: carbValue))]})
                
        let exp = expectation(description: #function)
        
        var recommendedBolus: ManualBolusRecommendation?

        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: self.dummyCarbEntry(), replacingCarbEntry: self.dummyReplacementEntry(), considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, expectedBgCorrectionAmount + expectedCobCorrectionAmount, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, expectedBgCorrectionAmount, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, expectedCobCorrectionAmount, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 0, accuracy: 0.01)
        XCTAssertNil(recommendedBolus!.missingAmount)
    }
    
    func testLoopGetStateRecommendsManualBolusForCobAndReducingCarbEntry() {
        // note that the default setup for .highAndStable has a _carb_effect file reflecting a 5g carb effect (with 45 ISF)
        // predicted glucose starts from 200 and goes down to 176.21882841682697 (taking into account _insulin_effect)
        let isf = 45.0
        let cir = 10.0

        let expectedCobCorrectionAmount = 0.6
        let expectedBgCorrectionAmount = 1.82 + (200 - 176.21882841682697) / isf // COB correction is to 200. BG correction is the rest
        let expectedCarbsAmount = 0.5
        
        let carbValue = 5.0 + cir * ((200 - 176.21882841682697) / isf + expectedCobCorrectionAmount)
        
        setUp(for: .highAndStable, predictCarbGlucoseEffects: true,
              carbHistorySupplier: {[
                StoredCarbEntry(startDate: $0, quantity: HKQuantity(unit: .gram(), doubleValue: carbValue)),
                StoredCarbEntry(startDate: $0, quantity: HKQuantity(unit: .gram(), doubleValue: 10))
              ]})
                
        let exp = expectation(description: #function)
        
        let carbEntry = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: expectedCarbsAmount * cir), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 1))
        
        var recommendedBolus: ManualBolusRecommendation?

        loopDataManager.getLoopState { (_, loopState) in
            
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: carbEntry, replacingCarbEntry: StoredCarbEntry(startDate: self.now, quantity: HKQuantity(unit: .gram(), doubleValue: 10)), considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, expectedCarbsAmount + expectedBgCorrectionAmount + expectedCobCorrectionAmount, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, expectedBgCorrectionAmount, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, expectedCobCorrectionAmount, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, expectedCarbsAmount, accuracy: 0.01)
        XCTAssertNil(recommendedBolus!.missingAmount)
    }
    
    func testLoopGetStateRecommendsManualBolusForZeroCorrectionCobAndCarbEntry() {
        // note that the default setup for .highAndStable has a _carb_effect file reflecting a 5g carb effect (with 45 ISF)
        // predicted glucose starts from 200 and goes down to 176.21882841682697 (taking into account _insulin_effect)
        let isf = 45.0
        let cir = 10.0

        let expectedCobCorrectionAmount = 0.0
        let expectedCarbsAmount = 0.5
        let expectedBgOffset = -0.2
        let expectedBgCorrectionAmount = 1.82 + (200 - 176.21882841682697) / isf + expectedBgOffset
        
        
        let carbValue = 5.0 + cir * ((200 - 176.21882841682697) / isf + expectedBgOffset)
        
        setUp(for: .highAndStable, predictCarbGlucoseEffects: true,
              carbHistorySupplier: {[
                StoredCarbEntry(startDate: $0, quantity: HKQuantity(unit: .gram(), doubleValue: carbValue))
              ]})
                
        let exp = expectation(description: #function)
        
        let carbEntry = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: expectedCarbsAmount * cir), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 1))
        
        var recommendedBolus: ManualBolusRecommendation?

        loopDataManager.getLoopState { (_, loopState) in
            
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: carbEntry, replacingCarbEntry: self.dummyReplacementEntry(), considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, expectedCarbsAmount + expectedBgCorrectionAmount + expectedCobCorrectionAmount, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, expectedBgCorrectionAmount, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, expectedCobCorrectionAmount, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, expectedCarbsAmount, accuracy: 0.01)
        XCTAssertNil(recommendedBolus!.missingAmount)
    }
    
    func testLoopGetStateRecommendsManualBolusForCarbEntry() {
        setUp(for: .highAndStable, predictCarbGlucoseEffects: true)
        let exp = expectation(description: #function)
        
        var recommendedBolus: ManualBolusRecommendation?

        let carbEntry = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 5.0), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 1.0))
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: carbEntry, replacingCarbEntry: nil, considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 2.32, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, 1.82, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 0.5, accuracy: 0.01)
        XCTAssertNil(recommendedBolus!.missingAmount)
    }
    
    func testLoopGetStateRecommendsManualBolusForCarbEntryMaxBolusClamping() {
        setUp(for: .highAndStable, maxBolus: 1, predictCarbGlucoseEffects: true)
        let exp = expectation(description: #function)
        
        var recommendedBolus: ManualBolusRecommendation?

        let carbEntry = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 5.0), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 1.0))
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: carbEntry, replacingCarbEntry: nil, considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 1, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, 1.82, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 0.5, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.missingAmount!, 1.32, accuracy: 0.01)
    }
    
    func testLoopGetStateRecommendsManualBolusForBeneathRange() {
        setUp(for: .flatAndStable, correctionRanges: correctionRange(160))
        
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: nil, replacingCarbEntry: nil, considerPositiveVelocityAndRC: true)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, (106.21882841682697 - 160) / 55, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 0, accuracy: 0.01)
        XCTAssertNil(recommendedBolus!.missingAmount)
    }
    
    func testLoopGetStateRecommendsManualBolusForInRangeAboveMidPoint() {
        setUp(for: .flatAndStable, correctionRanges: correctionRange(80, 110))
        
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: nil, replacingCarbEntry: nil, considerPositiveVelocityAndRC: true)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 0, accuracy: 0.01)
        XCTAssertNil(recommendedBolus!.missingAmount)
    }
    
    func testLoopGetStateRecommendsManualBolusForSuspendForCarbEntry() {
        setUp(for: .highAndStable, predictCarbGlucoseEffects: true, correctionRanges: correctionRange(230), suspendThresholdValue: 220)
        
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?

        let carbEntry = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 15.0), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 1.0))
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: carbEntry, replacingCarbEntry: nil, considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }

        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, (176.21882841682697 - 230) / 45, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 1.5, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.missingAmount!, 1.5 + (176.21882841682697 - 230) / 45, accuracy: 0.01)
    }
    
    func testLoopGetStateRecommendsManualBolusForBigAndSlowCarbEntry() {
        setUp(for: .highAndStable, predictCarbGlucoseEffects: true, correctionRanges: correctionRange(176.2188), suspendThresholdValue: 176.218)
        
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?

        let carbEntry = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 100.0), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 4.0))
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: carbEntry, replacingCarbEntry: nil, considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }

        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 7.27, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 9.99, accuracy: 0.01) // 9.99 and not 10 since there is 10 minute delay, leaving 0.01 remaining
        XCTAssertEqual(recommendedBolus!.missingAmount!, 9.99 - 7.27, accuracy: 0.01)
    }

    
    func testLoopGetStateRecommendsManualBolusNoMissingForSuspendForCarbEntry() {
        setUp(for: .highAndStable, predictCarbGlucoseEffects: true, correctionRanges: correctionRange(230), suspendThresholdValue: 220)
        
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?

        let carbEntry = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 5.0), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 1.0))
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: carbEntry, replacingCarbEntry: nil, considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }

        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, (176.21882841682697 - 230) / 45, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 0.5, accuracy: 0.01)
        XCTAssertNil(recommendedBolus!.missingAmount) // carbsAmount + bgCorrectionAmount < 0, so nothing is missing
    }
    
    func testLoopGetStateRecommendsManualBolusForSuspendNoCarbEntry() {
        setUp(for: .highAndStable, predictCarbGlucoseEffects: true, correctionRanges: correctionRange(230), suspendThresholdValue: 180)
        
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?

        let carbEntry = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 5.0), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 1.0))
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: nil, replacingCarbEntry: nil, considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }

        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.bgCorrectionAmount, (176.21882841682697 - 230) / 45, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus!.bolusBreakdown!.carbsAmount!, 0.0, accuracy: 0.01)
        XCTAssertNil(recommendedBolus!.missingAmount)
    }
    
    func testLoopGetStateRecommendsManualBolusForInRangeCarbEntry() {
        setUp(for: .highAndStable, predictCarbGlucoseEffects: true, correctionRanges: correctionRange(170, 210))
                        
        let exp1 = expectation(description: #function)
        var recommendedBolus1: ManualBolusRecommendation?
        
        let exp2 = expectation(description: #function)
        var recommendedBolus2: ManualBolusRecommendation?

        // note that 176.218 + 5/10*45 < 210
        let carbEntry1 = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 5), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 1.0))
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus1 = try? loopState.recommendBolus(consideringPotentialCarbEntry: carbEntry1, replacingCarbEntry: nil, considerPositiveVelocityAndRC: false)
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 100000.0)

        let carbEntry2 = NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: 4.8), startDate: now, foodType: nil, absorptionTime: TimeInterval(hours: 1.0))
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus2 = try? loopState.recommendBolus(consideringPotentialCarbEntry: carbEntry2, replacingCarbEntry: nil, considerPositiveVelocityAndRC: false)
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 100000.0)

                
        XCTAssertEqual(recommendedBolus1!.amount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus1!.bolusBreakdown!.bgCorrectionAmount, -0.5, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus1!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus1!.bolusBreakdown!.carbsAmount!, 0.5, accuracy: 0.01)
        XCTAssertNil(recommendedBolus1!.missingAmount)
        
        XCTAssertEqual(recommendedBolus2!.amount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus2!.bolusBreakdown!.bgCorrectionAmount, -0.48, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus2!.bolusBreakdown!.cobCorrectionAmount, 0, accuracy: 0.01)
        XCTAssertEqual(recommendedBolus2!.bolusBreakdown!.carbsAmount!, 0.48, accuracy: 0.01)
        XCTAssertNil(recommendedBolus2!.missingAmount)
    }

    func testLoopGetStateRecommendsManualBolusWithMomentum() {
        setUp(for: .highAndRisingWithCOB)
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: nil, replacingCarbEntry: nil, considerPositiveVelocityAndRC: true)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(recommendedBolus!.amount, 1.62, accuracy: 0.01)
    }

    func testLoopGetStateRecommendsManualBolusWithoutMomentum() {
        setUp(for: .highAndRisingWithCOB)
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: nil, replacingCarbEntry: nil, considerPositiveVelocityAndRC: false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(recommendedBolus!.amount, 1.52, accuracy: 0.01)
    }

    func testIsClosedLoopAvoidsTriggeringTempBasalCancelOnCreation() {
        let settings = LoopSettings(
            dosingEnabled: false,
            glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
            maximumBasalRatePerHour: 5,
            maximumBolus: 10,
            suspendThreshold: suspendThreshold
        )

        let doseStore = MockDoseStore()
        let glucoseStore = MockGlucoseStore(for: .flatAndStable)
        let carbStore = MockCarbStore()

        let currentDate = Date()

        dosingDecisionStore = MockDosingDecisionStore()
        automaticDosingStatus = AutomaticDosingStatus(automaticDosingEnabled: false, isAutomaticDosingAllowed: true)
        let existingTempBasal = DoseEntry(
            type: .tempBasal,
            startDate: currentDate.addingTimeInterval(-.minutes(2)),
            endDate: currentDate.addingTimeInterval(.minutes(28)),
            value: 1.0,
            unit: .unitsPerHour,
            deliveredUnits: nil,
            description: "Mock Temp Basal",
            syncIdentifier: "asdf",
            scheduledBasalRate: nil,
            insulinType: .novolog,
            automatic: true,
            manuallyEntered: false,
            isMutable: true)
        loopDataManager = LoopDataManager(
            lastLoopCompleted: currentDate.addingTimeInterval(-.minutes(5)),
            basalDeliveryState: .tempBasal(existingTempBasal),
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
        let mockDelegate = MockDelegate()
        loopDataManager.delegate = mockDelegate

        // Dose enacting happens asynchronously, as does receiving isClosedLoop signals
        waitOnMain(timeout: 5)
        XCTAssertNil(mockDelegate.recommendation)
    }

    func testAutoBolusMaxIOBClamping() {
        /// `maxBolus` is set to clamp the automatic dose
        /// Autobolus without clamping: 0.65 U. Clamped recommendation: 0.2 U.
        setUp(for: .highAndRisingWithCOB, maxBolus: 5, dosingStrategy: .automaticBolus)

        // This sets up dose rounding
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate

        let updateGroup = DispatchGroup()
        updateGroup.enter()

        var insulinOnBoard: InsulinValue?
        var recommendedBolus: Double?
        self.loopDataManager.getLoopState { _, state in
            insulinOnBoard = state.insulinOnBoard
            recommendedBolus = state.recommendedAutomaticDose?.recommendation.bolusUnits
            updateGroup.leave()
        }
        updateGroup.wait()

        XCTAssertEqual(recommendedBolus!, 0.5, accuracy: 0.01)
        XCTAssertEqual(insulinOnBoard?.value, 9.5)

        /// Set the `maximumBolus` to 10U so there's no clamping
        updateGroup.enter()
        self.loopDataManager.mutateSettings { settings in settings.maximumBolus = 10 }
        self.loopDataManager.getLoopState { _, state in
            insulinOnBoard = state.insulinOnBoard
            recommendedBolus = state.recommendedAutomaticDose?.recommendation.bolusUnits
            updateGroup.leave()
        }
        updateGroup.wait()

        XCTAssertEqual(recommendedBolus!, 0.65, accuracy: 0.01)
        XCTAssertEqual(insulinOnBoard?.value, 9.5)
    }

    func testTempBasalMaxIOBClamping() {
        /// `maximumBolus` is set to 5U to clamp max IOB at 10U
        /// Without clamping: 4.25 U/hr. Clamped recommendation: 2.0 U/hr.
        setUp(for: .highAndRisingWithCOB, maxBolus: 5)

        // This sets up dose rounding
        let delegate = MockDelegate()
        loopDataManager.delegate = delegate

        let updateGroup = DispatchGroup()
        updateGroup.enter()

        var insulinOnBoard: InsulinValue?
        var recommendedBasal: TempBasalRecommendation?
        self.loopDataManager.getLoopState { _, state in
            insulinOnBoard = state.insulinOnBoard
            recommendedBasal = state.recommendedAutomaticDose?.recommendation.basalAdjustment
            updateGroup.leave()
        }
        updateGroup.wait()

        XCTAssertEqual(recommendedBasal!.unitsPerHour, 2.0, accuracy: 0.01)
        XCTAssertEqual(insulinOnBoard?.value, 9.5)

        /// Set the `maximumBolus` to 10U so there's no clamping
        updateGroup.enter()
        self.loopDataManager.mutateSettings { settings in settings.maximumBolus = 10 }
        self.loopDataManager.getLoopState { _, state in
            insulinOnBoard = state.insulinOnBoard
            recommendedBasal = state.recommendedAutomaticDose?.recommendation.basalAdjustment
            updateGroup.leave()
        }
        updateGroup.wait()

        XCTAssertEqual(recommendedBasal!.unitsPerHour, 4.25, accuracy: 0.01)
        XCTAssertEqual(insulinOnBoard?.value, 9.5)
    }

}
