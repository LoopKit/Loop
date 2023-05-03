//
//  CarbActionTests.swift
//  LoopTests
//
//  Created by Bill Gestrich on 1/14/23.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
@testable import Loop
import LoopKit

class CarbActionTests: XCTestCase {
    
    override func setUpWithError() throws {
    }
    
    override func tearDownWithError() throws {
    }

    
    func testToValidCarbEntry_Succeeds() throws {
        
        //Arrange
        let expectedCarbsInGrams = 15.0
        let expectedDate = Date()
        let expectedAbsorptionTime = TimeInterval(hours: 4.0)
        let foodType = "🍕"
        
        let action = CarbAction(amountInGrams: expectedCarbsInGrams, absorptionTime: expectedAbsorptionTime, foodType: foodType, startDate: expectedDate)
        
        //Act
        let carbEntry = try action.toValidCarbEntry(defaultAbsorptionTime: TimeInterval(hours: 3.0),
                                                    minAbsorptionTime: TimeInterval(hours: 0.5),
                                                    maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                    maxCarbEntryQuantity: expectedCarbsInGrams,
                                                    maxCarbEntryPastTime: .hours(-12),
                                                    maxCarbEntryFutureTime: .hours(1)
        )
        
        //Assert
        XCTAssertEqual(carbEntry.startDate, expectedDate)
        XCTAssertEqual(carbEntry.absorptionTime, expectedAbsorptionTime)
        XCTAssertEqual(carbEntry.quantity, HKQuantity(unit: .gram(), doubleValue: expectedCarbsInGrams))
        XCTAssertEqual(carbEntry.foodType, foodType)
    }
    
    func testToValidCarbEntry_MissingAbsorptionHours_UsesDefaultAbsorption() throws {
        
        //Arrange
        let defaultAbsorptionTime = TimeInterval(hours: 4.0)
        let action = CarbAction(amountInGrams: 15.0, startDate: Date())
        
        //Act
        let carbEntry = try action.toValidCarbEntry(defaultAbsorptionTime: defaultAbsorptionTime,
                                                    minAbsorptionTime: TimeInterval(hours: 0.5),
                                                    maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                    maxCarbEntryQuantity: 200,
                                                    maxCarbEntryPastTime: .hours(-12),
                                                    maxCarbEntryFutureTime: .hours(1))
        
        //Assert
        XCTAssertEqual(carbEntry.absorptionTime, defaultAbsorptionTime)
    }
    
    func testToValidCarbEntry_AtMinAbsorptionHours_Succeeds() throws {
        
        //Arrange
        let minAbsorptionTime = TimeInterval(hours: 0.5)
        let action = CarbAction(amountInGrams: 15.0,
                                      absorptionTime: minAbsorptionTime,
                                      startDate: Date())
        
        //Act
        let carbEntry = try action.toValidCarbEntry(defaultAbsorptionTime: minAbsorptionTime,
                                                    minAbsorptionTime: minAbsorptionTime,
                                                    maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                    maxCarbEntryQuantity: 200,
                                                    maxCarbEntryPastTime: .hours(-12),
                                                    maxCarbEntryFutureTime: .hours(1))
        
        //Assert
        XCTAssertEqual(carbEntry.absorptionTime, minAbsorptionTime)
    }
    
