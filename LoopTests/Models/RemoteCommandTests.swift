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
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry":expectedCarbsInGrams,
            "absorption-time": expectedAbsorptionTimeInHours,
            "otp": otp,
            "start-time": expectedStartDateString
        ]
        
        //Act
        let command = try RemoteCommand.createRemoteCommand(notification: notification, allowedPresets: [], defaultAbsorptionTime: TimeInterval(hours: 4.0)).get()
        
        //Assert
        guard case .carbsEntry(let carbEntry) = command else {
            XCTFail("Incorrect case")
            return
        }
        XCTAssertEqual(carbEntry.startDate, expectedDate)
        XCTAssertEqual(carbEntry.absorptionTime, TimeInterval(hours: expectedAbsorptionTimeInHours))
        XCTAssertEqual(carbEntry.quantity, HKQuantity(unit: .gram(), doubleValue: expectedCarbsInGrams))
    }
    
    func testParseCarbEntryNotification_MissingCreatedDate_Succeeds() throws {
        
        //Arrange
        let expectedStartDate = Date()
        let expectedCarbsInGrams = 15.0
        let expectedAbsorptionTimeInHours = 3.0
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry":expectedCarbsInGrams,
            "absorption-time": expectedAbsorptionTimeInHours,
            "otp": otp
        ]
        
        //Act
        let command = try RemoteCommand.createRemoteCommand(notification: notification, allowedPresets: [], defaultAbsorptionTime: TimeInterval(hours: 4.0), nowDate: expectedStartDate).get()
        
        //Assert
        guard case .carbsEntry(let carbEntry) = command else {
            XCTFail("Incorrect case")
            return
        }
        
        XCTAssertEqual(carbEntry.startDate, expectedStartDate)
        XCTAssertEqual(carbEntry.absorptionTime, TimeInterval(hours: expectedAbsorptionTimeInHours))
        XCTAssertEqual(carbEntry.quantity, HKQuantity(unit: .gram(), doubleValue: expectedCarbsInGrams))
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
        XCTAssertThrowsError(try RemoteCommand.createRemoteCommand(notification: notification, allowedPresets: [], defaultAbsorptionTime: TimeInterval(hours: 4.0)).get())
    }
    
    func testParseCarbEntryNotification_MissingAbsorptionHours_UsesDefaultAbsorption() throws {
        
        //Arrange
        let expectedStartDateString = "2022-08-14T03:08:00.000Z"
        let expectedCarbsInGrams = 15.0
        let expectedDate = dateFormatter().date(from: expectedStartDateString)!
        let expectedAbsorptionTimeInHours = 4.0
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry": expectedCarbsInGrams,
            "otp": otp,
            "start-time": expectedStartDateString
        ]

        //Act
        let command = try RemoteCommand.createRemoteCommand(notification: notification, allowedPresets: [], defaultAbsorptionTime: TimeInterval(hours: expectedAbsorptionTimeInHours)).get()
        
        //Assert
        guard case .carbsEntry(let carbEntry) = command else {
            XCTFail("Incorrect case")
            return
        }
        XCTAssertEqual(carbEntry.startDate, expectedDate)
        XCTAssertEqual(carbEntry.absorptionTime, TimeInterval(hours: expectedAbsorptionTimeInHours))
        XCTAssertEqual(carbEntry.quantity, HKQuantity(unit: .gram(), doubleValue: expectedCarbsInGrams))
    }

    
    func testParseCarbEntryNotification_AtMinAbsorptionHours_Succeeds() throws {
        
        //Arrange
        let expectedStartDateString = "2022-08-14T03:08:00.000Z"
        let expectedCarbsInGrams = 15.0
        let expectedDate = dateFormatter().date(from: expectedStartDateString)!
        let expectedAbsorptionTimeInHours = 0.5
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry": expectedCarbsInGrams,
            "absorption-time":expectedAbsorptionTimeInHours,
            "otp": otp,
            "start-time": expectedStartDateString
        ]

        //Act
        let command = try RemoteCommand.createRemoteCommand(notification: notification, allowedPresets: [], defaultAbsorptionTime: TimeInterval(hours: 4.0)).get()
        
        //Assert
        guard case .carbsEntry(let carbEntry) = command else {
            XCTFail("Incorrect case")
            return
        }
        XCTAssertEqual(carbEntry.startDate, expectedDate)
        XCTAssertEqual(carbEntry.absorptionTime, TimeInterval(hours: expectedAbsorptionTimeInHours))
        XCTAssertEqual(carbEntry.quantity, HKQuantity(unit: .gram(), doubleValue: expectedCarbsInGrams))
    }
    
    func testParseCarbEntryNotification_BelowMinAbsorptionHours_Fails() throws {
        
        //Arrange
        let expectedStartDateString = "2022-08-14T03:08:00.000Z"
        let expectedCarbsInGrams = 15.0
        let expectedAbsorptionTimeInHours = 0.4
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry": expectedCarbsInGrams,
            "absorption-time":expectedAbsorptionTimeInHours,
            "otp": otp,
            "start-time": expectedStartDateString
        ]
        
        //Act + Assert
        XCTAssertThrowsError(try RemoteCommand.createRemoteCommand(notification: notification, allowedPresets: [], defaultAbsorptionTime: TimeInterval(hours: 4.0)).get())
    }
    
    func testParseCarbEntryNotification_AtMaxAbsorptionHours_Succeeds() throws {
        
        //Arrange
        let expectedStartDateString = "2022-08-14T03:08:00.000Z"
        let expectedCarbsInGrams = 15.0
        let expectedDate = dateFormatter().date(from: expectedStartDateString)!
        let expectedAbsorptionTimeInHours = 8.0
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry": expectedCarbsInGrams,
            "absorption-time":expectedAbsorptionTimeInHours,
            "otp": otp,
            "start-time": expectedStartDateString
        ]

        //Act
        let command = try RemoteCommand.createRemoteCommand(notification: notification, allowedPresets: [], defaultAbsorptionTime: TimeInterval(hours: 4.0)).get()
        
        //Assert
        guard case .carbsEntry(let carbEntry) = command else {
            XCTFail("Incorrect case")
            return
        }
        XCTAssertEqual(carbEntry.startDate, expectedDate)
        XCTAssertEqual(carbEntry.absorptionTime, TimeInterval(hours: expectedAbsorptionTimeInHours))
        XCTAssertEqual(carbEntry.quantity, HKQuantity(unit: .gram(), doubleValue: expectedCarbsInGrams))
    }
    
    func testParseCarbEntryNotification_AboveMaxAbsorptionHours_Fails() throws {
        
        //Arrange
        let expectedStartDateString = "2022-08-14T03:08:00.000Z"
        let expectedCarbsInGrams = 15.0
        let expectedAbsorptionTimeInHours = 8.1
        let otp = 12345
        let notification: [String: Any] = [
            "carbs-entry": expectedCarbsInGrams,
            "absorption-time":expectedAbsorptionTimeInHours,
            "otp": otp,
            "start-time": expectedStartDateString
        ]
        
        //Act + Assert
        XCTAssertThrowsError(try RemoteCommand.createRemoteCommand(notification: notification, allowedPresets: [], defaultAbsorptionTime: TimeInterval(hours: 4.0)).get())
    }
    
    
    //MARK: Utils
    
    func dateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions =  [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

}
