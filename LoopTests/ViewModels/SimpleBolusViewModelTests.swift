//
//  SimpleBolusViewModelTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 10/12/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
import LoopKitUI
import LoopCore

@testable import Loop

class SimpleBolusViewModelTests: XCTestCase {
    
    enum MockError: Error {
        case authentication
    }
    
    var addedGlucose: [NewGlucoseSample] = []
    var addedCarbEntry: NewCarbEntry?
    var storedBolusDecision: BolusDosingDecision?
    var enactedBolus: (units: Double, activationType: BolusActivationType)?
    var currentIOB: InsulinValue = SimpleBolusViewModelTests.noIOB
    var currentRecommendation: Double = 0
    var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable = DisplayGlucoseUnitObservable(displayGlucoseUnit: .milligramsPerDeciliter)

    static var noIOB = InsulinValue(startDate: Date(), value: 0)
    static var someIOB = InsulinValue(startDate: Date(), value: 2.4)
    
    override func setUp() {
        addedGlucose = []
        addedCarbEntry = nil
        enactedBolus = nil
        currentRecommendation = 0
    }
    
    func testFailedAuthenticationShouldNotSaveDataOrBolus() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        viewModel.authenticate = { (description, completion) in
            completion(.failure(MockError.authentication))
        }
        
        viewModel.enteredBolusString = "3"
        
        let saveExpectation = expectation(description: "Save completion callback")
        
        viewModel.saveAndDeliver { (success) in
            saveExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 2)
        
        XCTAssertNil(enactedBolus)
        XCTAssertNil(addedCarbEntry)
        XCTAssert(addedGlucose.isEmpty)

    }
    
    func testIssuingBolus() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }
        
        viewModel.enteredBolusString = "3"
        
        let saveExpectation = expectation(description: "Save completion callback")
        
        viewModel.saveAndDeliver { (success) in
            saveExpectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        XCTAssertNil(addedCarbEntry)
        XCTAssert(addedGlucose.isEmpty)
        
        XCTAssertEqual(3.0, enactedBolus?.units)

    }
    
    func testMealCarbsAndManualGlucoseWithRecommendation() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentRecommendation = 2.5

        viewModel.enteredCarbString = "20"
        viewModel.manualGlucoseString = "180"
        
        let saveExpectation = expectation(description: "Save completion callback")

        viewModel.saveAndDeliver { (success) in
            saveExpectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(20, addedCarbEntry?.quantity.doubleValue(for: .gram()))
        XCTAssertEqual(180, addedGlucose.first?.quantity.doubleValue(for: .milligramsPerDeciliter))
        
        XCTAssertEqual(2.5, enactedBolus?.units)
        
        XCTAssertEqual(storedBolusDecision?.manualBolusRecommendation?.recommendation.amount, 2.5)
        XCTAssertEqual(storedBolusDecision?.carbEntry?.quantity, addedCarbEntry?.quantity)
    }
    
    func testMealCarbsWithUserOverridingRecommendation() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentRecommendation = 2.5

        // This triggers a recommendation update
        viewModel.enteredCarbString = "20"
        
        XCTAssertEqual("2.5", viewModel.recommendedBolus)
        XCTAssertEqual("2.5", viewModel.enteredBolusString)
        
        viewModel.enteredBolusString = "0.1"

        let saveExpectation = expectation(description: "Save completion callback")

        viewModel.saveAndDeliver { (success) in
            saveExpectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(20, addedCarbEntry?.quantity.doubleValue(for: .gram()))
        
        XCTAssertEqual(0.1, enactedBolus?.units)
        
        XCTAssertEqual(0.1, storedBolusDecision?.manualBolusRequested)
        XCTAssertEqual(2.5, storedBolusDecision?.manualBolusRecommendation?.recommendation.amount)
        XCTAssertEqual(addedCarbEntry?.quantity, storedBolusDecision?.carbEntry?.quantity)
    }

    func testDeleteCarbsRemovesRecommendation() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentRecommendation = 2.5

        viewModel.enteredCarbString = "20"

        XCTAssertEqual("2.5", viewModel.recommendedBolus)
        XCTAssertEqual("2.5", viewModel.enteredBolusString)

        viewModel.enteredCarbString = ""

        XCTAssertEqual("–", viewModel.recommendedBolus)
        XCTAssertEqual("0", viewModel.enteredBolusString)
    }

    func testDeleteCurrentGlucoseRemovesRecommendation() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentRecommendation = 3.0

        viewModel.manualGlucoseString = "180"

        XCTAssertEqual("3", viewModel.recommendedBolus)
        XCTAssertEqual("3", viewModel.enteredBolusString)

        viewModel.manualGlucoseString = ""

        XCTAssertEqual("–", viewModel.recommendedBolus)
        XCTAssertEqual("0", viewModel.enteredBolusString)
    }

    func testDeleteCurrentGlucoseRemovesActiveInsulin() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentIOB = SimpleBolusViewModelTests.someIOB

        viewModel.manualGlucoseString = "180"

        XCTAssertEqual("2.4", viewModel.activeInsulin)

        viewModel.manualGlucoseString = ""

        XCTAssertNil(viewModel.activeInsulin)
    }

    func testManualGlucoseStringMatchesDisplayGlucoseUnit() {
        // used "260" mg/dL ("14.4" mmol/L) since 14.40 mmol/L -> 259 mg/dL and 14.43 mmol/L -> 260 mg/dL
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        XCTAssertEqual(viewModel.manualGlucoseString, "")
        viewModel.manualGlucoseString = "260"
        XCTAssertEqual(viewModel.manualGlucoseString, "260")
        self.displayGlucoseUnitObservable.displayGlucoseUnitDidChange(to: .millimolesPerLiter)
        XCTAssertEqual(viewModel.manualGlucoseString, "14.4")
        self.displayGlucoseUnitObservable.displayGlucoseUnitDidChange(to: .milligramsPerDeciliter)
        XCTAssertEqual(viewModel.manualGlucoseString, "260")
        self.displayGlucoseUnitObservable.displayGlucoseUnitDidChange(to: .millimolesPerLiter)
        XCTAssertEqual(viewModel.manualGlucoseString, "14.4")

        viewModel.manualGlucoseString = "14.0"
        XCTAssertEqual(viewModel.manualGlucoseString, "14.0")
        viewModel.manualGlucoseString = "14.4"
        XCTAssertEqual(viewModel.manualGlucoseString, "14.4")
        self.displayGlucoseUnitObservable.displayGlucoseUnitDidChange(to: .milligramsPerDeciliter)
        XCTAssertEqual(viewModel.manualGlucoseString, "259")
    }
    
    func testGlucoseEntryWarnings() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        
        currentRecommendation = 2
        viewModel.manualGlucoseString = "180"
        XCTAssertNil(viewModel.activeNotice)
        XCTAssert(viewModel.bolusRecommended)
        
        currentRecommendation = 0
        viewModel.manualGlucoseString = "72"
        XCTAssertEqual(viewModel.activeNotice, .glucoseBelowSuspendThreshold)
        XCTAssert(!viewModel.bolusRecommended)
        XCTAssert(!viewModel.actionButtonDisabled)

        viewModel.manualGlucoseString = "69"
        XCTAssertEqual(viewModel.activeNotice, .glucoseBelowRecommendationLimit)
        viewModel.manualGlucoseString = "54"
        XCTAssertEqual(viewModel.activeNotice, .glucoseBelowRecommendationLimit)
        viewModel.manualGlucoseString = "800"
        XCTAssertEqual(viewModel.activeNotice, .glucoseOutOfAllowedInputRange)
        XCTAssert(viewModel.actionButtonDisabled)
        viewModel.manualGlucoseString = "9"
        XCTAssertEqual(viewModel.activeNotice, .glucoseOutOfAllowedInputRange)
        XCTAssert(viewModel.actionButtonDisabled)

        viewModel.manualGlucoseString = ""
        viewModel.enteredCarbString = "400"
        XCTAssertEqual(viewModel.activeNotice, .carbohydrateEntryTooLarge)
        XCTAssert(viewModel.actionButtonDisabled)
    }
    
    func testGlucoseEntryWarningsForMealBolus() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: true)
        viewModel.manualGlucoseString = "69"
        viewModel.enteredCarbString = "25"
        XCTAssertEqual(viewModel.activeNotice, .glucoseWarning)
    }
    
    func testOutOfBoundsGlucoseShowsNoRecommendation() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: true)
        viewModel.manualGlucoseString = "699"
        XCTAssert(!viewModel.bolusRecommended)
    }
    
    func testOutOfBoundsCarbsShowsNoRecommendation() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: true)
        viewModel.enteredCarbString = "400"
        XCTAssert(!viewModel.bolusRecommended)
    }
    
    func testMaxBolusWarnings() {
        let viewModel = SimpleBolusViewModel(delegate: self, displayMealEntry: false)
        viewModel.enteredBolusString = "20"
        XCTAssertEqual(viewModel.activeNotice, .maxBolusExceeded)
        
        currentRecommendation = 20
        viewModel.manualGlucoseString = "250"
        viewModel.enteredCarbString = "150"
        XCTAssertEqual(viewModel.recommendedBolus, "20")
        XCTAssertEqual(viewModel.enteredBolusString, "3")
        XCTAssertEqual(viewModel.activeNotice, .recommendationExceedsMaxBolus)
    }
}

