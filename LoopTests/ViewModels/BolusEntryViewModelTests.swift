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

@MainActor
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

    static let exampleGlucoseRangeSchedule = GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: [
        RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 100, maxValue: 110)),
        RepeatingScheduleValue(startTime: TimeInterval(28800), value: DoubleRange(minValue: 90, maxValue: 100)),
        RepeatingScheduleValue(startTime: TimeInterval(75600), value: DoubleRange(minValue: 100, maxValue: 110))
    ], timeZone: .utcTimeZone)!

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

    override func setUp(completion: @escaping (Error?) -> Void) {
        now = Self.now
        delegate = MockBolusEntryViewModelDelegate()
        delegate.mostRecentGlucoseDataDate = now
        delegate.mostRecentPumpDataDate = now
        saveAndDeliverSuccess = false
        Task {
            await setUpViewModel()
            completion(nil)
        }
    }

    func setUpViewModel(originalCarbEntry: StoredCarbEntry? = nil, potentialCarbEntry: NewCarbEntry? = nil, selectedCarbAbsorptionTimeEmoji: String? = nil) async {
        bolusEntryViewModel = BolusEntryViewModel(delegate: delegate,
                                                  now: { self.now },
                                                  screenWidth: 512,
                                                  debounceIntervalMilliseconds: 0,
                                                  uuidProvider: { self.mockUUID },
                                                  timeZone: TimeZone(abbreviation: "GMT")!,
                                                  originalCarbEntry: originalCarbEntry,
                                                  potentialCarbEntry: potentialCarbEntry,
                                                  selectedCarbAbsorptionTimeEmoji: selectedCarbAbsorptionTimeEmoji)
        bolusEntryViewModel.authenticationHandler = { _ in return true }
        
        bolusEntryViewModel.maximumBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 10)

        await bolusEntryViewModel.generateRecommendationAndStartObserving()
    }

    func testInitialConditions() throws {
        XCTAssertEqual(0, bolusEntryViewModel.glucoseValues.count)
        XCTAssertEqual(0, bolusEntryViewModel.predictedGlucoseValues.count)
        XCTAssertNil(bolusEntryViewModel.activeCarbs)
        XCTAssertNil(bolusEntryViewModel.activeInsulin)
        XCTAssertEqual(bolusEntryViewModel.targetGlucoseSchedule, BolusEntryViewModelTests.exampleGlucoseRangeSchedule)
        XCTAssertNil(bolusEntryViewModel.preMealOverride)
        XCTAssertNil(bolusEntryViewModel.scheduleOverride)
       
        XCTAssertFalse(bolusEntryViewModel.isManualGlucoseEntryEnabled)

        XCTAssertNil(bolusEntryViewModel.manualGlucoseQuantity)
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 0), bolusEntryViewModel.recommendedBolus)
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 0), bolusEntryViewModel.enteredBolus)

        XCTAssertNil(bolusEntryViewModel.activeAlert)
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }
    
    func testChartDateInterval() throws {
        // TODO: Test different screen widths
        // TODO: Test different insulin models
        // TODO: Test different chart history settings
        let expected = DateInterval(start: now - .hours(2), duration: .hours(8))
        XCTAssertEqual(expected, bolusEntryViewModel.chartDateInterval)
    }

    // MARK: updating state
    
    func testUpdateDisableManualGlucoseEntryIfNecessary() async throws {
        bolusEntryViewModel.isManualGlucoseEntryEnabled = true
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        await bolusEntryViewModel.update()
        XCTAssertFalse(bolusEntryViewModel.isManualGlucoseEntryEnabled)
        XCTAssertNil(bolusEntryViewModel.manualGlucoseQuantity)
        XCTAssertEqual(.glucoseNoLongerStale, bolusEntryViewModel.activeAlert)
    }
    
    func testUpdateDisableManualGlucoseEntryIfNecessaryStaleGlucose() async throws {
        delegate.mostRecentGlucoseDataDate = Date.distantPast
        bolusEntryViewModel.isManualGlucoseEntryEnabled = true
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        await bolusEntryViewModel.update()
        XCTAssertTrue(bolusEntryViewModel.isManualGlucoseEntryEnabled)
        XCTAssertEqual(Self.exampleManualGlucoseQuantity, bolusEntryViewModel.manualGlucoseQuantity)
        XCTAssertNil(bolusEntryViewModel.activeAlert)
    }

    func testUpdateGlucoseValues() async throws {
        XCTAssertEqual(0, bolusEntryViewModel.glucoseValues.count)
        delegate.getGlucoseSamplesResponse = [StoredGlucoseSample(sample: Self.exampleCGMGlucoseSample)]
        await bolusEntryViewModel.update()
        XCTAssertEqual(1, bolusEntryViewModel.glucoseValues.count)
        XCTAssertEqual([100.4], bolusEntryViewModel.glucoseValues.map {
            return $0.quantity.doubleValue(for: .milligramsPerDeciliter)
        })
    }
    
    func testUpdateGlucoseValuesWithManual() async throws {
        XCTAssertEqual(0, bolusEntryViewModel.glucoseValues.count)
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        delegate.getGlucoseSamplesResponse = [StoredGlucoseSample(sample: Self.exampleCGMGlucoseSample)]
        await bolusEntryViewModel.update()
        XCTAssertEqual([100.4, 123.4], bolusEntryViewModel.glucoseValues.map {
            return $0.quantity.doubleValue(for: .milligramsPerDeciliter)
        })
    }
    
    func testManualEntryClearsEnteredBolus() throws {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 0), bolusEntryViewModel.enteredBolus)
    }
    
    func testUpdatePredictedGlucoseValues() async throws {
        let prediction = [PredictedGlucoseValue(startDate: Self.exampleStartDate, quantity: Self.exampleCGMGlucoseQuantity)]
        delegate.loopState.predictGlucoseValueResult = prediction
        await bolusEntryViewModel.update()
        XCTAssertEqual(prediction, bolusEntryViewModel.predictedGlucoseValues.map { PredictedGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) })
    }
    
    func testUpdatePredictedGlucoseValuesWithManual() async throws {
        let prediction = [PredictedGlucoseValue(startDate: Self.exampleStartDate, quantity: Self.exampleCGMGlucoseQuantity)]
        delegate.loopState.predictGlucoseValueResult = prediction
        await bolusEntryViewModel.update()

        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        XCTAssertEqual(prediction,
                       bolusEntryViewModel.predictedGlucoseValues.map {
                        PredictedGlucoseValue(startDate: $0.startDate, quantity: $0.quantity)
        })
    }
    
    func testUpdateSettings() async throws {
        XCTAssertNil(bolusEntryViewModel.preMealOverride)
        XCTAssertNil(bolusEntryViewModel.scheduleOverride)
        XCTAssertEqual(bolusEntryViewModel.targetGlucoseSchedule, BolusEntryViewModelTests.exampleGlucoseRangeSchedule)
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
        bolusEntryViewModel.updateSettings()
        await bolusEntryViewModel.update()

        XCTAssertEqual(newSettings.preMealOverride, bolusEntryViewModel.preMealOverride)
        XCTAssertEqual(newSettings.scheduleOverride, bolusEntryViewModel.scheduleOverride)
        XCTAssertEqual(newGlucoseTargetRangeSchedule, bolusEntryViewModel.targetGlucoseSchedule)
    }

    func testUpdateSettingsWithCarbs() async throws {
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        XCTAssertNil(bolusEntryViewModel.preMealOverride)
        XCTAssertNil(bolusEntryViewModel.scheduleOverride)
        XCTAssertEqual(bolusEntryViewModel.targetGlucoseSchedule, BolusEntryViewModelTests.exampleGlucoseRangeSchedule)
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
        bolusEntryViewModel.updateSettings()

        // Pre-meal override should be ignored if we have carbs (LOOP-1964), and cleared in settings
        XCTAssertEqual(newSettings.scheduleOverride, bolusEntryViewModel.scheduleOverride)
        XCTAssertEqual(newGlucoseTargetRangeSchedule, bolusEntryViewModel.targetGlucoseSchedule)
        
        // ... but restored if we cancel without bolusing
        bolusEntryViewModel = nil
    }
    
    func testManualGlucoseChangesPredictedGlucoseValues() async throws {
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        let prediction = [PredictedGlucoseValue(startDate: Self.exampleStartDate, quantity: Self.exampleCGMGlucoseQuantity)]
        delegate.loopState.predictGlucoseValueResult = prediction
        await bolusEntryViewModel.update()

        XCTAssertEqual(prediction,
                       bolusEntryViewModel.predictedGlucoseValues.map {
                        PredictedGlucoseValue(startDate: $0.startDate, quantity: $0.quantity)
        })
    }
    
    func testUpdateInsulinOnBoard() async throws {
        delegate.insulinOnBoardResult = .success(InsulinValue(startDate: Self.exampleStartDate, value: 1.5))
        XCTAssertNil(bolusEntryViewModel.activeInsulin)
        await bolusEntryViewModel.update()
        XCTAssertEqual(HKQuantity(unit: .internationalUnit(), doubleValue: 1.5), bolusEntryViewModel.activeInsulin)
    }
    
    func testUpdateCarbsOnBoard() async throws {
        delegate.carbsOnBoardResult = .success(CarbValue(startDate: Self.exampleStartDate, endDate: Self.exampleEndDate, quantity: Self.exampleCarbQuantity))
        XCTAssertNil(bolusEntryViewModel.activeCarbs)
        await bolusEntryViewModel.update()
        XCTAssertEqual(Self.exampleCarbQuantity, bolusEntryViewModel.activeCarbs)
    }
    
    func testUpdateCarbsOnBoardFailure() async throws {
        delegate.carbsOnBoardResult = .failure(CarbStore.CarbStoreError.notConfigured)
        await bolusEntryViewModel.update()
        XCTAssertNil(bolusEntryViewModel.activeCarbs)
    }

    func testUpdateRecommendedBolusNoNotice() async throws {
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendation = ManualBolusRecommendation(amount: 1.25, pendingInsulin: 4.321)
        delegate.loopState.bolusRecommendationResult = recommendation
        await bolusEntryViewModel.update()
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(recommendation.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        let consideringPotentialCarbEntryPassed = try XCTUnwrap(delegate.loopState.consideringPotentialCarbEntryPassed)
        XCTAssertEqual(mockPotentialCarbEntry, consideringPotentialCarbEntryPassed)
        let replacingCarbEntryPassed = try XCTUnwrap(delegate.loopState.replacingCarbEntryPassed)
        XCTAssertEqual(mockOriginalCarbEntry, replacingCarbEntryPassed)
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }
            
    func testUpdateRecommendedBolusWithNotice() async throws {
        delegate.settings.suspendThreshold = GlucoseThreshold(unit: .milligramsPerDeciliter, value: Self.exampleCGMGlucoseQuantity.doubleValue(for: .milligramsPerDeciliter))
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendation = ManualBolusRecommendation(amount: 1.25, pendingInsulin: 4.321, notice: BolusRecommendationNotice.glucoseBelowSuspendThreshold(minGlucose: Self.exampleGlucoseValue))
        delegate.loopState.bolusRecommendationResult = recommendation
        await bolusEntryViewModel.update()
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(recommendation.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        XCTAssertEqual(BolusEntryViewModel.Notice.predictedGlucoseBelowSuspendThreshold(suspendThreshold: Self.exampleCGMGlucoseQuantity), bolusEntryViewModel.activeNotice)
    }
    
    func testUpdateRecommendedBolusWithNoticeMissingSuspendThreshold() async throws {
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        delegate.settings.suspendThreshold = nil
        let recommendation = ManualBolusRecommendation(amount: 1.25, pendingInsulin: 4.321, notice: BolusRecommendationNotice.glucoseBelowSuspendThreshold(minGlucose: Self.exampleGlucoseValue))
        delegate.loopState.bolusRecommendationResult = recommendation
        await bolusEntryViewModel.update()
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(recommendation.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }

    func testUpdateRecommendedBolusWithOtherNotice() async throws {
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendation = ManualBolusRecommendation(amount: 1.25, pendingInsulin: 4.321, notice: BolusRecommendationNotice.currentGlucoseBelowTarget(glucose: Self.exampleGlucoseValue))
        delegate.loopState.bolusRecommendationResult = recommendation
        await bolusEntryViewModel.update()
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(recommendation.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }
        
    func testUpdateRecommendedBolusThrowsMissingDataError() async throws {
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        delegate.loopState.bolusRecommendationError = LoopError.missingDataError(.glucose)
        await bolusEntryViewModel.update()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNil(recommendedBolus)
        XCTAssertEqual(.staleGlucoseData, bolusEntryViewModel.activeNotice)
    }
    
    func testUpdateRecommendedBolusThrowsPumpDataTooOld() async throws {
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        delegate.loopState.bolusRecommendationError = LoopError.pumpDataTooOld(date: now)
        await bolusEntryViewModel.update()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNil(recommendedBolus)
        XCTAssertEqual(.stalePumpData, bolusEntryViewModel.activeNotice)
    }

    func testUpdateRecommendedBolusThrowsGlucoseTooOld() async throws {
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        delegate.loopState.bolusRecommendationError = LoopError.glucoseTooOld(date: now)
        await bolusEntryViewModel.update()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNil(recommendedBolus)
        XCTAssertEqual(.staleGlucoseData, bolusEntryViewModel.activeNotice)
    }

    func testUpdateRecommendedBolusThrowsInvalidFutureGlucose() async throws {
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        delegate.loopState.bolusRecommendationError = LoopError.invalidFutureGlucose(date: now)
        await bolusEntryViewModel.update()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNil(recommendedBolus)
        XCTAssertEqual(.futureGlucoseData, bolusEntryViewModel.activeNotice)
    }

    func testUpdateRecommendedBolusThrowsOtherError() async throws {
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        delegate.loopState.bolusRecommendationError = LoopError.pumpSuspended
        await bolusEntryViewModel.update()
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNil(recommendedBolus)
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }
    
    func testUpdateRecommendedBolusWithManual() async throws {
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        XCTAssertFalse(bolusEntryViewModel.isBolusRecommended)
        let recommendation = ManualBolusRecommendation(amount: 1.25, pendingInsulin: 4.321)
        delegate.loopState.bolusRecommendationResult = recommendation
        await bolusEntryViewModel.update()
        XCTAssertTrue(bolusEntryViewModel.isBolusRecommended)
        let recommendedBolus = bolusEntryViewModel.recommendedBolus
        XCTAssertNotNil(recommendedBolus)
        XCTAssertEqual(recommendation.amount, recommendedBolus?.doubleValue(for: .internationalUnit()))
        let consideringPotentialCarbEntryPassed = try XCTUnwrap(delegate.loopState.consideringPotentialCarbEntryPassed)
        XCTAssertEqual(mockPotentialCarbEntry, consideringPotentialCarbEntryPassed)
        let replacingCarbEntryPassed = try XCTUnwrap(delegate.loopState.replacingCarbEntryPassed)
        XCTAssertEqual(mockOriginalCarbEntry, replacingCarbEntryPassed)
        XCTAssertNil(bolusEntryViewModel.activeNotice)
    }

    // MARK: save data and bolus delivery

    func testDeliverBolusOnlyRecommendationChanged() async throws {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity

        let success = await bolusEntryViewModel.saveAndDeliver()

        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(.manualRecommendationChanged, delegate.enactedBolusActivationType)
        XCTAssertTrue(success)
        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.reason, .normalBolus)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.manualBolusRequested, 1.0)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
    }

    func testBolusTooSmall() async throws {
        bolusEntryViewModel.enteredBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0.01)
        let success = await bolusEntryViewModel.saveAndDeliver()
        XCTAssertEqual(.bolusTooSmall, bolusEntryViewModel.activeAlert)
        XCTAssertNil(delegate.enactedBolusUnits)
        XCTAssertFalse(success)
        XCTAssertEqual(0, delegate.bolusDosingDecisionsAdded.count)
    }


    func testDeliverBolusOnlyRecommendationAccepted() async throws {
        bolusEntryViewModel.recommendedBolus = Self.exampleBolusQuantity
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity

        let success = await bolusEntryViewModel.saveAndDeliver()

        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(.manualRecommendationAccepted, delegate.enactedBolusActivationType)
        XCTAssertTrue(success)
        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.reason, .normalBolus)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.manualBolusRequested, 1.0)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
    }

    func testDeliverBolusOnlyNoRecommendation() async throws {
        bolusEntryViewModel.recommendedBolus = nil
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity

        let success = await bolusEntryViewModel.saveAndDeliver()

        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(.manualNoRecommendation, delegate.enactedBolusActivationType)
        XCTAssertTrue(success)
        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.reason, .normalBolus)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.manualBolusRequested, 1.0)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
    }

    struct MockError: Error {}
    func testDeliverBolusAuthFail() async throws {
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity

        // Mock failed authentication
        bolusEntryViewModel.authenticationHandler = { _ in return false }

        let success = await bolusEntryViewModel.saveAndDeliver()

        XCTAssertNil(delegate.enactedBolusUnits)
        XCTAssertNil(delegate.enactedBolusActivationType)
        XCTAssertFalse(success)
        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertTrue(delegate.bolusDosingDecisionsAdded.isEmpty)
    }
    
    private func saveAndDeliver(_ bolus: HKQuantity, file: StaticString = #file, line: UInt = #line) async throws {
        bolusEntryViewModel.enteredBolus = bolus

        self.saveAndDeliverSuccess = await bolusEntryViewModel.saveAndDeliver()
    }
    
    func testSaveManualGlucoseNoBolus() async throws {
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity

        bolusEntryViewModel.enteredBolus = BolusEntryViewModelTests.noBolus

        delegate.addGlucoseSamplesResult = .success([Self.exampleManualStoredGlucoseSample])

        let saveAndDeliverSuccess = await bolusEntryViewModel.saveAndDeliver()

        let expectedGlucoseSample = NewGlucoseSample(date: now, quantity: Self.exampleManualGlucoseQuantity, condition: nil, trend: nil, trendRate: nil, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: mockUUID)
        
        XCTAssertEqual([expectedGlucoseSample], delegate.glucoseSamplesAdded)

        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.reason, .normalBolus)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.manualBolusRequested, 0.0)

        let addedGlucose = delegate.bolusDosingDecisionsAdded.first!.0.manualGlucoseSample
        XCTAssertEqual(addedGlucose?.quantity, Self.exampleManualGlucoseQuantity)
        XCTAssertEqual(addedGlucose?.startDate, now)

        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertNil(delegate.enactedBolusUnits)
        XCTAssertNil(delegate.enactedBolusActivationType)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveCarbGlucoseNoBolus() async throws {
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        delegate.addGlucoseSamplesResult = .success([Self.exampleManualStoredGlucoseSample])
        delegate.addCarbEntryResult = .success(mockFinalCarbEntry)

        try await saveAndDeliver(BolusEntryViewModelTests.noBolus)

        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertEqual(1, delegate.carbEntriesAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.reason, .normalBolus)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.originalCarbEntry, mockOriginalCarbEntry)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.carbEntry, mockFinalCarbEntry)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.manualBolusRequested, 0.0)

        XCTAssertEqual(mockOriginalCarbEntry, delegate.carbEntriesAdded.first?.1)

        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertNil(delegate.enactedBolusUnits)
        XCTAssertNil(delegate.enactedBolusActivationType)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveManualGlucoseAndBolus() async throws {
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity

        delegate.addGlucoseSamplesResult = .success([Self.exampleManualStoredGlucoseSample])

        try await saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)
        
        let expectedGlucoseSample = NewGlucoseSample(date: now, quantity: Self.exampleManualGlucoseQuantity, condition: nil, trend: nil, trendRate: nil, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: mockUUID)
        XCTAssertEqual([expectedGlucoseSample], delegate.glucoseSamplesAdded)
        
        XCTAssertTrue(delegate.carbEntriesAdded.isEmpty)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.reason, .normalBolus)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.manualBolusRequested, 1.0)

        let addedGlucose = delegate.bolusDosingDecisionsAdded.first!.0.manualGlucoseSample
        XCTAssertEqual(addedGlucose?.quantity, Self.exampleManualGlucoseQuantity)
        XCTAssertEqual(addedGlucose?.startDate, now)

        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(.manualRecommendationChanged, delegate.enactedBolusActivationType)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveCarbAndBolus() async throws {
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        delegate.addCarbEntryResult = .success(mockFinalCarbEntry)

        try await saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)

        XCTAssertTrue(delegate.glucoseSamplesAdded.isEmpty)
        XCTAssertEqual(1, delegate.carbEntriesAdded.count)
        XCTAssertEqual(mockPotentialCarbEntry, delegate.carbEntriesAdded.first?.0)
        XCTAssertEqual(mockOriginalCarbEntry, delegate.carbEntriesAdded.first?.1)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.reason, .normalBolus)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.originalCarbEntry, mockOriginalCarbEntry)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.carbEntry, mockFinalCarbEntry)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.manualBolusRequested, 1.0)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(.manualRecommendationChanged, delegate.enactedBolusActivationType)
        XCTAssertTrue(saveAndDeliverSuccess)
    }
    
    func testSaveCarbAndBolusClearsSavedPreMealOverride() async throws {
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
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
        bolusEntryViewModel.updateSettings()

        delegate.addCarbEntryResult = .success(mockFinalCarbEntry)

        try await saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)

        XCTAssertTrue(saveAndDeliverSuccess)

        // ... make sure the "restoring" of the saved pre-meal override does not happen
        bolusEntryViewModel = nil
    }

    func testSaveManualGlucoseAndCarbAndBolus() async throws {
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity

        delegate.addGlucoseSamplesResult = .success([Self.exampleManualStoredGlucoseSample])
        delegate.addCarbEntryResult = .success(mockFinalCarbEntry)

        try await saveAndDeliver(BolusEntryViewModelTests.exampleBolusQuantity)
        
        let expectedGlucoseSample = NewGlucoseSample(date: now, quantity: Self.exampleManualGlucoseQuantity, condition: nil, trend: nil, trendRate: nil, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: mockUUID)
        XCTAssertEqual([expectedGlucoseSample], delegate.glucoseSamplesAdded)

        XCTAssertEqual(1, delegate.carbEntriesAdded.count)
        XCTAssertEqual(mockPotentialCarbEntry, delegate.carbEntriesAdded.first?.0)
        XCTAssertEqual(mockOriginalCarbEntry, delegate.carbEntriesAdded.first?.1)
        XCTAssertEqual(1, delegate.bolusDosingDecisionsAdded.count)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.reason, .normalBolus)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.manualBolusRequested, 1.0)

        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.originalCarbEntry, mockOriginalCarbEntry)
        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.0.carbEntry, mockFinalCarbEntry)

        let addedGlucose = delegate.bolusDosingDecisionsAdded.first!.0.manualGlucoseSample
        XCTAssertEqual(addedGlucose?.quantity, Self.exampleManualGlucoseQuantity)
        XCTAssertEqual(addedGlucose?.startDate, now)

        XCTAssertEqual(delegate.bolusDosingDecisionsAdded.first?.1, now)
        XCTAssertEqual(1.0, delegate.enactedBolusUnits)
        XCTAssertEqual(.manualRecommendationChanged, delegate.enactedBolusActivationType)
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
    
    func testCarbEntryAmountAndEmojiString() async throws {
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        XCTAssertEqual("234 g foodType", bolusEntryViewModel.carbEntryAmountAndEmojiString)
    }
    
    func testCarbEntryAmountAndEmojiStringNoFoodType() async throws {
        let potentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: Self.exampleStartDate, foodType: nil, absorptionTime: 1)
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: potentialCarbEntry)

        XCTAssertEqual("234 g", bolusEntryViewModel.carbEntryAmountAndEmojiString)
    }
    
    func testCarbEntryAmountAndEmojiStringWithEmoji() async throws {
        let potentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: Self.exampleStartDate, foodType: nil, absorptionTime: 1)
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: potentialCarbEntry, selectedCarbAbsorptionTimeEmoji: "😀")

        XCTAssertEqual("234 g 😀", bolusEntryViewModel.carbEntryAmountAndEmojiString)
    }
    
    func testCarbEntryDateAndAbsorptionTimeStringNil() throws {
        XCTAssertNil(bolusEntryViewModel.carbEntryDateAndAbsorptionTimeString)
    }
    
    func testCarbEntryDateAndAbsorptionTimeString() async throws {
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: mockPotentialCarbEntry)

        XCTAssertEqual("12:00 PM + 0m", bolusEntryViewModel.carbEntryDateAndAbsorptionTimeString)
    }
    
    func testCarbEntryDateAndAbsorptionTimeString2() async throws {
        let potentialCarbEntry = NewCarbEntry(quantity: BolusEntryViewModelTests.exampleCarbQuantity, startDate: Self.exampleStartDate, foodType: nil, absorptionTime: nil)
        await setUpViewModel(originalCarbEntry: mockOriginalCarbEntry, potentialCarbEntry: potentialCarbEntry)

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
    
    func testActionButtonPotentialCarbEntry() async {
        await setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
        XCTAssertEqual(.saveWithoutBolusing, bolusEntryViewModel.actionButtonAction)
    }
    
    func testActionButtonManualGlucoseAndPotentialCarbEntry() async {
        await setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
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
    
    func testActionButtonSaveAndDeliverPotentialCarbEntry() async {
        await setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        XCTAssertEqual(.saveAndDeliver, bolusEntryViewModel.actionButtonAction)
    }

    func testActionButtonSaveAndDeliverBothManualGlucoseAndPotentialCarbEntry() async {
        await setUpViewModel(potentialCarbEntry: mockPotentialCarbEntry)
        bolusEntryViewModel.manualGlucoseQuantity = Self.exampleManualGlucoseQuantity
        bolusEntryViewModel.enteredBolus = Self.exampleBolusQuantity
        XCTAssertEqual(.saveAndDeliver, bolusEntryViewModel.actionButtonAction)
    }
}

// MARK: utilities

fileprivate class MockLoopState: LoopState {
    
    var carbsOnBoard: CarbValue?
    
    var insulinOnBoard: InsulinValue?
    
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

public enum BolusEntryViewTestError: Error {
    case responseUndefined
}

fileprivate class MockBolusEntryViewModelDelegate: BolusEntryViewModelDelegate {

    fileprivate var loopState = MockLoopState()

    private let dataAccessQueue = DispatchQueue(label: "com.loopKit.tests.dataAccessQueue", qos: .utility)


    func updateRemoteRecommendation() {
    }

    func roundBolusVolume(units: Double) -> Double {
        // 0.05 units for rates between 0.05-30U/hr
        // 0 is not a supported bolus volume
        let supportedBolusVolumes = (1...600).map { Double($0) / 20.0 }
        return ([0.0] + supportedBolusVolumes).enumerated().min( by: { abs($0.1 - units) < abs($1.1 - units) } )!.1
    }

    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval {
        return .hours(6) + .minutes(10)
    }
    
    var pumpInsulinType: InsulinType?

    var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable = DisplayGlucoseUnitObservable(displayGlucoseUnit: .milligramsPerDeciliter)

    func withLoopState(do block: @escaping (LoopState) -> Void) {
        dataAccessQueue.async {
            block(self.loopState)
        }
    }

    func saveGlucose(sample: LoopKit.NewGlucoseSample) async -> LoopKit.StoredGlucoseSample? {
        glucoseSamplesAdded.append(sample)
        return StoredGlucoseSample(sample: sample.quantitySample)
    }

    var glucoseSamplesAdded = [NewGlucoseSample]()
    var addGlucoseSamplesResult: Swift.Result<[StoredGlucoseSample], Error> = .failure(BolusEntryViewTestError.responseUndefined)
    func addGlucoseSamples(_ samples: [NewGlucoseSample], completion: ((Swift.Result<[StoredGlucoseSample], Error>) -> Void)?) {
        glucoseSamplesAdded.append(contentsOf: samples)
        completion?(addGlucoseSamplesResult)
    }
    
    var carbEntriesAdded = [(NewCarbEntry, StoredCarbEntry?)]()
    var addCarbEntryResult: Result<StoredCarbEntry> = .failure(BolusEntryViewTestError.responseUndefined)
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry?, completion: @escaping (Result<StoredCarbEntry>) -> Void) {
        carbEntriesAdded.append((carbEntry, replacingEntry))
        completion(addCarbEntryResult)
    }
    
    var bolusDosingDecisionsAdded = [(BolusDosingDecision, Date)]()
    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        bolusDosingDecisionsAdded.append((bolusDosingDecision, date))
    }

    var enactedBolusUnits: Double?
    var enactedBolusActivationType: BolusActivationType?
    func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (Error?) -> Void) {
        enactedBolusUnits = units
        enactedBolusActivationType = activationType
    }
    
    var getGlucoseSamplesResponse: [StoredGlucoseSample] = []
    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void) {
        completion(.success(getGlucoseSamplesResponse))
    }
    
    var insulinOnBoardResult: DoseStoreResult<InsulinValue>?
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        if let insulinOnBoardResult = insulinOnBoardResult {
            completion(insulinOnBoardResult)
        } else {
            completion(.failure(.configurationError))
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
    
    var settings: LoopSettings = LoopSettings(
        dosingEnabled: true,
        glucoseTargetRangeSchedule: BolusEntryViewModelTests.exampleGlucoseRangeSchedule,
        maximumBasalRatePerHour: 3.0,
        maximumBolus: 10.0,
        suspendThreshold: GlucoseThreshold(unit: .internationalUnit(), value: 75)) {
            didSet {
                NotificationCenter.default.post(name: .LoopDataUpdated, object: nil, userInfo: [
                    LoopDataManager.LoopUpdateContextKey: LoopDataManager.LoopUpdateContext.preferences.rawValue
                ])
            }
        }

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
