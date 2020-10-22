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
@testable import Loop

class SimpleBolusViewModelTests: XCTestCase {
    
    enum MockError: Error {
        case authentication
    }
    
    var addedGlucose: [NewGlucoseSample] = []
    var addedCarbEntry: NewCarbEntry?
    var enactedBolus: (units: Double, startDate: Date)?
    var currentIOB: InsulinValue = SimpleBolusViewModelTests.noIOB
    var currentRecommendation: Double = 0

    static var noIOB = InsulinValue(startDate: Date(), value: 0)
    static var someIOB = InsulinValue(startDate: Date(), value: 24)

    
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

    }
}

extension SimpleBolusViewModelTests: SimpleBolusViewModelDelegate {
    func addGlucose(_ samples: [NewGlucoseSample], completion: @escaping (Error?) -> Void) {
        addedGlucose = samples
        completion(nil)
    }
    
    func addCarbEntry(_ carbEntry: NewCarbEntry, completion: @escaping (Error?) -> Void) {
        addedCarbEntry = carbEntry
        completion(nil)
    }
    
    func enactBolus(units: Double, at startDate: Date) {
        enactedBolus = (units: units, startDate: startDate)
    }
    
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        completion(.success(currentIOB))
    }
    
    func computeSimpleBolusRecommendation(mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> HKQuantity? {
        return HKQuantity(unit: .internationalUnit(), doubleValue: currentRecommendation)
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