extension SimpleBolusViewModelTests: SimpleBolusViewModelDelegate {
    func addGlucose(_ samples: [NewGlucoseSample], completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void) {
        addedGlucose = samples
        completion(.success([]))
    }
    
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry?, completion: @escaping (Result<StoredCarbEntry>) -> Void) {
        
        addedCarbEntry = carbEntry
        let storedCarbEntry = StoredCarbEntry(
            uuid: UUID(),
            provenanceIdentifier: UUID().uuidString,
            syncIdentifier: UUID().uuidString,
            syncVersion: 1,
            startDate: carbEntry.startDate,
            quantity: carbEntry.quantity,
            foodType: carbEntry.foodType,
            absorptionTime: carbEntry.absorptionTime,
            createdByCurrentApp: true,
            userCreatedDate: Date(),
            userUpdatedDate: nil)
        completion(.success(storedCarbEntry))
    }

    func enactBolus(units: Double, activationType: BolusActivationType) {
        enactedBolus = (units: units, activationType: activationType)
    }
    
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        completion(.success(currentIOB))
    }
    
    func computeSimpleBolusRecommendation(at date: Date, mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> BolusDosingDecision? {
        
        var decision = BolusDosingDecision(for: .simpleBolus)
        decision.manualBolusRecommendation = ManualBolusRecommendationWithDate(recommendation: ManualBolusRecommendation(amount: currentRecommendation, pendingInsulin: 0, notice: .none),
                                                                               date: date)
        decision.insulinOnBoard = currentIOB
        return decision
    }
    
    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        storedBolusDecision = bolusDosingDecision
    }

    var maximumBolus: Double {
        return 3.0
    }
    
    var suspendThreshold: HKQuantity {
        return HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)
    }
}