    func testToValidCarbEntry_BelowMinAbsorptionHours_Fails() throws {
        
        //Arrange
        let minAbsorptionTime = TimeInterval(hours: 0.5)
        let aborptionOverrideTime = TimeInterval(hours: 0.4)
        let action = CarbAction(amountInGrams: 15.0,
                                      absorptionTime: aborptionOverrideTime,
                                      startDate: Date())
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidCarbEntry(defaultAbsorptionTime: minAbsorptionTime,
                                                minAbsorptionTime: minAbsorptionTime,
                                                maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                maxCarbEntryQuantity: 200,
                                                maxCarbEntryPastTime: .hours(-12),
                                                maxCarbEntryFutureTime: .hours(1)
            )
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? CarbActionError, case .invalidAbsorptionTime = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    func testToValidCarbEntry_AtMaxAbsorptionHours_Succeeds() throws {
        
        //Arrange
        let maxAbsorptionTime = TimeInterval(hours: 5.0)
        let action = CarbAction(amountInGrams: 15.0,
                                      absorptionTime: maxAbsorptionTime,
                                      startDate: Date())
        
        //Act
        let carbEntry = try action.toValidCarbEntry(defaultAbsorptionTime: maxAbsorptionTime,
                                                    minAbsorptionTime: TimeInterval(hours: 0.5),
                                                    maxAbsorptionTime: maxAbsorptionTime,
                                                    maxCarbEntryQuantity: 200,
                                                    maxCarbEntryPastTime: .hours(-12),
                                                    maxCarbEntryFutureTime: .hours(1)
        )
        
        //Assert
        XCTAssertEqual(carbEntry.absorptionTime, maxAbsorptionTime)
    }
    
    func testToValidCarbEntry_AboveMaxAbsorptionHours_Fails() throws {
        
        //Arrange
        let maxAbsorptionTime = TimeInterval(hours: 5.0)
        let absorptionTime = TimeInterval(hours: 5.1)
        let action = CarbAction(amountInGrams: 15.0,
                                      absorptionTime: absorptionTime,
                                      startDate: Date())
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidCarbEntry(defaultAbsorptionTime: maxAbsorptionTime,
                                                minAbsorptionTime: TimeInterval(hours: 0.5),
                                                maxAbsorptionTime: maxAbsorptionTime,
                                                maxCarbEntryQuantity: 200,
                                                maxCarbEntryPastTime: .hours(-12),
                                                maxCarbEntryFutureTime: .hours(1)
            )
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? CarbActionError, case .invalidAbsorptionTime = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    func testToValidCarbEntry_AtMinStartTime_Succeeds() throws {
        
        //Arrange
        let maxCarbEntryPastTime = TimeInterval(hours: -12)
        let nowDate = Date()
        let startDate = nowDate.addingTimeInterval(maxCarbEntryPastTime)
        let action = CarbAction(amountInGrams: 15.0,
                                      absorptionTime: TimeInterval(hours: 5.0),
                                      startDate: startDate)
        
        //Act
        let carbEntry = try action.toValidCarbEntry(defaultAbsorptionTime: TimeInterval(hours: 3.0),
                                                    minAbsorptionTime: TimeInterval(hours: 0.5),
                                                    maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                    maxCarbEntryQuantity: 200,
                                                    maxCarbEntryPastTime: maxCarbEntryPastTime,
                                                    maxCarbEntryFutureTime: .hours(1),
                                                    nowDate: nowDate
        )
        
        //Assert
        XCTAssertEqual(carbEntry.startDate, startDate)
    }
    
    func testToValidCarbEntry_BeforeMinStartTime_Fails() throws {
        
        //Arrange
        let maxCarbEntryPastTime = TimeInterval(hours: -12)
        let nowDate = Date()
        let startDate = nowDate.addingTimeInterval(maxCarbEntryPastTime - 1)
        let action = CarbAction(amountInGrams: 15.0,
                                      absorptionTime: TimeInterval(hours: 5.0),
                                      startDate: startDate)
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidCarbEntry(defaultAbsorptionTime: TimeInterval(hours: 3.0),
                                                minAbsorptionTime: TimeInterval(hours: 0.5),
                                                maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                maxCarbEntryQuantity: 200,
                                                maxCarbEntryPastTime: maxCarbEntryPastTime,
                                                maxCarbEntryFutureTime: .hours(1)
            )
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? CarbActionError, case .invalidStartDate = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    func testToValidCarbEntry_AtMaxStartTime_Succeeds() throws {
        
        //Arrange
        let maxCarbEntryFutureTime = TimeInterval(hours: 1)
        let nowDate = Date()
        let startDate = nowDate.addingTimeInterval(maxCarbEntryFutureTime)
        let action = CarbAction(amountInGrams: 15.0,
                                      absorptionTime: TimeInterval(hours: 5.0),
                                      startDate: startDate)
        
        //Act
        let carbEntry = try action.toValidCarbEntry(defaultAbsorptionTime: TimeInterval(hours: 3.0),
                                                    minAbsorptionTime: TimeInterval(hours: 0.5),
                                                    maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                    maxCarbEntryQuantity: 200,
                                                    maxCarbEntryPastTime: .hours(-12),
                                                    maxCarbEntryFutureTime: maxCarbEntryFutureTime,
                                                    nowDate: nowDate
        )
        
        //Assert
        XCTAssertEqual(carbEntry.startDate, startDate)
    }
    
    func testToValidCarbEntry_AfterMaxStartTime_Fails() throws {
        
        //Arrange
        let maxCarbEntryFutureTime = TimeInterval(hours: 1)
        let nowDate = Date()
        let startDate = nowDate.addingTimeInterval(maxCarbEntryFutureTime + 1)
        let action = CarbAction(amountInGrams: 15.0,
                                      absorptionTime: TimeInterval(hours: 5.0),
                                      startDate: startDate)
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidCarbEntry(defaultAbsorptionTime: TimeInterval(hours: 3.0),
                                                minAbsorptionTime: TimeInterval(hours: 0.5),
                                                maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                maxCarbEntryQuantity: 200,
                                                maxCarbEntryPastTime: .hours(-12),
                                                maxCarbEntryFutureTime: maxCarbEntryFutureTime
            )
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? CarbActionError, case .invalidStartDate = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    func testToValidCarbEntry_AtMaxCarbs_Succeeds() throws {
        
        let maxCarbsAmount = 200.0
        let carbsAmount = maxCarbsAmount
        
        //Arrange
        let action = CarbAction(amountInGrams: carbsAmount,
                                      absorptionTime: TimeInterval(hours: 5.0),
                                      startDate: Date())
        
        //Act
        let carbEntry = try action.toValidCarbEntry(defaultAbsorptionTime: TimeInterval(hours: 3.0),
                                                    minAbsorptionTime: TimeInterval(hours: 0.5),
                                                    maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                    maxCarbEntryQuantity: maxCarbsAmount,
                                                    maxCarbEntryPastTime: .hours(-12),
                                                    maxCarbEntryFutureTime: TimeInterval(hours: 1)
        )
        
        //Assert
        XCTAssertEqual(carbEntry.quantity, HKQuantity(unit: .gram(), doubleValue: carbsAmount))
    }
    
    func testToValidCarbEntry_AboveMaxCarbs_Fails() throws {
        
        let maxCarbsAmount = 200.0
        let carbsAmount = maxCarbsAmount + 1
        
        //Arrange
        let action = CarbAction(amountInGrams: carbsAmount,
                                      absorptionTime: TimeInterval(hours: 5.0),
                                      startDate: Date())
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidCarbEntry(defaultAbsorptionTime: TimeInterval(hours: 3.0),
                                                minAbsorptionTime: TimeInterval(hours: 0.5),
                                                maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                maxCarbEntryQuantity: 200,
                                                maxCarbEntryPastTime: .hours(-12),
                                                maxCarbEntryFutureTime: .hours(1.0)
            )
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? CarbActionError, case .exceedsMaxCarbs = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    func testToValidCarbEntry_NegativeCarbs_Fails() throws {
        
        let carbsAmount = -1.0
        
        //Arrange
        let action = CarbAction(amountInGrams: carbsAmount,
                                      absorptionTime: TimeInterval(hours: 5.0),
                                      startDate: Date())
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidCarbEntry(defaultAbsorptionTime: TimeInterval(hours: 3.0),
                                                minAbsorptionTime: TimeInterval(hours: 0.5),
                                                maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                maxCarbEntryQuantity: 200,
                                                maxCarbEntryPastTime: .hours(-12),
                                                maxCarbEntryFutureTime: .hours(1.0)
            )
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? CarbActionError, case .invalidCarbs = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    func testToValidCarbEntry_ZeroCarbs_Fails() throws {
        
        let carbsAmount = 0.0
        
        //Arrange
        let action = CarbAction(amountInGrams: carbsAmount,
                                      absorptionTime: TimeInterval(hours: 5.0),
                                      startDate: Date())
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidCarbEntry(defaultAbsorptionTime: TimeInterval(hours: 3.0),
                                                minAbsorptionTime: TimeInterval(hours: 0.5),
                                                maxAbsorptionTime: TimeInterval(hours: 5.0),
                                                maxCarbEntryQuantity: 200,
                                                maxCarbEntryPastTime: .hours(-12),
                                                maxCarbEntryFutureTime: .hours(1.0)
            )
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? CarbActionError, case .invalidCarbs = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
}


//MARK: Utils

func dateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions =  [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}

