//
//  OverrideActionTests.swift
//  LoopKitTests
//
//  Created by Bill Gestrich on 1/14/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import Loop
import LoopKit

final class OverrideActionTests: XCTestCase {

    override func setUpWithError() throws {

    }

    override func tearDownWithError() throws {

    }
    
    func testToValidOverride_Succeeds() throws {
        
        //Arrange
        let durationTime = TimeInterval(hours: 1.0)
        let remoteAddress = "1234-54321"
        let overrideName = "My-Override"
        let action = OverrideAction(name: overrideName, durationTime: durationTime, remoteAddress: remoteAddress)
        let presets = [TemporaryScheduleOverridePreset(symbol: "", name: overrideName, settings: .init(targetRange: .none), duration: .indefinite)]

        //Act
        let validOverride = try action.toValidOverride(allowedPresets: presets)
        
        //Assert
        XCTAssertEqual(validOverride.duration, .finite(durationTime))
        switch validOverride.enactTrigger {
        case .remote(let triggerAddress):
            XCTAssertEqual(triggerAddress, remoteAddress)
        default:
            XCTFail("Unexpected trigger trigger type")
        }
    }

    func testToValidOverride_WhenOverrideNotInPresets_Fails() throws {
        
        //Arrange
        let action = OverrideAction(name: "Unknown-Override", durationTime: TimeInterval(hours: 1.0), remoteAddress: "1234-54321")
        let presets = [TemporaryScheduleOverridePreset(symbol: "", name: "My-Override", settings: .init(targetRange: .none), duration: .indefinite)]
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidOverride(allowedPresets: presets)
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? OverrideActionError, case .unknownPreset = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    func testToValidOverride_WhenNoDuration_YieldsIndefiniteOverride() throws {
        
        //Arrange
        let action = OverrideAction(name: "My-Override", durationTime: nil, remoteAddress: "1234-54321")
        let presets = [TemporaryScheduleOverridePreset(symbol: "", name: "My-Override", settings: .init(targetRange: .none), duration: .indefinite)]

        //Act
        let validOverride = try action.toValidOverride(allowedPresets: presets)
        
        //Assert
        XCTAssertEqual(validOverride.duration, .indefinite)
    }
    
    func testToValidOverride_WhenDurationZero_YieldsIndefiniteOverride() throws {
        
        //Arrange
        let action = OverrideAction(name: "My-Override", durationTime: TimeInterval(hours: 0), remoteAddress: "1234-54321")
        let presets = [TemporaryScheduleOverridePreset(symbol: "", name: "My-Override", settings: .init(targetRange: .none), duration: .indefinite)]

        //Act
        let validOverride = try action.toValidOverride(allowedPresets: presets)
        
        //Assert
        XCTAssertEqual(validOverride.duration, .indefinite)
    }
    
    func testToValidOverride_WhenNegativeDuration_Fails() throws {
        
        //Arrange
        let action = OverrideAction(name: "My-Override", durationTime: TimeInterval(hours: -1.0), remoteAddress: "1234-54321")
        let presets = [TemporaryScheduleOverridePreset(symbol: "", name: "My-Override", settings: .init(targetRange: .none), duration: .indefinite)]
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidOverride(allowedPresets: presets)
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? OverrideActionError, case .negativeDuration = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    //Limit to 24 hour duration
    
    func testToValidOverride_WhenAtMaxDuration_Succeeds() throws {
        
        //Arrange
        let duration = TimeInterval(hours: 24)
        let action = OverrideAction(name: "My-Override", durationTime: duration, remoteAddress: "1234-54321")
        let presets = [TemporaryScheduleOverridePreset(symbol: "", name: "My-Override", settings: .init(targetRange: .none), duration: .indefinite)]
        
        //Act
        let validOverride = try action.toValidOverride(allowedPresets: presets)
        
        //Assert
        XCTAssertEqual(validOverride.duration, .finite(duration))

    }
    
    func testToValidOverride_WhenAtMaxDuration_Fails() throws {
        
        //Arrange
        let duration = TimeInterval(hours: 24) + 1
        let action = OverrideAction(name: "My-Override", durationTime: duration, remoteAddress: "1234-54321")
        let presets = [TemporaryScheduleOverridePreset(symbol: "", name: "My-Override", settings: .init(targetRange: .none), duration: .indefinite)]
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidOverride(allowedPresets: presets)
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? OverrideActionError, case .durationExceedsMax = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }

}
