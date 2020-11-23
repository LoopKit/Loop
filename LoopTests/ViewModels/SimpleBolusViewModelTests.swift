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
import LoopCore
@testable import Loop

class SimpleBolusViewModelTests: XCTestCase {
    
    enum MockError: Error {
        case authentication
    }
    
    var addedGlucose: [NewGlucoseSample] = []
    var addedCarbEntry: NewCarbEntry?
    var storedBolusDecision: BolusDosingDecision?
    var enactedBolus: (units: Double, startDate: Date)?
    var currentIOB: InsulinValue = SimpleBolusViewModelTests.noIOB
    var currentRecommendation: Double = 0

    static var noIOB = InsulinValue(startDate: Date(), value: 0)
    static var someIOB = InsulinValue(startDate: Date(), value: 2.4)

    
    override func setUp() {
        addedGlucose = []
        addedCarbEntry = nil
        enactedBolus = nil
        currentRecommendation = 0
    }
    
    func testFailedAuthenticationShouldNotSaveDataOrBolus() {
        let viewModel = SimpleBolusViewModel(delegate: self)
        viewModel.authenticate = { (description, completion) in
            completion(.failure(MockError.authentication))
        }
        
        viewModel.enteredBolusAmount = "3"
        
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
        let viewModel = SimpleBolusViewModel(delegate: self)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }
        
        viewModel.enteredBolusAmount = "3"
        
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
        let viewModel = SimpleBolusViewModel(delegate: self)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentRecommendation = 2.5

        viewModel.enteredCarbAmount = "20"
        viewModel.enteredGlucoseAmount = "180"
        
        let saveExpectation = expectation(description: "Save completion callback")

        viewModel.saveAndDeliver { (success) in
            saveExpectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(20, addedCarbEntry?.quantity.doubleValue(for: .gram()))
        XCTAssertEqual(180, addedGlucose.first?.quantity.doubleValue(for: .milligramsPerDeciliter))
        
        XCTAssertEqual(2.5, enactedBolus?.units)
        
        XCTAssertEqual(storedBolusDecision?.recommendedBolus?.amount, 2.5)
        XCTAssertEqual(storedBolusDecision?.carbEntry?.quantity, addedCarbEntry?.quantity)
    }
    
    func testMealCarbsWithUserOverridingRecommendation() {
        let viewModel = SimpleBolusViewModel(delegate: self)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentRecommendation = 2.5

        // This triggers a recommendation update
        viewModel.enteredCarbAmount = "20"
        
        XCTAssertEqual("2.5", viewModel.recommendedBolus)
        XCTAssertEqual("2.5", viewModel.enteredBolusAmount)
        
        viewModel.enteredBolusAmount = "0.1"

        let saveExpectation = expectation(description: "Save completion callback")

        viewModel.saveAndDeliver { (success) in
            saveExpectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        XCTAssertEqual(20, addedCarbEntry?.quantity.doubleValue(for: .gram()))
        
        XCTAssertEqual(0.1, enactedBolus?.units)
        
        XCTAssertEqual(0.1, storedBolusDecision?.requestedBolus)
        XCTAssertEqual(2.5, storedBolusDecision?.recommendedBolus?.amount)
        XCTAssertEqual(addedCarbEntry?.quantity, storedBolusDecision?.carbEntry?.quantity)
    }

    func testDeleteCarbsRemovesRecommendation() {
        let viewModel = SimpleBolusViewModel(delegate: self)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentRecommendation = 2.5

        viewModel.enteredCarbAmount = "20"

        XCTAssertEqual("2.5", viewModel.recommendedBolus)
        XCTAssertEqual("2.5", viewModel.enteredBolusAmount)

        viewModel.enteredCarbAmount = ""

        XCTAssertEqual("–", viewModel.recommendedBolus)
        XCTAssertEqual("0", viewModel.enteredBolusAmount)
    }

    func testDeleteCurrentGlucoseRemovesRecommendation() {
        let viewModel = SimpleBolusViewModel(delegate: self)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentRecommendation = 3.0

        viewModel.enteredGlucoseAmount = "180"

        XCTAssertEqual("3", viewModel.recommendedBolus)
        XCTAssertEqual("3", viewModel.enteredBolusAmount)

        viewModel.enteredGlucoseAmount = ""

        XCTAssertEqual("–", viewModel.recommendedBolus)
        XCTAssertEqual("0", viewModel.enteredBolusAmount)
    }

    func testDeleteCurrentGlucoseRemovesActiveInsulin() {
        let viewModel = SimpleBolusViewModel(delegate: self)
        viewModel.authenticate = { (description, completion) in
            completion(.success)
        }

        currentIOB = SimpleBolusViewModelTests.someIOB

        viewModel.enteredGlucoseAmount = "180"

        XCTAssertEqual("2.4", viewModel.activeInsulin)

        viewModel.enteredGlucoseAmount = ""

        XCTAssertNil(viewModel.activeInsulin)
    }
}

extension SimpleBolusViewModelTests: SimpleBolusViewModelDelegate {
    func addGlucose(_ samples: [NewGlucoseSample], completion: @escaping (Error?) -> Void) {
        addedGlucose = samples
        completion(nil)
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

    func enactBolus(units: Double, at startDate: Date) {
        enactedBolus = (units: units, startDate: startDate)
    }
    
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        completion(.success(currentIOB))
    }
    
    func computeSimpleBolusRecommendation(at date: Date, mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> BolusDosingDecision? {
        
        var decision = BolusDosingDecision()
        decision.recommendedBolus = BolusRecommendation(amount: currentRecommendation, pendingInsulin: 0, notice: .none)
        decision.insulinOnBoard = currentIOB
        return decision
    }
    
    func storeBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        storedBolusDecision = bolusDosingDecision
    }

    var preferredGlucoseUnit: HKUnit {
        return .milligramsPerDeciliter
    }
    
    var maximumBolus: Double {
        return 3.0
    }
    
    var suspendThreshold: HKQuantity {
        return HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)
    }
    
    
}
