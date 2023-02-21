//
//  RemoteCommandTests.swift
//  LoopTests
//
//  Created by Bill Gestrich on 8/13/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
@testable import Loop
import LoopKit

class RemoteCommandTests: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }
    
    
    //MARK: Carb Entry Command
    
    func testParseCarbEntryNotification_ValidPayload_Succeeds() throws {
        
        //Arrange
        let expectedStartDateString = "2022-08-14T03:08:00.000Z"
        let expectedCarbsInGrams = 15.0
        let expectedDate = dateFormatter().date(from: expectedStartDateString)!
        let expectedAbsorptionTimeInHours = 3.0
        let expectedFoodType = "🍕"
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry":expectedCarbsInGrams,
            "absorption-time": expectedAbsorptionTimeInHours,
            "food-type": expectedFoodType,
            "otp": otp,
            "start-time": expectedStartDateString
        ]
        
        //Act
        let action = try RemoteCommand.createRemoteAction(notification: notification).get()
        
        //Assert
        guard case .carbsEntry(let carbEntry) = action else {
            XCTFail("Incorrect case")
            return
        }
        XCTAssertEqual(carbEntry.startDate, expectedDate)
        XCTAssertEqual(carbEntry.absorptionTime, TimeInterval(hours: expectedAbsorptionTimeInHours))
        XCTAssertEqual(carbEntry.amountInGrams, expectedCarbsInGrams)
        XCTAssertEqual(expectedFoodType, carbEntry.foodType)
    }
    
    func testParseCarbEntryNotification_MissingCreatedDate_Succeeds() throws {
        
        //Arrange
        let expectedCarbsInGrams = 15.0
        let expectedAbsorptionTimeInHours = 3.0
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry":expectedCarbsInGrams,
            "absorption-time": expectedAbsorptionTimeInHours,
            "otp": otp
        ]
        
        //Act
        let action = try RemoteCommand.createRemoteAction(notification: notification).get()
        
        //Assert
        guard case .carbsEntry(let carbEntry) = action else {
            XCTFail("Incorrect case")
            return
        }
        
        XCTAssertEqual(carbEntry.startDate, nil)
        XCTAssertEqual(carbEntry.absorptionTime, TimeInterval(hours: expectedAbsorptionTimeInHours))
        XCTAssertEqual(carbEntry.amountInGrams, expectedCarbsInGrams)
    }
    
    func testParseCarbEntryNotification_InvalidCreatedDate_Fails() throws {
        
        //Arrange
        let expectedCarbsInGrams = 15.0
        let expectedAbsorptionTimeInHours = 3.0
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry": expectedCarbsInGrams,
            "absorption-time":expectedAbsorptionTimeInHours,
            "otp": otp,
            "start-time": "invalid-date-string"
        ]
        
        //Act + Assert
        XCTAssertThrowsError(try RemoteCommand.createRemoteAction(notification: notification).get())
    }
    
    
    //MARK: Utils
    
    func dateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions =  [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

}
