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
   
    // Some of the tests depend on a date on the hour
    static let now = ISO8601DateFormatter().date(from: "2020-03-11T07:00:00-0700")!
    static let exampleStartDate = now - .hours(2)
    static let exampleEndDate = now - .hours(1)
    static fileprivate let exampleGlucoseValue = MockGlucoseValue(quantity: exampleManualGlucoseQuantity, startDate: exampleStartDate)
    static let exampleManualGlucoseQuantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 123.4)
    static let exampleManualGlucoseSample =
        HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
                         quantity: exampleManualGlucoseQuantity,
                         start: exampleStartDate,
                         end: exampleEndDate)
    static let exampleManualStoredGlucoseSample = StoredGlucoseSample(sample: exampleManualGlucoseSample)

    static let exampleCGMGlucoseQuantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 100.4)
    static let exampleCGMGlucoseSample =
        HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
                         quantity: exampleCGMGlucoseQuantity,
                         start: exampleStartDate,
                         end: exampleEndDate)

    static let exampleCarbQuantity = HKQuantity(unit: .gram(), doubleValue: 234.5)
    
    static let exampleBolusQuantity = HKQuantity(unit: .internationalUnit(), doubleValue: 1.0)
    static let noBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)

    static let mockUUID = UUID()

    static let exampleScheduleOverrideSettings = TemporaryScheduleOverrideSettings(unit: .millimolesPerLiter, targetRange: nil, insulinNeedsScaleFactor: nil)
    static let examplePreMealOverride = TemporaryScheduleOverride(context: .preMeal, settings: exampleScheduleOverrideSettings, startDate: exampleStartDate, duration: .indefinite, enactTrigger: .local, syncIdentifier: mockUUID)
    static let exampleCustomScheduleOverride = TemporaryScheduleOverride(context: .custom, settings: exampleScheduleOverrideSettings, startDate: exampleStartDate, duration: .indefinite, enactTrigger: .local, syncIdentifier: mockUUID)
    
    var bolusEntryViewModel: BolusEntryViewModel!
    fileprivate var delegate: MockBolusEntryViewModelDelegate!
    var now: Date = BolusEntryViewModelTests.now
    
    let mockOriginalCarbEntry = StoredCarbEntry(uuid: UUID(), provenanceIdentifier: "provenanceIdentifier", syncIdentifier: "syncIdentifier", syncVersion: 0, startDate: BolusEntryViewModelTests.exampleStartDate, quantity: BolusEntryViewModelTests.exampleCarbQuantity, foodType: "foodType", absorptionTime: 1, createdByCurrentApp: true, userCreatedDate: BolusEntryViewModelTests.now, userUpdatedDate: BolusEntryViewModelTests.now)
    let mockPotentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: BolusEntryViewModelTests.exampleStartDate, foodType: "foodType", absorptionTime: 1)
    let mockFinalCarbEntry = StoredCarbEntry(uuid: UUID(), provenanceIdentifier: "provenanceIdentifier", syncIdentifier: "syncIdentifier", syncVersion: 1, startDate: BolusEntryViewModelTests.exampleStartDate, quantity: BolusEntryViewModelTests.exampleCarbQuantity, foodType: "foodType", absorptionTime: 1, createdByCurrentApp: true, userCreatedDate: BolusEntryViewModelTests.now, userUpdatedDate: BolusEntryViewModelTests.now)
    let mockUUID = BolusEntryViewModelTests.mockUUID.uuidString
    let queue = DispatchQueue(label: "BolusEntryViewModelTests")
    var saveAndDeliverSuccess = false
    
    override func setUpWithError() throws {
        now = Self.now
        delegate = MockBolusEntryViewModelDelegate()
        delegate.mostRecentGlucoseDataDate = now
        delegate.mostRecentPumpDataDate = now
        saveAndDeliverSuccess = false
        setUpViewModel()
    }
    
    func setUpViewModel(originalCarbEntry: StoredCarbEntry? = nil, potentialCarbEntry: NewCarbEntry? = nil, selectedCarbAbsorptionTimeEmoji: String? = nil) {
        bolusEntryViewModel = BolusEntryViewModel(delegate: delegate,
                                                  now: { self.now },
                                                  screenWidth: 512,
                                                  debounceIntervalMilliseconds: 0,
                                                  uuidProvider: { self.mockUUID },
                                                  timeZone: TimeZone(abbreviation: "GMT")!,
                                                  originalCarbEntry: originalCarbEntry,
                                                  potentialCarbEntry: potentialCarbEntry,
                                                  selectedCarbAbsorptionTimeEmoji: selectedCarbAbsorptionTimeEmoji)
        bolusEntryViewModel.authenticate = authenticateOverride
        bolusEntryViewModel.maximumBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 10)
    }

    var authenticateOverrideCompletion: ((Swift.Result<Void, Error>) -> Void)?
    private func authenticateOverride(_ message: String, _ completion: @escaping (Swift.Result<Void, Error>) -> Void) {
        authenticateOverrideCompletion = completion
    }

    func testInitialConditions() throws {
        XCTAssertEqual(0, bolusEntryViewModel.glucoseValues.count)
        XCTAssertEqual(0, bolusEntryViewModel.predictedGlucoseValues.count)
        XCTAssertNil(bolusEntryViewModel.activeCarbs)
        XCTAssertNil(bolusEntryViewModel.activeInsulin)
        XCTAssertNil(bolusEntryViewModel.targetGlucoseSchedule)
        XCTAssertNil(bolusEntryViewModel.preMealOverride)
        XCTAssertNil(bolusEntryViewModel.scheduleOverride)
       
        XCTAssertFalse(bolusEntryViewModel.isManualGlucoseEntryEnabled)

        XCTAssertNil(bolusEntryViewModel.manualGlucoseQuantity)
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
        let expected = DateInterval(start: now - .hours(2), duration: .hours(8))
        XCTAssertEqual(expected, bolusEntryViewModel.chartDateInterval)
    }

    // MARK: updating state
    
    func testUpdateDisableManualGlucoseEntryIfNecessary() throws {
        bolusEntryViewModel.isManualGlucoseEntryEnabled = true
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        try triggerLoopStateUpdated(with: MockLoopState())
        XCTAssertFalse(bolusEntryViewModel.isManualGlucoseEntryEnabled)
        XCTAssertNil(bolusEntryViewModel.manualGlucoseQuantity)
        XCTAssertEqual(.glucoseNoLongerStale, bolusEntryViewModel.activeAlert)
    }
    
    func testUpdateDisableManualGlucoseEntryIfNecessaryStaleGlucose() throws {
        delegate.mostRecentGlucoseDataDate = Date.distantPast
        bolusEntryViewModel.isManualGlucoseEntryEnabled = true
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        try triggerLoopStateUpdated(with: MockLoopState())
        XCTAssertTrue(bolusEntryViewModel.isManualGlucoseEntryEnabled)
        XCTAssertEqual(Self.exampleManualGlucoseQuantity, bolusEntryViewModel.manualGlucoseQuantity)
        XCTAssertNil(bolusEntryViewModel.activeAlert)
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
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertEqual([100.4, 123.4], bolusEntryViewModel.glucoseValues.map {
            return $0.quantity.doubleValue(for: .milligramsPerDeciliter)
        })
    }
    
    func testManualEntryClearsEnteredBolus() throws {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        XCTAssertEqual(Self.exampleBolusQuantity, bolusEntryViewModel.enteredBolus)
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
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
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        let mockLoopState = MockLoopState()
        mockLoopState.predictGlucoseValueResult = [PredictedGlucoseValue(startDate: Self.exampleStartDate, quantity: Self.exampleCGMGlucoseQuantity)]
        try triggerLoopStateUpdated(with: mockLoopState)
        waitOnMain()
        XCTAssertEqual(mockLoopState.predictGlucoseValueResult,
                       bolusEntryViewModel.predictedGlucoseValues.map {
                        PredictedGlucoseValue(startDate: $0.startDate, quantity: $0.quantity)
        })
    }
    
    func testUpdateSettings() throws {
        XCTAssertNil(bolusEntryViewModel.preMealOverride)
        XCTAssertNil(bolusEntryViewModel.scheduleOverride)
        XCTAssertNil(bolusEntryViewModel.targetGlucoseSchedule)
        let newGlucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: [
            RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 100, maxValue: 110)),
            RepeatingScheduleValue(startTime: TimeInterval(28800), value: DoubleRange(minValue: 90, maxValue: 100)),
            RepeatingScheduleValue(startTime: TimeInterval(75600), value: DoubleRange(minValue: 100, maxValue: 110))
        ], timeZone: .utcTimeZone)!
        var newSettings = LoopSettings(dosingEnabled: true,
                                       glucoseTargetRangeSchedule: newGlucoseTargetRangeSchedule,
                                       maximumBasalRatePerHour: 1.0,
                                       maximumBolus: 10.0,
                                       suspendThreshold: GlucoseThreshold(unit: .milligramsPerDeciliter, value: 100.0))
        let settings = TemporaryScheduleOverrideSettings(unit: .millimolesPerLiter, targetRange: nil, insulinNeedsScaleFactor: nil)
        newSettings.preMealOverride = TemporaryScheduleOverride(context: .preMeal, settings: settings, startDate: Self.exampleStartDate, duration: .indefinite, enactTrigger: .local, syncIdentifier: UUID())
        newSettings.scheduleOverride = TemporaryScheduleOverride(context: .custom, settings: settings, startDate: Self.exampleStartDate, duration: .indefinite, enactTrigger: .local, syncIdentifier: UUID())
        delegate.settings = newSettings
        try triggerLoopStateUpdatedWithDataAndWait()
        waitOnMain()

        XCTAssertEqual(newSettings.preMealOverride, bolusEntryViewModel.preMealOverride)
        XCTAssertEqual(newSettings.scheduleOverride, bolusEntryViewModel.scheduleOverride)
        XCTAssertEqual(newGlucoseTargetRangeSchedule, bolusEntryViewModel.targetGlucoseSchedule)
    }

    func testUpdateSettingsWithCarbs() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        XCTAssertNil(bolusEntryViewModel.preMealOverride)
        XCTAssertNil(bolusEntryViewModel.scheduleOverride)
        XCTAssertNil(bolusEntryViewModel.targetGlucoseSchedule)
        let newGlucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: [
            RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 100, maxValue: 110)),
            RepeatingScheduleValue(startTime: TimeInterval(28800), value: DoubleRange(minValue: 90, maxValue: 100)),
            RepeatingScheduleValue(startTime: TimeInterval(75600), value: DoubleRange(minValue: 100, maxValue: 110))
        ], timeZone: .utcTimeZone)!
        var newSettings = LoopSettings(dosingEnabled: true,
                                       glucoseTargetRangeSchedule: newGlucoseTargetRangeSchedule,
                                       maximumBasalRatePerHour: 1.0,
                                       maximumBolus: 10.0,
                                       suspendThreshold: GlucoseThreshold(unit: .milligramsPerDeciliter, value: 100.0))
        newSettings.preMealOverride = Self.examplePreMealOverride
        newSettings.scheduleOverride = Self.exampleCustomScheduleOverride
        delegate.settings = newSettings
        try triggerLoopStateUpdatedWithDataAndWait()
        waitOnMain()
        
        // Pre-meal override should be ignored if we have carbs (LOOP-1964), and cleared in settings
        XCTAssertEqual(newSettings.scheduleOverride, bolusEntryViewModel.scheduleOverride)
        XCTAssertEqual(newGlucoseTargetRangeSchedule, bolusEntryViewModel.targetGlucoseSchedule)
        
        // ... but restored if we cancel without bolusing
        bolusEntryViewModel = nil
    }
    
    func testManualGlucoseChangesPredictedGlucoseValues() throws {
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
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
        mockState.bolusRecommendationResult = ManualBolusRecommendation(amount: 1.234, pendingInsulin: 4.321)
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
        mockState.bolusRecommendationResult = ManualBolusRecommendation(amount: 1.234, pendingInsulin: 4.321, notice: BolusRecommendationNotice.glucoseBelowSuspendThreshold(minGlucose: Self.exampleGlucoseValue))
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
        mockState.bolusRecommendationResult = ManualBolusRecommendation(amount: 1.234, pendingInsulin: 4.321, notice: BolusRecommendationNotice.glucoseBelowSuspendThreshold(minGlucose: Self.exampleGlucoseValue))
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
        mockState.bolusRecommendationResult = ManualBolusRecommendation(amount: 1.234, pendingInsulin: 4.321, notice: BolusRecommendationNotice.currentGlucoseBelowTarget(glucose: Self.exampleGlucoseValue))
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
        mockState.bolusRecommendationError = LoopError.pumpSuspended
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNil(recommendedBolus)
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }
    
    func testUpdateRecommendedBolusWithManual() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        let mockState = MockLoopState()
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        mockState.bolusRecommendationResult = ManualBolusRecommendation(amount: 1.234, pendingInsulin: 4.321)
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

    func testUpdateDoesNotRefreshPumpIfDataIsFresh() throws {
        XCTAssertFalse(bolusEntryViewModel.isRefreshingPump)
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertFalse(bolusEntryViewModel.isRefreshingPump)
        XCTAssertNil(delegate.ensureCurrentPumpDataCompletion)
    }

    func testUpdateIsRefreshingPump() throws {
        delegate.mostRecentPumpDataDate = Date.distantPast
        XCTAssertFalse(bolusEntryViewModel.isRefreshingPump)
        try triggerLoopStateUpdatedWithDataAndWait()
        XCTAssertTrue(bolusEntryViewModel.isRefreshingPump)
        let completion = try XCTUnwrap(delegate.ensureCurrentPumpDataCompletion)
        completion(Date())
        // Need to once again trigger loop state
        try triggerLoopStateResult(with: MockLoopState())
        // then wait on main again (sigh)
        waitOnMain()
        XCTAssertFalse(bolusEntryViewModel.isRefreshingPump)
    }
        
    func testRecommendedBolusSetsEnteredBolus() throws {
        XCTAssertNil(bolusEntryViewModel.recommendedBolus)
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        let mockState = MockLoopState()
        mockState.bolusRecommendationResult = ManualBolusRecommendation(amount: 1.234, pendingInsulin: 4.321)
        try triggerLoopStateUpdatedWithDataAndWait(with: mockState)
        // Now, through the magic of `observeRecommendedBolusChanges` and the recommendedBolus publisher it should update to 1.234.  But we have to wait twice on main to make this reliable...
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 1.234), bolusEntryViewModel.enteredBolus)
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
        XCTAssertEqual(false, delegate.enactedBolusAutomatic)
        XCTAssertTrue(success)
        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0, BolusDosingDecision(for: .normalBolus,
                                                                                        manualBolusRequested: 1.0))
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
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
        XCTAssertNil(delegate.enactedBolusAutomatic)
        XCTAssertFalse(success)
        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertTrue(delegate.bolusDosingDecisionsAdded.isEmpty)
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
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        // manualGlucoseSample updates asynchronously on main
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()

        try saveAndDeliver(BolusEntryViewModelTests.noBolus)

        let expectedGlucoseSample = NewGlucoseSample(date: now, quantity: Self.exampleManualGlucoseQuantity, condition: nil, trend: nil, trendRate: nil, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: mockUUID)
        XCTAssertEqual([expectedGlucoseSample], delegate.glucoseSamplesAdded)

        delegate.addGlucoseCompletion?(.success([Self.exampleManualStoredGlucoseSample]))
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()

        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0, BolusDosingDecision(for: .normalBolus,
                                                                                        manualGlucoseSample: Self.exampleManualStoredGlucoseSample,
                                                                                        manualBolusRequested: 0.0))
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertNil(delegate.enactedBolusUnits)
        XCTAssertNil(delegate.enactedBolusAutomatic)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveCarbGlucoseNoBolus() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        try saveAndDeliver(BolusEntryViewModelTests.noBolus)
        delegate.addGlucoseCompletion?(.success([Self.exampleManualStoredGlucoseSample]))
        waitOnMain()
        let addCarbEntryCompletion = try XCTUnwrap(delegate.addCarbEntryCompletion)
        addCarbEntryCompletion(.success(mockFinalCarbEntry))
        waitOnMain()

        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertEqual(1, delegate.carbEntriesAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0, BolusDosingDecision(for: .normalBolus,
                                                                                        originalCarbEntry: mockOriginalCarbEntry,
                                                                                        carbEntry: mockFinalCarbEntry,
                                                                                        manualBolusRequested: 0.0))
        XCTAssertEqual(mockOriginalCarbEntry, delegate.carbEntriesAdded.first?.1)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0, BolusDosingDecision(for: .normalBolus,
                                                                                        originalCarbEntry: mockOriginalCarbEntry,
                                                                                        carbEntry: mockFinalCarbEntry,
                                                                                        manualBolusRequested: 0.0))
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertNil(delegate.enactedBolusUnits)
        XCTAssertNil(delegate.enactedBolusAutomatic)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveManualGlucoseAndBolus() throws {
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        // manualGlucoseSample updates asynchronously on main
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()

        try saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)
        
        let expectedGlucoseSample = NewGlucoseSample(date: now, quantity: Self.exampleManualGlucoseQuantity, condition: nil, trend: nil, trendRate: nil, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: mockUUID)
        XCTAssertEqual([expectedGlucoseSample], delegate.glucoseSamplesAdded)
        
        delegate.addGlucoseCompletion?(.success([Self.exampleManualStoredGlucoseSample]))
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()

        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0, BolusDosingDecision(for: .normalBolus,
                                                                                        manualGlucoseSample: Self.exampleManualStoredGlucoseSample,
                                                                                        manualBolusRequested: 1.0))
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(false, delegate.enactedBolusAutomatic)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveCarbAndBolus() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        // manualGlucoseSample updates asynchronously on main
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()

        try saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)
        
        let addCarbEntryCompletion = try XCTUnwrap(delegate.addCarbEntryCompletion)
        addCarbEntryCompletion(.success(mockFinalCarbEntry))
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()

        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertEqual(1, delegate.carbEntriesAdded.count)
        XCTAssertEqual(mockPotentialCarbEntry, delegate.carbEntriesAdded.first?.0)
        XCTAssertEqual(mockOriginalCarbEntry, delegate.carbEntriesAdded.first?.1)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0, BolusDosingDecision(for: .normalBolus,
                                                                                        originalCarbEntry: mockOriginalCarbEntry,
                                                                                        carbEntry: mockFinalCarbEntry,
                                                                                        manualBolusRequested: 1.0))
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(false, delegate.enactedBolusAutomatic)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveCarbAndBolusClearsSavedPreMealOverride() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        // set up user specified pre-meal override
        let newGlucoseTargetRangeSchedule = GlucoseRangeSchedule(unit: .millimolesPerLiter, dailyItems: [
            RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 100, maxValue: 110)),
            RepeatingScheduleValue(startTime: TimeInterval(28800), value: DoubleRange(minValue: 90, maxValue: 100)),
            RepeatingScheduleValue(startTime: TimeInterval(75600), value: DoubleRange(minValue: 100, maxValue: 110))
        ], timeZone: .utcTimeZone)!
        var newSettings = LoopSettings(dosingEnabled: true,
                                       glucoseTargetRangeSchedule: newGlucoseTargetRangeSchedule,
                                       maximumBasalRatePerHour: 1.0,
                                       maximumBolus: 10.0,
                                       suspendThreshold: GlucoseThreshold(unit: .milligramsPerDeciliter, value: 100.0))
        newSettings.preMealOverride = Self.examplePreMealOverride
        newSettings.scheduleOverride = Self.exampleCustomScheduleOverride
        delegate.settings = newSettings
        try triggerLoopStateUpdatedWithDataAndWait()
        waitOnMain()

        try saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)
        let addCarbEntryCompletion = try XCTUnwrap(delegate.addCarbEntryCompletion)
        addCarbEntryCompletion(.success(mockFinalCarbEntry))
        waitOnMain()
        XCTAssertTrue(saveAndDeliverSuccess)

        // ... make sure the "restoring" of the saved pre-meal override does not happen
        bolusEntryViewModel = nil
    }

    func testSaveManualGlucoseAndCarbAndBolus() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        // manualGlucoseSample updates asynchronously on main
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()

        try saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)
        
        let expectedGlucoseSample = NewGlucoseSample(date: now, quantity: Self.exampleManualGlucoseQuantity, condition: nil, trend: nil, trendRate: nil, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: mockUUID)
        XCTAssertEqual([expectedGlucoseSample], delegate.glucoseSamplesAdded)
        
        delegate.addGlucoseCompletion?(.success([Self.exampleManualStoredGlucoseSample]))
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()

        let addCarbEntryCompletion = try XCTUnwrap(delegate.addCarbEntryCompletion)
        addCarbEntryCompletion(.success(mockFinalCarbEntry))
        // For some reason, starting with Xcode 12.5, in order for these tests to pass we need to call `waitOnMain()`
        // _twice_ here.  Not exactly sure why, needs investigation.
        waitOnMain()
        waitOnMain()

        XCTAssertEqual(1, delegate.carbEntriesAdded.count)
        XCTAssertEqual(mockPotentialCarbEntry, delegate.carbEntriesAdded.first?.0)
        XCTAssertEqual(mockOriginalCarbEntry, delegate.carbEntriesAdded.first?.1)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0, BolusDosingDecision(for: .normalBolus,
                                                                                        originalCarbEntry: mockOriginalCarbEntry,
                                                                                        carbEntry: mockFinalCarbEntry,
                                                                                        manualGlucoseSample: Self.exampleManualStoredGlucoseSample,
                                                                                        manualBolusRequested: 1.0))
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(false, delegate.enactedBolusAutomatic)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    // MARK: Display strings
    
    func testEnteredBolusAmountString() throws {
        XCTAssertEqual("0", bolusEntryViewModel.enteredBolusAmountString)
    }

    func testMaximumBolusAmountString() throws {
        XCTAssertEqual("10", bolusEntryViewModel.maximumBolusAmountString)
    }
    
    func testCarbEntryAmountAndEmojiStringNil() throws {
        XCTAssertNil(bolusEntryViewModel.carbEntryAmountAndEmojiString)
    }
    
    func testCarbEntryAmountAndEmojiString() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        XCTAssertEqual("234 g foodType", bolusEntryViewModel.carbEntryAmountAndEmojiString)
    }
    
    func testCarbEntryAmountAndEmojiStringNoFoodType() throws {
        let potentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: Self.exampleStartDate, foodType: nil, absorptionTime: 1)
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: potentialCarbEntry)

        XCTAssertEqual("234 g", bolusEntryViewModel.carbEntryAmountAndEmojiString)
    }
    
    func testCarbEntryAmountAndEmojiStringWithEmoji() throws {
        let potentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: Self.exampleStartDate, foodType: nil, absorptionTime: 1)
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: potentialCarbEntry, selectedCarbAbsorptionTimeEmoji: "😀")

        XCTAssertEqual("234 g 😀", bolusEntryViewModel.carbEntryAmountAndEmojiString)
    }
    
    func testCarbEntryDateAndAbsorptionTimeStringNil() throws {
        XCTAssertNil(bolusEntryViewModel.carbEntryDateAndAbsorptionTimeString)
    }
    
    func testCarbEntryDateAndAbsorptionTimeString() throws {
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        XCTAssertEqual("12:00 PM + 0m", bolusEntryViewModel.carbEntryDateAndAbsorptionTimeString)
    }
    
    func testCarbEntryDateAndAbsorptionTimeString2() throws {
        let potentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: Self.exampleStartDate, foodType: nil, absorptionTime: nil)
        setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: potentialCarbEntry)

        XCTAssertEqual("12:00 PM", bolusEntryViewModel.carbEntryDateAndAbsorptionTimeString)
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
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        XCTAssertEqual(.saveWithoutBolusing, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonPotentialCarbEntry() {
        setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
        XCTAssertEqual(.saveWithoutBolusing, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonManualGlucoseAndPotentialCarbEntry() {
        setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        XCTAssertEqual(.saveWithoutBolusing, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonDeliverOnly() {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        XCTAssertEqual(.deliver, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonSaveAndDeliverManualGlucose() {
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
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
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        XCTAssertEqual(.saveAndDeliver, bolusEntryViewModel.actionButtonAction)
    }

    func testManualGlucoseStringMatchesDisplayGlucoseUnit() {
        // used "260" mg/dL ("14.4" mmol/L) since 14.40 mmol/L -> 259 mg/dL and 14.43 mmol/L -> 260 mg/dL
        XCTAssertEqual(bolusEntryViewModel.manualGlucoseString, "")
        bolusEntryViewModel.manualGlucoseString = "260"
        XCTAssertEqual(bolusEntryViewModel.manualGlucoseString, "260")
        delegate.displayGlucoseUnitObservable.displayGlucoseUnitDidChange(to: .millimolesPerLiter)
        XCTAssertEqual(bolusEntryViewModel.manualGlucoseString, "14.4")
        delegate.displayGlucoseUnitObservable.displayGlucoseUnitDidChange(to: .milligramsPerDeciliter)
        XCTAssertEqual(bolusEntryViewModel.manualGlucoseString, "260")
        delegate.displayGlucoseUnitObservable.displayGlucoseUnitDidChange(to: .millimolesPerLiter)
        XCTAssertEqual(bolusEntryViewModel.manualGlucoseString, "14.4")

        bolusEntryViewModel.manualGlucoseString = "14.0"
        XCTAssertEqual(bolusEntryViewModel.manualGlucoseString, "14.0")
        bolusEntryViewModel.manualGlucoseString = "14.4"
        XCTAssertEqual(bolusEntryViewModel.manualGlucoseString, "14.4")
        delegate.displayGlucoseUnitObservable.displayGlucoseUnitDidChange(to: .milligramsPerDeciliter)
        XCTAssertEqual(bolusEntryViewModel.manualGlucoseString, "259")
    }
}

// MARK: utilities

extension BolusEntryViewModelTests {
    
    func triggerLoopStateUpdatedWithDataAndWait(with state: LoopState = MockLoopState(), function: String = #function) throws {
        delegate.getGlucoseSamplesResponse = [StoredGlucoseSample(sample: Self.exampleCGMGlucoseSample)]
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
    
    var error: LoopError?
    
    var insulinCounteractionEffects: [GlucoseEffectVelocity] = []
    
    var predictedGlucose: [PredictedGlucoseValue]?
    
    var predictedGlucoseIncludingPendingInsulin: [PredictedGlucoseValue]?
    
    var recommendedAutomaticDose: (recommendation: AutomaticDoseRecommendation, date: Date)?
    
    var retrospectiveGlucoseDiscrepancies: [GlucoseChange]?
    
    var totalRetrospectiveCorrection: HKQuantity?
    
    var predictGlucoseValueResult: [PredictedGlucoseValue] = []
    func predictGlucose(using inputs: PredictionInputEffect, potentialBolus: DoseEntry?, potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, includingPendingInsulin: Bool, considerPositiveVelocityAndRC: Bool) throws -> [PredictedGlucoseValue] {
        return predictGlucoseValueResult
    }

    func predictGlucoseFromManualGlucose(_ glucose: NewGlucoseSample, potentialBolus: DoseEntry?, potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, includingPendingInsulin: Bool, considerPositiveVelocityAndRC: Bool) throws -> [PredictedGlucoseValue] {
        return predictGlucoseValueResult
    }

    var bolusRecommendationResult: ManualBolusRecommendation?
    var bolusRecommendationError: Error?
    var consideringPotentialCarbEntryPassed: NewCarbEntry??
    var replacingCarbEntryPassed: StoredCarbEntry??
    func recommendBolus(consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, considerPositiveVelocityAndRC: Bool) throws -> ManualBolusRecommendation? {
        consideringPotentialCarbEntryPassed = potentialCarbEntry
        replacingCarbEntryPassed = replacedCarbEntry
        if let error = bolusRecommendationError { throw error }
        return bolusRecommendationResult
    }
    
    func recommendBolusForManualGlucose(_ glucose: NewGlucoseSample, consideringPotentialCarbEntry potentialCarbEntry: NewCarbEntry?, replacingCarbEntry replacedCarbEntry: StoredCarbEntry?, considerPositiveVelocityAndRC: Bool) throws -> ManualBolusRecommendation? {
        consideringPotentialCarbEntryPassed = potentialCarbEntry
        replacingCarbEntryPassed = replacedCarbEntry
        if let error = bolusRecommendationError { throw error }
        return bolusRecommendationResult
    }
}

fileprivate class MockBolusEntryViewModelDelegate: BolusEntryViewModelDelegate {
        
    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval {
        return .hours(6) + .minutes(10)
    }
    
    var pumpInsulinType: InsulinType?

    var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable = DisplayGlucoseUnitObservable(displayGlucoseUnit: .milligramsPerDeciliter)

    var loopStateCallBlock: ((LoopState) -> Void)?
    func withLoopState(do block: @escaping (LoopState) -> Void) {
        loopStateCallBlock = block
    }
    
    var glucoseSamplesAdded = [NewGlucoseSample]()
    var addGlucoseCompletion: ((Swift.Result<[StoredGlucoseSample], Error>) -> Void)?
    func addGlucoseSamples(_ samples: [NewGlucoseSample], completion: ((Swift.Result<[StoredGlucoseSample], Error>) -> Void)?) {
        glucoseSamplesAdded.append(contentsOf: samples)
        addGlucoseCompletion = completion
    }
    
    var carbEntriesAdded = [(NewCarbEntry, StoredCarbEntry?)]()
    var addCarbEntryCompletion: ((Result<StoredCarbEntry>) -> Void)?
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry?, completion: @escaping (Result<StoredCarbEntry>) -> Void) {
        carbEntriesAdded.append((carbEntry, replacingEntry))
        addCarbEntryCompletion = completion
    }
    
    var bolusDosingDecisionsAdded = [(BolusDosingDecision, Date)]()
    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        bolusDosingDecisionsAdded.append((bolusDosingDecision, date))
    }

    var enactedBolusUnits: Double?
    var enactedBolusAutomatic: Bool?
    func enactBolus(units: Double, automatic: Bool, completion: @escaping (Error?) -> Void) {
        enactedBolusUnits = units
        enactedBolusAutomatic = automatic
    }
    
    var getGlucoseSamplesResponse: [StoredGlucoseSample] = []
    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void) {
        completion(.success(getGlucoseSamplesResponse))
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
    
    var ensureCurrentPumpDataCompletion: ((Date?) -> Void)?
    func ensureCurrentPumpData(completion: @escaping (Date?) -> Void) {
        ensureCurrentPumpDataCompletion = completion
    }
    
    var mostRecentGlucoseDataDate: Date?
    
    var mostRecentPumpDataDate: Date?
    
    var isPumpConfigured: Bool = true
    
    var preferredGlucoseUnit: HKUnit = .milligramsPerDeciliter
    
    var insulinModel: InsulinModel? = MockInsulinModel()
    
    var settings: LoopSettings = LoopSettings()
}

fileprivate struct MockInsulinModel: InsulinModel {
    func percentEffectRemaining(at time: TimeInterval) -> Double { 0 }
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

extension BolusDosingDecision: Equatable {
    init(for reason: Reason, originalCarbEntry: StoredCarbEntry? = nil, carbEntry: StoredCarbEntry? = nil, manualGlucoseSample: StoredGlucoseSample? = nil, manualBolusRequested: Double? = nil) {
        self.init(for: reason)
        self.originalCarbEntry = originalCarbEntry
        self.carbEntry = carbEntry
        self.manualGlucoseSample = manualGlucoseSample
        self.manualBolusRequested = manualBolusRequested
    }

    public static func ==(lhs: BolusDosingDecision, rhs: BolusDosingDecision) -> Bool {
        return lhs.originalCarbEntry == rhs.originalCarbEntry &&
            lhs.carbEntry == rhs.carbEntry &&
            lhs.manualGlucoseSample == rhs.manualGlucoseSample &&
            lhs.insulinOnBoard == rhs.insulinOnBoard &&
            lhs.carbsOnBoard == rhs.carbsOnBoard &&
            lhs.glucoseTargetRangeSchedule == rhs.glucoseTargetRangeSchedule &&
            lhs.predictedGlucose == rhs.predictedGlucose &&
            lhs.manualBolusRecommendation == rhs.manualBolusRecommendation &&
            lhs.manualBolusRequested == rhs.manualBolusRequested
    }
}

extension ManualBolusRecommendationWithDate: Equatable {
    public static func == (lhs: ManualBolusRecommendationWithDate, rhs: ManualBolusRecommendationWithDate) -> Bool {
        return lhs.recommendation == rhs.recommendation && lhs.date == rhs.date
    }
}
