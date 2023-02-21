//
//  BolusActionTests.swift
//  LoopKitTests
//
//  Created by Bill Gestrich on 1/14/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import Loop
import LoopKit

final class BolusActionTests: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }
    
    func testToValidBolusAtMaxAmount_Succeeds() throws {
        
        //Arrange
        let maxBolusAmount = 10.0
        let bolusAmount = maxBolusAmount
        let action = BolusAction(amountInUnits: bolusAmount)
        
        //Act
        let validatedBolusAmount = try action.toValidBolusAmount(maximumBolus: 10.0)
        
        //Assert
        XCTAssertEqual(validatedBolusAmount, bolusAmount)
        
    }
    
    func testToValidBolusAmount_AboveMaxAmount_Fails() throws {
        
        //Arrange
        let maxBolusAmount = 10.0
        let bolusAmount = maxBolusAmount + 0.1
        let action = BolusAction(amountInUnits: bolusAmount)
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidBolusAmount(maximumBolus: maxBolusAmount)
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? BolusActionError, case .exceedsMaxBolus = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    func testToValidBolusAmount_AtZero_Fails() throws {
        
        //Arrange
        let bolusAmount = 0.0
        let action = BolusAction(amountInUnits: bolusAmount)
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidBolusAmount(maximumBolus: 10.0)
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? BolusActionError, case .invalidBolus = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    
    func testToValidBolusAmount_NegativeAmount_Fails() throws {
        
        //Arrange
        let bolusAmount = -1.0
        let action = BolusAction(amountInUnits: bolusAmount)
        
        //Act
        var thrownError: Error? = nil
        do {
            let _ = try action.toValidBolusAmount(maximumBolus: 10.0)
        } catch {
            thrownError = error
        }
        
        //Assert
        guard let validationError = thrownError as? BolusActionError, case .invalidBolus = validationError else {
            XCTFail("Unexpected type \(thrownError.debugDescription)")
            return
        }
    }
    

}
