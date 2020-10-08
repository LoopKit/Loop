//
//  BolusEntryViewModelTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 9/28/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit
import LoopKitUI
import SwiftUI
import XCTest
@testable import Loop

class BolusEntryViewModelTests: XCTestCase {
    static let now = Date.distantFuture
    static let exampleStartDate = Date.distantFuture - .hours(2)
    static let exampleEndDate = Date.distantFuture - .hours(1)
    static fileprivate let exampleGlucoseValue = MockGlucoseValue(quantity: exampleManualGlucoseQuantity, startDate: exampleStartDate)
    static let exampleManualGlucoseQuantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 123.4)
    static let exampleManualGlucoseSample =
        HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
                         quantity: exampleManualGlucoseQuantity,
                         start: exampleStartDate,
                         end: exampleEndDate)
    
    static let exampleCGMGlucoseQuantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 100.4)
    static let exampleCGMGlucoseSample =
        HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
                         quantity: exampleCGMGlucoseQuantity,
                         start: exampleStartDate,
                         end: exampleEndDate)

    static let exampleCarbQuantity = HKQuantity(unit: .gram(), doubleValue: 234.5)
    
    static let exampleBolusQuantity = HKQuantity(unit: .internationalUnit(), doubleValue: 1.0)
    static let noBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)

    var bolusEntryViewModel: BolusEntryViewModel!
    fileprivate var delegate: MockBolusEntryViewModelDelegate!
    var now: Date = BolusEntryViewModelTests.now
    
    let mockOriginalCarbEntry = StoredCarbEntry(uuid: UUID(), provenanceIdentifier: "provenanceIdentifier", syncIdentifier: "syncIdentifier", syncVersion: 0, startDate: BolusEntryViewModelTests.exampleStartDate, quantity: BolusEntryViewModelTests.exampleCarbQuantity, foodType: "foodType", absorptionTime: 1, createdByCurrentApp: true, userCreatedDate: BolusEntryViewModelTests.now, userUpdatedDate: BolusEntryViewModelTests.now)
    let mockPotentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: BolusEntryViewModelTests.exampleStartDate, foodType: "foodType", absorptionTime: 1)
    let mockUUID = UUID().uuidString
    let queue = DispatchQueue(label: "BolusEntryViewModelTests")
    var saveAndDeliverSuccess = false
    
    override func setUpWithError() throws {
        now = Date.distantFuture
        delegate = MockBolusEntryViewModelDelegate()
        saveAndDeliverSuccess = false
        setUpViewModel()
    }
    
    func setUpViewModel(originalCarbEntry: StoredCarbEntry? = nil, potentialCarbEntry: NewCarbEntry? = nil) {
        bolusEntryViewModel = BolusEntryViewModel(delegate: delegate,
                                                  now: { self.now },
                                                  screenWidth: 512,
                                                  debounceIntervalMilliseconds: 0,
                                                  authenticateOverride: authenticateOverride,
                                                  uuidProvider: { self.mockUUID },
                                                  originalCarbEntry: originalCarbEntry,
                                                  potentialCarbEntry: potentialCarbEntry,
                                                  selectedCarbAbsorptionTimeEmoji: nil)
        bolusEntryViewModel.maximumBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 10)
    }

    var authenticateOverrideCompletion: ((Swift.Result<Void, Error>) -> Void)?
    private func authenticateOverride(_ message: String, _ completion: @escaping (Swift.Result<Void, Error>) -> Void) {
        authenticateOverrideCompletion = completion
    }
    
    override func tearDownWithError() throws {
    }

    func testInitialConditions() throws {
        XCTAssertEqual(0, bolusEntryViewModel.glucoseValues.count)
        XCTAssertEqual(0, bolusEntryViewModel.predictedGlucoseValues.count)
        XCTAssertEqual(.milligramsPerDeciliter, bolusEntryViewModel.glucoseUnit)
        XCTAssertNil(bolusEntryViewModel.activeCarbs)
        XCTAssertNil(bolusEntryViewModel.activeInsulin)
        XCTAssertNil(bolusEntryViewModel.targetGlucoseSchedule)
        XCTAssertNil(bolusEntryViewModel.preMealOverride)
        XCTAssertNil(bolusEntryViewModel.scheduleOverride)
       
        XCTAssertFalse(bolusEntryViewModel.isManualGlucoseEntryEnabled)

        XCTAssertNil(bolusEntryViewModel.enteredManualGlucose)
        XCTAssertNil(bolusEntryViewModel.recommendedBolus)
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 0), bolusEntryViewModel.enteredBolus)

        XCTAssertNil(bolusEntryViewModel.activeAlert)
        XCTAssertNil(bolusEntryViewModel.activeNotice)

        XCTAssertFalse(bolusEntryViewModel.isRefreshingPump)
    }
    
    func testChartDateInterval() throws {
        // TODO: Test different screen widths
        // TODO: Test different insulin models
        // TODO: Test different chart history settings
        let expected = DateInterval(start: now - .hours(9), duration: .hours(8))
        XCTAssertEqual(expected, bolusEntryViewModel.chartDateInterval)
    }

    // MARK: updating state

    func testUpdateDisableManualGlucoseEntryIfNecessary() throws {
        bolusEntryViewModel.isManualGlucoseEntryEnabled = true
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        try triggerLoopStateUpdated(with: MockLoopState())
        XCTAssertFalse(bolusEntryViewModel.isManualGlucoseEntryEnabled)
        XCTAssertNil(bolusEntryViewModel.enteredManualGlucose)
        XCTAssertEqual(.glucoseNoLongerStale, bolusEntryViewModel.activeAlert)
    }
    
    func testUpdateGlucoseValues() throws {
        XCTAssertEqual(0, bolusEntryViewModel.glucoseValues.count)
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertEqual(1, bolusEntryViewModel.glucoseValues.count)
        XCTAssertEqual([100.4], bolusEntryViewModel.glucoseValues.map {
            return $0.quantity.doubleValue(for: .milligramsPerDeciliter)
        })
    }
    
    func testUpdateGlucoseValuesWithManual() throws {
        XCTAssertEqual(0, bolusEntryViewModel.glucoseValues.count)
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertEqual([100.4, 123.4], bolusEntryViewModel.glucoseValues.map {
            return $0.quantity.doubleValue(for: .milligramsPerDeciliter)
        })
    }
    
    func testManualEntryClearsEnteredBolus() throws {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        XCTAssertEqual(Self.exampleBolusQuantity, bolusEntryViewModel.enteredBolus)
        waitOnMain()
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 0), bolusEntryViewModel.enteredBolus)
    }
    
    func testUpdatePredictedGlucoseValues() throws {
        let mockLoopState = MockLoopState()
        mockLoopState.predictGlucoseValueResult = [PredictedGlucoseValue(startDate: Self.exampleStartDate, quantity: Self.exampleCGMGlucoseQuantity)]
        try triggerLoopStateUpdated(with: mockLoopState)
        waitOnMain()
        XCTAssertEqual(mockLoopState.predictGlucoseValueResult,
                       bolusEntryViewModel.predictedGlucoseValues.map {
                        PredictedGlucoseValue(startDate: $0.startDate, quantity: $0.quantity)
        })
    }
    
    func testUpdatePredictedGlucoseValuesWithManual() throws {
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        let mockLoopState = MockLoopState()
        mockLoopState.predictGlucoseValueResult = [PredictedGlucoseValue(startDate: Self.exampleStartDate, quantity: Self.exampleCGMGlucoseQuantity)]
        try triggerLoopStateUpdated(with: mockLoopState)
        waitOnMain()
        XCTAssertEqual(mockLoopState.predictGlucoseValueResult,
                       bolusEntryViewModel.predictedGlucoseValues.map {
                        PredictedGlucoseValue(startDate: $0.startDate, quantity: $0.quantity)
        })
    }
    
    func testManualGlucoseChangesPredictedGlucoseValues() throws {
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        let mockLoopState = MockLoopState()
        mockLoopState.predictGlucoseValueResult = [PredictedGlucoseValue(startDate: Self.exampleStartDate, quantity: Self.exampleCGMGlucoseQuantity)]
        waitOnMain()
        try triggerLoopStateUpdatedWithDataAndWait(with: mockLoopState)
        waitOnMain()

        XCTAssertEqual(mockLoopState.predictGlucoseValueResult,
                       bolusEntryViewModel.predictedGlucoseValues.map {
                        PredictedGlucoseValue(startDate: $0.startDate, quantity: $0.quantity)
        })
    }
    
    func testUpdateInsulinOnBoard() throws {
        delegate.insulinOnBoardResult = .success(InsulinValue(startDate: Self.exampleStartDate, value: 1.5))
        XCTAssertNil(bolusEntryViewModel.activeInsulin)
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 1.5), bolusEntryViewModel.activeInsulin)
    }
    
    func testUpdateCarbsOnBoard() throws {
        delegate.carbsOnBoardResult = .success(CarbValue(startDate: Self.exampleStartDate, endDate: Self.exampleEndDate, quantity: Self.exampleCarbQuantity))
        XCTAssertNil(bolusEntryViewModel.activeCarbs)
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertEqual(Self.exampleCarbQuantity, bolusEntryViewModel.activeCarbs)
    }
    
    func testUpdateCarbsOnBoardFailure() throws {
        delegate.carbsOnBoardResult = .failure(CarbStore.CarbStoreError.notConfigured)
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertNil(bolusEntryViewModel.activeCarbs)
    }

    func testUpdateRecommendedBolusNoNotice() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        let mockState = MockLoopState()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        mockState.bolusRecommendationResult = BolusRecommendation(amount: 1.234, pendingInsulin: 4.321)
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(mockState.bolusRecommendationResult?.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        let consideringPotentialCarbEntryPassed = try XCTUnwrap(mockState.consideringPotentialCarbEntryPassed)
        XCTAssertEqual(mockPotentialCarbEntry, consideringPotentialCarbEntryPassed)
        let replacingCarbEntryPassed = try XCTUnwrap(mockState.replacingCarbEntryPassed)
        XCTAssertEqual(mockOriginalCarbEntry, replacingCarbEntryPassed)
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }
            
    func testUpdateRecommendedBolusWithNotice() throws {
        let mockState = MockLoopState()
        delegate.settings.suspendThreshold = GlucoseThreshold(unit: .milligramsPerDeciliter, value: Self.exampleCGMGlucoseQuantity.doubleValue(for: .milligramsPerDeciliter))
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        mockState.bolusRecommendationResult = BolusRecommendation(amount: 1.234, pendingInsulin: 4.321, notice: BolusRecommendationNotice.glucoseBelowSuspendThreshold(minGlucose: Self.exampleGlucoseValue))
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(mockState.bolusRecommendationResult?.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        XCTAssertEqual(BolusEntryViewModel.Notice.predictedGlucoseBelowSuspendThreshold(suspendThreshold: Self.exampleCGMGlucoseQuantity), bolusEntryViewModel.activeNotice)
    }
    
    func testUpdateRecommendedBolusWithNoticeMissingSuspendThreshold() throws {
        let mockState = MockLoopState()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        mockState.bolusRecommendationResult = BolusRecommendation(amount: 1.234, pendingInsulin: 4.321, notice: BolusRecommendationNotice.glucoseBelowSuspendThreshold(minGlucose: Self.exampleGlucoseValue))
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(mockState.bolusRecommendationResult?.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }

    func testUpdateRecommendedBolusWithOtherNotice() throws {
        let mockState = MockLoopState()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        mockState.bolusRecommendationResult = BolusRecommendation(amount: 1.234, pendingInsulin: 4.321, notice: BolusRecommendationNotice.currentGlucoseBelowTarget(glucose: Self.exampleGlucoseValue))
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(mockState.bolusRecommendationResult?.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }
        
    func testUpdateRecommendedBolusThrowsMissingDataError() throws {
        let mockState = MockLoopState()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        mockState.bolusRecommendationError = LoopError.missingDataError(.glucose)
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNil(recommendedBolus)
        XCTAssertEqual(.staleGlucoseData, bolusEntryViewModel.activeNotice)
    }
    
    func testUpdateRecommendedBolusThrowsPumpDataTooOld() throws {
        let mockState = MockLoopState()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        mockState.bolusRecommendationError = LoopError.pumpDataTooOld(date: now)
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNil(recommendedBolus)
        XCTAssertEqual(.stalePumpData, bolusEntryViewModel.activeNotice)
    }

    func testUpdateRecommendedBolusThrowsOtherError() throws {
        let mockState = MockLoopState()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        mockState.bolusRecommendationError = LoopError.invalidData(details: "")
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNil(recommendedBolus)
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }
    
    func testUpdateRecommendedBolusWithManual() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        let mockState = MockLoopState()
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        mockState.bolusRecommendationResult = BolusRecommendation(amount: 1.234, pendingInsulin: 4.321)
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(mockState.bolusRecommendationResult?.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        let consideringPotentialCarbEntryPassed = try XCTUnwrap(mockState.consideringPotentialCarbEntryPassed)
        XCTAssertEqual(mockPotentialCarbEntry, consideringPotentialCarbEntryPassed)
        let replacingCarbEntryPassed = try XCTUnwrap(mockState.replacingCarbEntryPassed)
        XCTAssertEqual(mockOriginalCarbEntry, replacingCarbEntryPassed)
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }

    func testRecommendedBolusClearsEnteredBolusThenSetsIt() throws {
        XCTAssertNil(bolusEntryViewModel.recommendedBolus)
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        let mockState = MockLoopState()
        mockState.bolusRecommendationResult = BolusRecommendation(amount: 1.234, pendingInsulin: 4.321)
        delegate.cachedGlucoseSamplesResponse = [StoredGlucoseSample(sample: Self.exampleCGMGlucoseSample)]
        try triggerLoopStateUpdated(with: mockState)
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 0.0), bolusEntryViewModel.enteredBolus)
        // Now, through the magic of `observeRecommendedBolusChanges` and the recommendedBolus publisher it should update to 1.234.
        // However, due to the weird complexities of the number of times BolusEntryViewModel hops on and
        // off `DispatchQueue.main` we need to wait on main twice to make this test reliable.
        waitOnMain()
        waitOnMain()
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 1.234), bolusEntryViewModel.enteredBolus)
    }

    func testUpdateDoesNotRefreshPumpIfDataIsFresh() throws {
        XCTAssertFalse(bolusEntryViewModel.isRefreshingPump)
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertFalse(bolusEntryViewModel.isRefreshingPump)
        XCTAssertNil(delegate.ensureCurrentPumpDataCompletion)
    }

    func testUpdateIsRefreshingPump() throws {
        delegate.isPumpDataStale = true
        XCTAssertFalse(bolusEntryViewModel.isRefreshingPump)
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertTrue(bolusEntryViewModel.isRefreshingPump)
        let completion = try XCTUnwrap(delegate.ensureCurrentPumpDataCompletion)
        completion()
        // Need to once again trigger loop state
        try triggerLoopStateResult(with: MockLoopState())
        // then wait on main again (sigh)
        waitOnMain()
        XCTAssertFalse(bolusEntryViewModel.isRefreshingPump)
    }
    
    // MARK: save data and bolus delivery

    func testDeliverBolusOnly() throws {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        var success = false
        bolusEntryViewModel.saveAndDeliver {
            success = true
        }
        // Pretend authentication succeeded
        let authenticateOverrideCompletion = try XCTUnwrap(self.authenticateOverrideCompletion)
        authenticateOverrideCompletion(.success(()))
        
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(now, delegate.enactedBolusDate)
        XCTAssertTrue(success)
        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
    }
    
    struct MockError: Error {}
    func testDeliverBolusAuthFail() throws {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        var success = false
        bolusEntryViewModel.saveAndDeliver {
            success = true
        }
        // Pretend authentication succeeded
        let authenticateOverrideCompletion = try XCTUnwrap(self.authenticateOverrideCompletion)
        authenticateOverrideCompletion(.failure(MockError()))
        
        XCTAssertNil(delegate.enactedBolusUnits)
        XCTAssertNil(delegate.enactedBolusDate)
        XCTAssertFalse(success)
        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
    }
    
    private func saveAndDeliver(_ bolus: HKQuantity, file: StaticString = #file, line: UInt = #line) throws {
        bolusEntryViewModel.enteredBolus = bolus
        bolusEntryViewModel.saveAndDeliver { self.saveAndDeliverSuccess = true }
        if bolus != BolusEntryViewModelTests.noBolus {
            let authenticateOverrideCompletion = try XCTUnwrap(self.authenticateOverrideCompletion, file: file, line: line)
            authenticateOverrideCompletion(.success(()))
        }
    }
    
    func testSaveManualGlucoseNoBolus() throws {
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        // manualGlucoseSample updates asynchronously on main
        waitOnMain()

        try saveAndDeliver(BolusEntryViewModelTests.noBolus)

        let expectedGlucoseSample = NewGlucoseSample(date: now, quantity: Self.exampleManualGlucoseQuantity, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: mockUUID)
        XCTAssertEqual([expectedGlucoseSample], delegate.glucoseSamplesAdded)
        
        delegate.addGlucoseCompletion?(.success([MockGlucoseValue(quantity: Self.exampleManualGlucoseQuantity, startDate: now)]))
        waitOnMain()

        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertNil(delegate.enactedBolusUnits)
        XCTAssertNil(delegate.enactedBolusDate)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveCarbGlucoseNoBolus() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        try saveAndDeliver(BolusEntryViewModelTests.noBolus)
        delegate.addGlucoseCompletion?(.success([MockGlucoseValue(quantity: Self.exampleManualGlucoseQuantity, startDate: now)]))
        waitOnMain()
        let addCarbEntryCompletion = try XCTUnwrap(delegate.addCarbEntryCompletion)
        addCarbEntryCompletion(.success(()))
        waitOnMain()

        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertEqual(1, delegate.carbEntriesAdded.count)
        XCTAssertEqual(mockPotentialCarbEntry, delegate.carbEntriesAdded.first?.0)
        XCTAssertEqual(mockOriginalCarbEntry, delegate.carbEntriesAdded.first?.1)
        XCTAssertNil(delegate.enactedBolusUnits)
        XCTAssertNil(delegate.enactedBolusDate)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveManualGlucoseAndBolus() throws {
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        // manualGlucoseSample updates asynchronously on main
        waitOnMain()
        
        try saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)
        
        let expectedGlucoseSample = NewGlucoseSample(date: now, quantity: Self.exampleManualGlucoseQuantity, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: mockUUID)
        XCTAssertEqual([expectedGlucoseSample], delegate.glucoseSamplesAdded)
        
        delegate.addGlucoseCompletion?(.success([MockGlucoseValue(quantity: Self.exampleManualGlucoseQuantity, startDate: now)]))
        waitOnMain()
        
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(now, delegate.enactedBolusDate)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveCarbAndBolus() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        // manualGlucoseSample updates asynchronously on main
        waitOnMain()
        
        try saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)
        
        let addCarbEntryCompletion = try XCTUnwrap(delegate.addCarbEntryCompletion)
        addCarbEntryCompletion(.success(()))
        waitOnMain()
        
        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertEqual(1, delegate.carbEntriesAdded.count)
        XCTAssertEqual(mockPotentialCarbEntry, delegate.carbEntriesAdded.first?.0)
        XCTAssertEqual(mockOriginalCarbEntry, delegate.carbEntriesAdded.first?.1)
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(now, delegate.enactedBolusDate)
        XCTAssertTrue(saveAndDeliverSuccess)
    }

    func testSaveManualGlucoseAndCarbAndBolus() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        // manualGlucoseSample updates asynchronously on main
        waitOnMain()
        
        try saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)
        
        let expectedGlucoseSample = NewGlucoseSample(date: now, quantity: Self.exampleManualGlucoseQuantity, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: mockUUID)
        XCTAssertEqual([expectedGlucoseSample], delegate.glucoseSamplesAdded)
        
        delegate.addGlucoseCompletion?(.success([MockGlucoseValue(quantity: Self.exampleManualGlucoseQuantity, startDate: now)]))
        waitOnMain()
        
        let addCarbEntryCompletion = try XCTUnwrap(delegate.addCarbEntryCompletion)
        addCarbEntryCompletion(.success(()))
        waitOnMain()

        XCTAssertEqual(1, delegate.carbEntriesAdded.count)
        XCTAssertEqual(mockPotentialCarbEntry, delegate.carbEntriesAdded.first?.0)
        XCTAssertEqual(mockOriginalCarbEntry, delegate.carbEntriesAdded.first?.1)
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(now, delegate.enactedBolusDate)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    // MARK: Display strings
    
    func testEnteredBolusAmountString() throws {
        XCTAssertEqual("0", bolusEntryViewModel.enteredBolusAmountString)
    }

    func testMaximumBolusAmountString() throws {
        XCTAssertEqual("10", bolusEntryViewModel.maximumBolusAmountString)
    }
    
    func testCarbEntryAmountAndEmojiString() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        XCTAssertEqual("234 g foodType", bolusEntryViewModel.carbEntryAmountAndEmojiString)
    }
    
    func testCarbEntryAmountAndEmojiString2() throws {
        let potentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: Date(), foodType: nil, absorptionTime: 1)
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: potentialCarbEntry)

        XCTAssertEqual("234 g", bolusEntryViewModel.carbEntryAmountAndEmojiString)
    }
    
    func testCarbEntryDateAndAbsorptionTimeString() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        //XCTAssertEqual("2:00 PM + 0m", bolusEntryViewModel.carbEntryDateAndAbsorptionTimeString)
    }
    
    func testCarbEntryDateAndAbsorptionTimeString2() throws {
        let potentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: Self.exampleStartDate, foodType: nil, absorptionTime: nil)
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: potentialCarbEntry)

        //XCTAssertEqual("2:00 PM", bolusEntryViewModel.carbEntryDateAndAbsorptionTimeString)
    }

    func testIsManualGlucosePromptVisible() throws {
        XCTAssertFalse(bolusEntryViewModel.isManualGlucosePromptVisible)
        bolusEntryViewModel.activeNotice = .staleGlucoseData
        bolusEntryViewModel.isManualGlucoseEntryEnabled = true
        XCTAssertFalse(bolusEntryViewModel.isManualGlucosePromptVisible)
        bolusEntryViewModel.activeNotice = .staleGlucoseData
        bolusEntryViewModel.isManualGlucoseEntryEnabled = false
        XCTAssertTrue(bolusEntryViewModel.isManualGlucosePromptVisible)
    }
    
    func testIsNoticeVisible() throws {
        XCTAssertFalse(bolusEntryViewModel.isNoticeVisible)
        bolusEntryViewModel.activeNotice = .stalePumpData
        XCTAssertTrue(bolusEntryViewModel.isNoticeVisible)
        bolusEntryViewModel.activeNotice = .staleGlucoseData
        bolusEntryViewModel.isManualGlucoseEntryEnabled = false
        XCTAssertTrue(bolusEntryViewModel.isNoticeVisible)
        bolusEntryViewModel.isManualGlucoseEntryEnabled = true
        XCTAssertFalse(bolusEntryViewModel.isNoticeVisible)
    }
    
    // MARK: action button tests
    
    func testPrimaryButtonDefault() {
        XCTAssertEqual(.actionButton, bolusEntryViewModel.primaryButton)
    }
    
    func testPrimaryButtonBolusEntry() {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        XCTAssertEqual(.actionButton, bolusEntryViewModel.primaryButton)
    }

    func testPrimaryButtonManual() {
        bolusEntryViewModel.activeNotice = .staleGlucoseData
        bolusEntryViewModel.isManualGlucoseEntryEnabled = false
        XCTAssertEqual(.manualGlucoseEntry, bolusEntryViewModel.primaryButton)
    }

    func testPrimaryButtonManualPrompt() {
        bolusEntryViewModel.isManualGlucoseEntryEnabled = true
        XCTAssertEqual(.actionButton, bolusEntryViewModel.primaryButton)
    }

    func testActionButtonDefault() {
        XCTAssertEqual(.enterBolus, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonManualGlucose() {
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        XCTAssertEqual(.saveWithoutBolusing, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonPotentialCarbEntry() {
        setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
        XCTAssertEqual(.saveWithoutBolusing, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonManualGlucoseAndPotentialCarbEntry() {
        setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        XCTAssertEqual(.saveWithoutBolusing, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonDeliverOnly() {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        XCTAssertEqual(.deliver, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonSaveAndDeliverManualGlucose() {
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        XCTAssertEqual(.saveAndDeliver, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonSaveAndDeliverPotentialCarbEntry() {
        setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        XCTAssertEqual(.saveAndDeliver, bolusEntryViewModel.actionButtonAction)
    }

    func testActionButtonSaveAndDeliverBothManualGlucoseAndPotentialCarbEntry() {
        setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.enteredManualGlucose = Self.exampleManualGlucoseQuantity
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        XCTAssertEqual(.saveAndDeliver, bolusEntryViewModel.actionButtonAction)
    }
}

// MARK: utilities

extension BolusEntryViewModelTests {
    
    func triggerLoopStateUpdatedWithDataAndWait(with state: LoopState = MockLoopState(), function: String = #function) throws {
        delegate.cachedGlucoseSamplesResponse = [StoredGlucoseSample(sample: Self.exampleCGMGlucoseSample)]
        try triggerLoopStateUpdated(with: state)
        waitOnMain()
    }
    
    func triggerLoopStateUpdated(with state: LoopState, function: String = #function) throws {
        NotificationCenter.default.post(name: .LoopDataUpdated, object: nil)
        try triggerLoopStateResult(with: state, function: function)
    }
    
    func triggerLoopStateResult(with state: LoopState, function: String = #function) throws {
        let exp = expectation(description: function)
        let block = try XCTUnwrap(delegate.loopStateCallBlock)
        queue.async {
            block(state)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}


fileprivate class MockLoopState: LoopState {
    
    var carbsOnBoard: CarbValue?
    
    var error: Error?
    
    var insulinCounteractionEffects: [GlucoseEffectVelocity] = []
    
    var predictedGlucose: [PredictedGlucoseValue]?
    
    var predictedGlucoseIncludingPendingInsulin: [PredictedGlucoseValue]?
    
    var recommendedTempBasal: (recommendation: TempBasalRecommendation, date: Date)?
    
    var recommendedBolus: (recommendation: BolusRecommendation, date: Date)?
    
    var retrospectiveGlucoseDiscrepancies: [GlucoseChange]?
    
    var totalRetrospectiveCorrection: HKQuantity?
    
    var predictGlucoseValueResult: [PredictedGlucoseValue] = []
    func predictGlucose(using inputs: PredictionInputEffect, potentialBolus: DoseEntry?, potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, includingPendingInsulin: Bool) throws -> [PredictedGlucoseValue] {
        return predictGlucoseValueResult
    }

    func predictGlucoseFromManualGlucose(_ glucose: NewGlucoseSample, potentialBolus: DoseEntry?, potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, includingPendingInsulin: Bool) throws -> [PredictedGlucoseValue] {
        return predictGlucoseValueResult
    }
    
    var bolusRecommendationResult: BolusRecommendation?
    var bolusRecommendationError: Error?
    var consideringPotentialCarbEntryPassed: NewCarbEntry??
    var replacingCarbEntryPassed: StoredCarbEntry??
    func recommendBolus(consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?) throws -> BolusRecommendation? {
        consideringPotentialCarbEntryPassed = potentialCarbEntry
        replacingCarbEntryPassed = replacedCarbEntry
        if let error = bolusRecommendationError { throw error }
        return bolusRecommendationResult
    }
    
    func recommendBolusForManualGlucose(_ glucose: NewGlucoseSample, consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?) throws -> BolusRecommendation? {
        consideringPotentialCarbEntryPassed = potentialCarbEntry
        replacingCarbEntryPassed = replacedCarbEntry
        if let error = bolusRecommendationError { throw error }
        return bolusRecommendationResult
    }
}

fileprivate class MockBolusEntryViewModelDelegate: BolusEntryViewModelDelegate {
    var loopStateCallBlock: ((LoopState) -> Void)?
    func withLoopState(do block: @escaping (LoopState) -> Void) {
        loopStateCallBlock = block
    }
    
    var glucoseSamplesAdded = [NewGlucoseSample]()
    var addGlucoseCompletion: ((Result<[GlucoseValue]>) -> Void)?
    func addGlucose(_ samples: [NewGlucoseSample], completion: ((Result<[GlucoseValue]>) -> Void)?) {
        glucoseSamplesAdded.append(contentsOf: samples)
        addGlucoseCompletion = completion
    }
    
    var carbEntriesAdded = [(NewCarbEntry, StoredCarbEntry?)]()
    var addCarbEntryCompletion: ((Result<Void>) -> Void)?
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry?, completion: @escaping (Result<Void>) -> Void) {
        carbEntriesAdded.append((carbEntry, replacingEntry))
        addCarbEntryCompletion = completion
    }
    
    var enactedBolusUnits: Double?
    var enactedBolusDate: Date?
    func enactBolus(units: Double, at startDate: Date, completion: @escaping (Error?) -> Void) {
        enactedBolusUnits = units
        enactedBolusDate = startDate
    }
    
    var cachedGlucoseSamplesResponse: [StoredGlucoseSample] = []
    func getCachedGlucoseSamples(start: Date, end: Date?, completion: @escaping ([StoredGlucoseSample]) -> Void) {
        completion(cachedGlucoseSamplesResponse)
    }
    
    var insulinOnBoardResult: DoseStoreResult<InsulinValue>?
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        if let insulinOnBoardResult = insulinOnBoardResult {
            completion(insulinOnBoardResult)
        }
    }
    
    var carbsOnBoardResult: CarbStoreResult<CarbValue>?
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (CarbStoreResult<CarbValue>) -> Void) {
        if let carbsOnBoardResult = carbsOnBoardResult {
            completion(carbsOnBoardResult)
        }
    }
    
    var ensureCurrentPumpDataCompletion: (() -> Void)?
    func ensureCurrentPumpData(completion: @escaping () -> Void) {
        ensureCurrentPumpDataCompletion = completion
    }
    
    var isGlucoseDataStale: Bool = false
    
    var isPumpDataStale: Bool = false
    
    var isPumpConfigured: Bool = true
    
    var preferredGlucoseUnit: HKUnit? = .milligramsPerDeciliter
    
    var insulinModel: InsulinModel? = MockInsulinModel()
    
    var settings: LoopSettings = LoopSettings()
}


fileprivate struct MockInsulinModel: InsulinModel {
    func percentEffectRemaining(at time: TimeInterval) -> Double {
        0
    }
    
    var effectDuration: TimeInterval = 0
    
    var delay: TimeInterval = 0
    
    var debugDescription: String = ""
}

fileprivate struct MockGlucoseValue: GlucoseValue {
    var quantity: HKQuantity
    var startDate: Date
}

fileprivate extension TimeInterval {
    static func milliseconds(_ milliseconds: Double) -> TimeInterval {
        return milliseconds / 1000
    }
}
