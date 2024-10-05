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
    
    override func setUpWithError() throws {
        viewModel = CGMStatusHUDViewModel()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testInitialization() throws {
        XCTAssertEqual(CGMStatusHUDViewModel.staleGlucoseRepresentation, "– – –")
        XCTAssertNil(viewModel.trend)
        XCTAssertEqual(viewModel.unitsString, "–")
        XCTAssertEqual(viewModel.glucoseValueString, "– – –")
        XCTAssertTrue(viewModel.accessibilityString.isEmpty)
        XCTAssertEqual(viewModel.glucoseValueTintColor, .label)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, .glucoseTintColor)
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        XCTAssertNil(viewModel.statusHighlight)
    }

    func testSetGlucoseQuantityCGM() {
        let glucoseDisplay = TestGlucoseDisplay(isStateValid: true,
                                                trendType: .down,
                                                trendRate: HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: -1.0),
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        let glucoseStartDate = Date()
        viewModel.setGlucoseQuantity(90,
                                     at: glucoseStartDate,
                                     unit: .milligramsPerDeciliter,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: false,
                                     isDisplayOnly: false,
                                     isGlucoseValueStale: false)
        
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
                                                trendRate: HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: -1.0),
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        let glucoseStartDate = Date()
        viewModel.setGlucoseQuantity(90,
                                     at: glucoseStartDate,
                                     unit: .milligramsPerDeciliter,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: false,
                                     isDisplayOnly: false,
                                     isGlucoseValueStale: true)

        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.glucoseValueString, "– – –")
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
                                                trendRate: HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: -1.0),
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        let glucoseStartDate = Date()
        viewModel.setGlucoseQuantity(90,
                                     at: glucoseStartDate,
                                     unit: .milligramsPerDeciliter,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: true,
                                     isDisplayOnly: false,
                                     isGlucoseValueStale: false)

        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.glucoseValueString, "90")
        XCTAssertNil(viewModel.trend)
        XCTAssertNotEqual(viewModel.glucoseTrendTintColor, glucoseDisplay.glucoseRangeCategory?.trendColor)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, .glucoseTintColor)
        XCTAssertEqual(viewModel.glucoseValueTintColor, glucoseDisplay.glucoseRangeCategory?.glucoseColor)
        XCTAssertEqual(viewModel.unitsString, HKUnit.milligramsPerDeciliter.localizedShortUnitString)
    }
    
    func testSetGlucoseQuantityCalibrationDoesNotShow() {
        let glucoseDisplay = TestGlucoseDisplay(isStateValid: true,
                                                trendType: .down,
                                                trendRate: HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: -1.0),
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        let glucoseStartDate = Date()
        viewModel.setGlucoseQuantity(90,
                                     at: glucoseStartDate,
                                     unit: .milligramsPerDeciliter,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: true,
                                     isDisplayOnly: true,
                                     isGlucoseValueStale: false)

        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        XCTAssertEqual(viewModel.glucoseValueString, "90")
        XCTAssertEqual(viewModel.trend, .down)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, glucoseDisplay.glucoseRangeCategory?.trendColor)
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
        let glucoseDisplay = TestGlucoseDisplay(isStateValid: true,
                                                trendType: .down,
                                                trendRate: HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: -1.0),
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        let glucoseStartDate = Date()
        viewModel.setGlucoseQuantity(90,
                                     at: glucoseStartDate,
                                     unit: .milligramsPerDeciliter,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: true,
                                     isDisplayOnly: false,
                                     isGlucoseValueStale: false)

        XCTAssertEqual(viewModel.glucoseValueString, "90")
        XCTAssertNil(viewModel.trend)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.manualGlucoseTrendIconOverride, statusHighlight1.image)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, statusHighlight1.state.color)

        // ensure updating the status highlight icon also updates the manual glucose override icon
        viewModel.statusHighlight = statusHighlight2
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.glucoseValueString, "90")
        XCTAssertNil(viewModel.trend)
        XCTAssertEqual(viewModel.manualGlucoseTrendIconOverride, statusHighlight2.image)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, statusHighlight2.state.color)
    }

    func testManualGlucoseOverridesStatusHighlight() {
        // add manual glucose
        let glucoseDisplay = TestGlucoseDisplay(isStateValid: true,
                                                trendType: .down,
                                                trendRate: HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: -1.0),
                                                isLocal: true,
                                                glucoseRangeCategory: .urgentLow)
        viewModel.setGlucoseQuantity(90,
                                     at: Date(),
                                     unit: .milligramsPerDeciliter,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: true,
                                     isDisplayOnly: false,
                                     isGlucoseValueStale: false)

        // check that manual glucose is displayed
        XCTAssertEqual(viewModel.glucoseValueString, "90")
        XCTAssertNil(viewModel.trend)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, .glucoseTintColor)

        // add status highlight
        let statusHighlight1 = TestStatusHighlight(localizedMessage: "Test 1",
                                                   imageName: "plus.circle",
                                                   state: .normalCGM)
        viewModel.statusHighlight = statusHighlight1

        // check that manual glucose is still displayed (this time with status highlight icon)
        XCTAssertEqual(viewModel.glucoseValueString, "90")
        XCTAssertNil(viewModel.trend)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.manualGlucoseTrendIconOverride, statusHighlight1.image)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, statusHighlight1.state.color)

        // add CGM glucose
        viewModel.setGlucoseQuantity(95,
                                     at: Date(),
                                     unit: .milligramsPerDeciliter,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: false,
                                     isDisplayOnly: false,
                                     isGlucoseValueStale: false)

        // check that status highlight is displayed
        XCTAssertEqual(viewModel.glucoseValueString, "95")
        XCTAssertEqual(viewModel.trend, .down)
        XCTAssertEqual(viewModel.statusHighlight as! TestStatusHighlight, statusHighlight1)
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)

        // remove status highlight
        viewModel.statusHighlight = nil

        // check that CGM glucose is displayed
        XCTAssertEqual(viewModel.glucoseValueString, "95")
        XCTAssertEqual(viewModel.trend, .down)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)

        // add status highlight
        let statusHighlight2 = TestStatusHighlight(localizedMessage: "Test 2",
                                                   imageName: "exclamationmark.circle",
                                                   state: .critical)
        viewModel.statusHighlight = statusHighlight2

        // check that status highlight is displayed
        XCTAssertEqual(viewModel.glucoseValueString, "95")
        XCTAssertEqual(viewModel.trend, .down)
        XCTAssertEqual(viewModel.statusHighlight as! TestStatusHighlight, statusHighlight2)
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)

        // add manual glucose
        viewModel.setGlucoseQuantity(100,
                                     at: Date(),
                                     unit: .milligramsPerDeciliter,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: true,
                                     isDisplayOnly: false,
                                     isGlucoseValueStale: false)

        // check that manual glucose is still displayed (again with status highlight icon)
        XCTAssertEqual(viewModel.glucoseValueString, "100")
        XCTAssertNil(viewModel.trend)
        XCTAssertNil(viewModel.statusHighlight)
        XCTAssertEqual(viewModel.manualGlucoseTrendIconOverride, statusHighlight2.image)
        XCTAssertEqual(viewModel.glucoseTrendTintColor, statusHighlight2.state.color)

        // add stale manual glucose
        viewModel.setGlucoseQuantity(100,
                                     at: Date(),
                                     unit: .milligramsPerDeciliter,
                                     glucoseDisplay: glucoseDisplay,
                                     wasUserEntered: true,
                                     isDisplayOnly: false,
                                     isGlucoseValueStale: true)

        // check that the status highlight is displayed
        XCTAssertEqual(viewModel.statusHighlight as! TestStatusHighlight, statusHighlight2)
        XCTAssertNil(viewModel.manualGlucoseTrendIconOverride)
    }
}

extension CGMStatusHUDViewModelTests {
    struct TestStatusHighlight: DeviceStatusHighlight, Equatable {
        var localizedMessage: String
        
        var imageName: String
        
        var state: DeviceStatusHighlightState
    }
    
    struct TestGlucoseDisplay: GlucoseDisplayable {
        var isStateValid: Bool
        
        var trendType: GlucoseTrend?

        var trendRate: HKQuantity?
        
        var isLocal: Bool
        
        var glucoseRangeCategory: GlucoseRangeCategory?
    }
}
