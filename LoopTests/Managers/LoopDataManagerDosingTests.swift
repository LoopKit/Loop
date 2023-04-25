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

    func testLoopGetStateRecommendsManualBolus() {
        setUp(for: .highAndStable)
        let exp = expectation(description: #function)
        var recommendedBolus: ManualBolusRecommendation?
        loopDataManager.getLoopState { (_, loopState) in
            recommendedBolus = try? loopState.recommendBolus(consideringPotentialCarbEntry: nil, replacingCarbEntry: nil, considerPositiveVelocityAndRC: true)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 100000.0)
        XCTAssertEqual(recommendedBolus!.amount, 1.82, accuracy: 0.01)
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
        let glucoseStore = MockGlucoseStore()
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
