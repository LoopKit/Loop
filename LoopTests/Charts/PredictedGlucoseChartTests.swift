//
//  PredictedGlucoseChartTests.swift
//  LoopTests
//
//  Created by Nathaniel Hamming on 2020-09-29.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
import SwiftCharts
@testable import LoopUI

class PredictedGlucoseChartTests: XCTestCase {

    private let yAxisStepSizeMGDL: Double = 40
    
    func testClampingPredictedGlucoseValues40To400() {
        let glucoseValues = [
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 40), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 120), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 250), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 400), startDate: Date())
        ]
        let predictedGlucoseValues =  [
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 40), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 280), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 380), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 400), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 480), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 580), startDate: Date())
        ]
        let predictedGlucoseChart = PredictedGlucoseChart(predictedGlucoseBounds: .default,
                                                          yAxisStepSizeMGDLOverride: yAxisStepSizeMGDL)
        predictedGlucoseChart.setGlucoseValues(glucoseValues)
        predictedGlucoseChart.setPredictedGlucoseValues(predictedGlucoseValues)
        let predictedGlucosePoints = predictedGlucoseChart.predictedGlucosePoints
        XCTAssertEqual(predictedGlucosePoints[0].y.scalar, 40)
        XCTAssertEqual(predictedGlucosePoints[1].y.scalar, 40)
        XCTAssertEqual(predictedGlucosePoints[2].y.scalar, 280)
        XCTAssertEqual(predictedGlucosePoints[3].y.scalar, 380)
        XCTAssertEqual(predictedGlucosePoints[4].y.scalar, 400)
        XCTAssertEqual(predictedGlucosePoints[5].y.scalar, 400)
        XCTAssertEqual(predictedGlucosePoints[6].y.scalar, 400)
    }

    func testClampingPredictedGlucoseValues40To600() {
        // the max expected value is 600, but the y-axis will go to 680 due to the step size
        let glucoseValues = [
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 40), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 120), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 350), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 480), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 600), startDate: Date())
        ]
        let predictedGlucoseValues =  [
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 40), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 300), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 450), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 600), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 750), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 1000), startDate: Date())
        ]
        let predictedGlucoseChart = PredictedGlucoseChart(predictedGlucoseBounds: .default,
                                                          yAxisStepSizeMGDLOverride: yAxisStepSizeMGDL)
        predictedGlucoseChart.setGlucoseValues(glucoseValues)
        predictedGlucoseChart.setPredictedGlucoseValues(predictedGlucoseValues)
        let predictedGlucosePoints = predictedGlucoseChart.predictedGlucosePoints
        XCTAssertEqual(predictedGlucosePoints[0].y.scalar, 40)
        XCTAssertEqual(predictedGlucosePoints[1].y.scalar, 40)
        XCTAssertEqual(predictedGlucosePoints[2].y.scalar, 300)
        XCTAssertEqual(predictedGlucosePoints[3].y.scalar, 450)
        XCTAssertEqual(predictedGlucosePoints[4].y.scalar, 600)
        XCTAssertEqual(predictedGlucosePoints[5].y.scalar, 680)
        XCTAssertEqual(predictedGlucosePoints[6].y.scalar, 680)
    }

    func testClampingPredictedGlucoseValues0To400() {
        let glucoseValues = [
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 120), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 250), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 400), startDate: Date())
        ]
        let predictedGlucoseValues =  [
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: -100), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 100), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 380), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 400), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 480), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 580), startDate: Date())
        ]
        let predictedGlucoseChart = PredictedGlucoseChart(predictedGlucoseBounds: .default,
                                                          yAxisStepSizeMGDLOverride: yAxisStepSizeMGDL)
        predictedGlucoseChart.setGlucoseValues(glucoseValues)
        predictedGlucoseChart.setPredictedGlucoseValues(predictedGlucoseValues)
        let predictedGlucosePoints = predictedGlucoseChart.predictedGlucosePoints
        XCTAssertEqual(predictedGlucosePoints[0].y.scalar, 0)
        XCTAssertEqual(predictedGlucosePoints[1].y.scalar, 0)
        XCTAssertEqual(predictedGlucosePoints[2].y.scalar, 100)
        XCTAssertEqual(predictedGlucosePoints[3].y.scalar, 380)
        XCTAssertEqual(predictedGlucosePoints[4].y.scalar, 400)
        XCTAssertEqual(predictedGlucosePoints[5].y.scalar, 400)
        XCTAssertEqual(predictedGlucosePoints[6].y.scalar, 400)
    }
    
    func testClampingPredictedGlucoseValues0To600() {
        let glucoseValues = [
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 120), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 350), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 480), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 600), startDate: Date())
        ]
        let predictedGlucoseValues =  [
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: -100), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 150), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 350), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 600), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 750), startDate: Date()),
            GlucoseValueTestable(quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 1000), startDate: Date())
        ]
        let predictedGlucoseChart = PredictedGlucoseChart(predictedGlucoseBounds: .default,
                                                          yAxisStepSizeMGDLOverride: yAxisStepSizeMGDL)
        predictedGlucoseChart.setGlucoseValues(glucoseValues)
        predictedGlucoseChart.setPredictedGlucoseValues(predictedGlucoseValues)
        let predictedGlucosePoints = predictedGlucoseChart.predictedGlucosePoints
        XCTAssertEqual(predictedGlucosePoints[0].y.scalar, 0)
        XCTAssertEqual(predictedGlucosePoints[1].y.scalar, 0)
        XCTAssertEqual(predictedGlucosePoints[2].y.scalar, 150)
        XCTAssertEqual(predictedGlucosePoints[3].y.scalar, 350)
        XCTAssertEqual(predictedGlucosePoints[4].y.scalar, 600)
        XCTAssertEqual(predictedGlucosePoints[5].y.scalar, 600)
        XCTAssertEqual(predictedGlucosePoints[6].y.scalar, 600)
    }
}

struct GlucoseValueTestable: GlucoseValue {
    var quantity: HKQuantity
    
    var startDate: Date
}
