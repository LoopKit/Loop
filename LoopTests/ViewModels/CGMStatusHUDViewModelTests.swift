//
//  CGMStatusHUDViewModelTests.swift
//  LoopTests
//
//  Created by Nathaniel Hamming on 2020-09-21.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
@testable import LoopUI

class CGMStatusHUDViewModelTests: XCTestCase {

    private var viewModel: CGMStatusHUDViewModel!
    private var staleGlucoseValueHandlerWasCalled = false
    private var testExpect: XCTestExpectation!
    
    override func setUpWithError() throws {
        viewModel = CGMStatusHUDViewModel(staleGlucoseValueHandler: staleGlucoseValueHandler)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testInitialization() throws {
        XCTAssertEqual(CGMStatusHUDViewModel.staleGlucoseRepresentation, "---")
        XCTAssertNil(viewModel.trend)
        XCTAssertEqual(viewModel.unitsString, "–")
        XCTAssertEqual(viewModel.glucoseValueString, "---")
        XCTAssertTrue(viewModel.accessibilityString.isEmpty)
        XCTAssertEqual(viewModel.glucoseValueTintColor, .label)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, .glucoseTintColor)
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        XCTAssertNil(viewModel.statusHighlight)
    }

    func testSetGlucoseQuantityCGM() {
        let glucoseDisplay = TestGlucoseDisplay(isStateValid: true,
                                                trendType: .down,
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        let glucoseStartDate = Date()
        let staleGlucoseAge: TimeInterval = .minutes(15)
        viewModel.setGlucoseQuantity(90,
                                     at: glucoseStartDate,
                                     unit: .milligramsPerDeciliter,
                                     staleGlucoseAge: staleGlucoseAge,
                                     glucoseDisplay: glucoseDisplay,
                                     isManualGlucose: false)
        
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.glucoseValueString, "90")
        XCTAssertEqual(viewModel.trend, .down)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, glucoseDisplay.glucoseRangeCategory?.trendColor)
        XCTAssertEqual(viewModel.glucoseValueTintColor, glucoseDisplay.glucoseRangeCategory?.glucoseColor)
        XCTAssertEqual(viewModel.unitsString, HKUnit.milligramsPerDeciliter.localizedShortUnitString)
    }
    
    func testSetGlucoseQuantityCGMStale() {
        let glucoseDisplay = TestGlucoseDisplay(isStateValid: true,
                                                trendType: .down,
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        let glucoseStartDate = Date()
        let staleGlucoseAge: TimeInterval = .minutes(-1)
        viewModel.setGlucoseQuantity(90,
                                     at: glucoseStartDate,
                                     unit: .milligramsPerDeciliter,
                                     staleGlucoseAge: staleGlucoseAge,
                                     glucoseDisplay: glucoseDisplay,
                                     isManualGlucose: false)
        
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.glucoseValueString, "---")
        XCTAssertNil(viewModel.trend)
        XCTAssertNotEqual(viewModel.glucoseTrendTintColor, glucoseDisplay.glucoseRangeCategory?.trendColor)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, .glucoseTintColor)
        XCTAssertNotEqual(viewModel.glucoseValueTintColor, glucoseDisplay.glucoseRangeCategory?.glucoseColor)
        XCTAssertEqual(viewModel.glucoseValueTintColor, .label)
        XCTAssertEqual(viewModel.unitsString, HKUnit.milligramsPerDeciliter.localizedShortUnitString)
    }
    
    func testSetGlucoseQuantityCGMStaleDelayed() {
        testExpect = self.expectation(description: #function)
        let glucoseDisplay = TestGlucoseDisplay(isStateValid: true,
                                                trendType: .down,
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        let glucoseStartDate = Date()
        let staleGlucoseAge: TimeInterval = .seconds(0.01)
        viewModel.setGlucoseQuantity(90,
                                     at: glucoseStartDate,
                                     unit: .milligramsPerDeciliter,
                                     staleGlucoseAge: staleGlucoseAge,
                                     glucoseDisplay: glucoseDisplay,
                                     isManualGlucose: false)
        wait(for: [testExpect], timeout: 1.0)
        XCTAssertTrue(staleGlucoseValueHandlerWasCalled)
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.glucoseValueString, "---")
        XCTAssertNil(viewModel.trend)
        XCTAssertNotEqual(viewModel.glucoseTrendTintColor, glucoseDisplay.glucoseRangeCategory?.trendColor)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, .glucoseTintColor)
        XCTAssertNotEqual(viewModel.glucoseValueTintColor, glucoseDisplay.glucoseRangeCategory?.glucoseColor)
        XCTAssertEqual(viewModel.glucoseValueTintColor, .label)
        XCTAssertEqual(viewModel.unitsString, HKUnit.milligramsPerDeciliter.localizedShortUnitString)
    }
    
    func testSetGlucoseQuantityManualGlucose() {
        let glucoseDisplay = TestGlucoseDisplay(isStateValid: true,
                                                trendType: .down,
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        let glucoseStartDate = Date()
        let staleGlucoseAge: TimeInterval = .minutes(15)
        viewModel.setGlucoseQuantity(90,
                                     at: glucoseStartDate,
                                     unit: .milligramsPerDeciliter,
                                     staleGlucoseAge: staleGlucoseAge,
                                     glucoseDisplay: glucoseDisplay,
                                     isManualGlucose: true)
        
        XCTAssertEqual(viewModel.manualGlucoseTrendIconOverride, UIImage(systemName: "questionmark.circle"))
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.glucoseValueString, "90")
        XCTAssertNil(viewModel.trend)
        XCTAssertNotEqual(viewModel.glucoseTrendTintColor, glucoseDisplay.glucoseRangeCategory?.trendColor)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, .glucoseTintColor)
        XCTAssertEqual(viewModel.glucoseValueTintColor, glucoseDisplay.glucoseRangeCategory?.glucoseColor)
        XCTAssertEqual(viewModel.unitsString, HKUnit.milligramsPerDeciliter.localizedShortUnitString)
    }
    
    func testSetManualGlucoseIconOverride() {
        let statusHighlight1 = TestStatusHighlight(localizedMessage: "Test 1",
                                                   imageName: "plus.circle",
                                                   state: .normalCGM)
        
        let statusHighlight2 = TestStatusHighlight(localizedMessage: "Test 2",
                                                   imageName: "exclamationmark.circle",
                                                   state: .critical)
        
        // set status highlight
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        viewModel.statusHighlight = statusHighlight1
        XCTAssertEqual(viewModel.statusHighlight as! TestStatusHighlight, statusHighlight1)
        
        // ensure status highlight icon is set to the manual glucose override icon
        // when there is a manual glucose override icon, the status highlight isn't returned to be presented
        viewModel.setManualGlucoseTrendIconOverride()
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.manualGlucoseTrendIconOverride, statusHighlight1.image)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, statusHighlight1.color)

        // ensure updating the status highlight icon also updates the manual glucose override icon
        viewModel.statusHighlight = statusHighlight2
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.manualGlucoseTrendIconOverride, statusHighlight2.image)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, statusHighlight2.color)
    }

}

extension CGMStatusHUDViewModelTests {
    func staleGlucoseValueHandler() {
        self.staleGlucoseValueHandlerWasCalled = true
        testExpect.fulfill()
    }
    
    struct TestStatusHighlight: DeviceStatusHighlight, Equatable {
        var localizedMessage: String
        
        var imageName: String
        
        var state: DeviceStatusHighlightState
    }
    
    struct TestGlucoseDisplay: GlucoseDisplayable {
        var isStateValid: Bool
        
        var trendType: GlucoseTrend?
        
        var isLocal: Bool
        
        var glucoseRangeCategory: GlucoseRangeCategory?
    }
}
