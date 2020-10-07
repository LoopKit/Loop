//
//  ChartAxisValuesStaticGeneratorTests.swift
//  LoopTests
//
//  Created by Nathaniel Hamming on 2020-09-29.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import SwiftCharts
@testable import LoopUI

class ChartAxisValuesStaticGeneratorTests: XCTestCase {

    private var maxSegmentCount: Double = 4
    private let minSegmentCount: Double = 2
    private let axisValueGenerator: ChartAxisValueStaticGenerator = { ChartAxisValueDouble($0) }
    private let addPaddingSegmentIfEdge: Bool = false
    private let multiple: Double = 40

    func testGenerateYAxisValuesUsingLinearSegmentStep40To400() {
        let pointsAtLimits = [
            ChartPoint(x: ChartAxisValue(scalar: 1), y:  ChartAxisValue(scalar: 40)),
            ChartPoint(x: ChartAxisValue(scalar: 2), y:  ChartAxisValue(scalar: 120)),
            ChartPoint(x: ChartAxisValue(scalar: 3), y:  ChartAxisValue(scalar: 250)),
            ChartPoint(x: ChartAxisValue(scalar: 4), y:  ChartAxisValue(scalar: 400)),
        ]
        var yAxisValues = generateYAxisValuesUsingLinearSegmentStep(chartPoints: pointsAtLimits)
        XCTAssertEqual(yAxisValues[0].scalar, 40)
        XCTAssertEqual(yAxisValues[1].scalar, 160)
        XCTAssertEqual(yAxisValues[2].scalar, 280)
        XCTAssertEqual(yAxisValues[3].scalar, 400)
        
        let pointsNearLimits = [
            ChartPoint(x: ChartAxisValue(scalar: 1), y:  ChartAxisValue(scalar: 41)),
            ChartPoint(x: ChartAxisValue(scalar: 2), y:  ChartAxisValue(scalar: 42)),
            ChartPoint(x: ChartAxisValue(scalar: 3), y:  ChartAxisValue(scalar: 43)),
            ChartPoint(x: ChartAxisValue(scalar: 4), y:  ChartAxisValue(scalar: 397)),
            ChartPoint(x: ChartAxisValue(scalar: 5), y:  ChartAxisValue(scalar: 398)),
            ChartPoint(x: ChartAxisValue(scalar: 6), y:  ChartAxisValue(scalar: 399)),
        ]
        yAxisValues = generateYAxisValuesUsingLinearSegmentStep(chartPoints: pointsNearLimits)
        XCTAssertEqual(yAxisValues[0].scalar, 40)
        XCTAssertEqual(yAxisValues[1].scalar, 160)
        XCTAssertEqual(yAxisValues[2].scalar, 280)
        XCTAssertEqual(yAxisValues[3].scalar, 400)
    }
    
    func testGenerateYAxisValuesUsingLinearSegmentStep40To600() {
        // the max expected value is 600, but the y-axis will go to 680 due to the step size
        let pointsAtLimits = [
            ChartPoint(x: ChartAxisValue(scalar: 1), y:  ChartAxisValue(scalar: 40)),
            ChartPoint(x: ChartAxisValue(scalar: 2), y:  ChartAxisValue(scalar: 120)),
            ChartPoint(x: ChartAxisValue(scalar: 3), y:  ChartAxisValue(scalar: 250)),
            ChartPoint(x: ChartAxisValue(scalar: 4), y:  ChartAxisValue(scalar: 600)),
        ]
        var yAxisValues = generateYAxisValuesUsingLinearSegmentStep(chartPoints: pointsAtLimits)
        XCTAssertEqual(yAxisValues[0].scalar, 40)
        XCTAssertEqual(yAxisValues[1].scalar, 200)
        XCTAssertEqual(yAxisValues[2].scalar, 360)
        XCTAssertEqual(yAxisValues[3].scalar, 520)
        XCTAssertEqual(yAxisValues[4].scalar, 680)
        
        let pointsNearLimits = [
            ChartPoint(x: ChartAxisValue(scalar: 1), y:  ChartAxisValue(scalar: 41)),
            ChartPoint(x: ChartAxisValue(scalar: 2), y:  ChartAxisValue(scalar: 42)),
            ChartPoint(x: ChartAxisValue(scalar: 3), y:  ChartAxisValue(scalar: 43)),
            ChartPoint(x: ChartAxisValue(scalar: 4), y:  ChartAxisValue(scalar: 597)),
            ChartPoint(x: ChartAxisValue(scalar: 5), y:  ChartAxisValue(scalar: 598)),
            ChartPoint(x: ChartAxisValue(scalar: 6), y:  ChartAxisValue(scalar: 599)),
        ]
        yAxisValues = generateYAxisValuesUsingLinearSegmentStep(chartPoints: pointsNearLimits)
        XCTAssertEqual(yAxisValues[0].scalar, 40)
        XCTAssertEqual(yAxisValues[1].scalar, 200)
        XCTAssertEqual(yAxisValues[2].scalar, 360)
        XCTAssertEqual(yAxisValues[3].scalar, 520)
        XCTAssertEqual(yAxisValues[4].scalar, 680)
    }

    func testGenerateYAxisValuesUsingLinearSegmentStep0To400() {
        // when starting at 0, the max segment size is set to 5
        maxSegmentCount = 5

        let pointsAtLimits = [
                ChartPoint(x: ChartAxisValue(scalar: 1), y:  ChartAxisValue(scalar: 0)),
                ChartPoint(x: ChartAxisValue(scalar: 2), y:  ChartAxisValue(scalar: 120)),
                ChartPoint(x: ChartAxisValue(scalar: 3), y:  ChartAxisValue(scalar: 250)),
                ChartPoint(x: ChartAxisValue(scalar: 4), y:  ChartAxisValue(scalar: 400)),
            ]
            var yAxisValues = generateYAxisValuesUsingLinearSegmentStep(chartPoints: pointsAtLimits)
            XCTAssertEqual(yAxisValues[0].scalar, 0)
            XCTAssertEqual(yAxisValues[1].scalar, 80)
            XCTAssertEqual(yAxisValues[2].scalar, 160)
            XCTAssertEqual(yAxisValues[3].scalar, 240)
            XCTAssertEqual(yAxisValues[4].scalar, 320)
            XCTAssertEqual(yAxisValues[5].scalar, 400)
            
            let pointsNearLimits = [
                ChartPoint(x: ChartAxisValue(scalar: 1), y:  ChartAxisValue(scalar: 1)),
                ChartPoint(x: ChartAxisValue(scalar: 2), y:  ChartAxisValue(scalar: 2)),
                ChartPoint(x: ChartAxisValue(scalar: 3), y:  ChartAxisValue(scalar: 3)),
                ChartPoint(x: ChartAxisValue(scalar: 4), y:  ChartAxisValue(scalar: 397)),
                ChartPoint(x: ChartAxisValue(scalar: 5), y:  ChartAxisValue(scalar: 398)),
                ChartPoint(x: ChartAxisValue(scalar: 6), y:  ChartAxisValue(scalar: 399)),
            ]
            yAxisValues = generateYAxisValuesUsingLinearSegmentStep(chartPoints: pointsNearLimits)
            XCTAssertEqual(yAxisValues[0].scalar, 0)
            XCTAssertEqual(yAxisValues[1].scalar, 80)
            XCTAssertEqual(yAxisValues[2].scalar, 160)
            XCTAssertEqual(yAxisValues[3].scalar, 240)
            XCTAssertEqual(yAxisValues[4].scalar, 320)
            XCTAssertEqual(yAxisValues[5].scalar, 400)
    }
    
    func testGenerateYAxisValuesUsingLinearSegmentStep0To680() {
        // when starting at 0, the max segment size is set to 5
        maxSegmentCount = 5
        
        let pointsAtLimits = [
            ChartPoint(x: ChartAxisValue(scalar: 1), y:  ChartAxisValue(scalar: 0)),
            ChartPoint(x: ChartAxisValue(scalar: 2), y:  ChartAxisValue(scalar: 120)),
            ChartPoint(x: ChartAxisValue(scalar: 3), y:  ChartAxisValue(scalar: 250)),
            ChartPoint(x: ChartAxisValue(scalar: 4), y:  ChartAxisValue(scalar: 600)),
        ]
        var yAxisValues = generateYAxisValuesUsingLinearSegmentStep(chartPoints: pointsAtLimits)
        XCTAssertEqual(yAxisValues[0].scalar, 0)
        XCTAssertEqual(yAxisValues[1].scalar, 120)
        XCTAssertEqual(yAxisValues[2].scalar, 240)
        XCTAssertEqual(yAxisValues[3].scalar, 360)
        XCTAssertEqual(yAxisValues[4].scalar, 480)
        XCTAssertEqual(yAxisValues[5].scalar, 600)
        
        let pointsNearLimits = [
            ChartPoint(x: ChartAxisValue(scalar: 1), y:  ChartAxisValue(scalar: 1)),
            ChartPoint(x: ChartAxisValue(scalar: 2), y:  ChartAxisValue(scalar: 2)),
            ChartPoint(x: ChartAxisValue(scalar: 3), y:  ChartAxisValue(scalar: 3)),
            ChartPoint(x: ChartAxisValue(scalar: 4), y:  ChartAxisValue(scalar: 597)),
            ChartPoint(x: ChartAxisValue(scalar: 5), y:  ChartAxisValue(scalar: 598)),
            ChartPoint(x: ChartAxisValue(scalar: 6), y:  ChartAxisValue(scalar: 599)),
        ]
        yAxisValues = generateYAxisValuesUsingLinearSegmentStep(chartPoints: pointsNearLimits)
        XCTAssertEqual(yAxisValues[0].scalar, 0)
        XCTAssertEqual(yAxisValues[1].scalar, 120)
        XCTAssertEqual(yAxisValues[2].scalar, 240)
        XCTAssertEqual(yAxisValues[3].scalar, 360)
        XCTAssertEqual(yAxisValues[4].scalar, 480)
        XCTAssertEqual(yAxisValues[5].scalar, 600)
    }
}

extension ChartAxisValuesStaticGeneratorTests {
    func generateYAxisValuesUsingLinearSegmentStep(chartPoints: [ChartPoint]) -> [ChartAxisValue] {
        return ChartAxisValuesStaticGenerator.generateYAxisValuesUsingLinearSegmentStep(chartPoints: chartPoints,
                                                                                        minSegmentCount: minSegmentCount,
                                                                                        maxSegmentCount: maxSegmentCount,
                                                                                        multiple: multiple,
                                                                                        axisValueGenerator: axisValueGenerator,
                                                                                        addPaddingSegmentIfEdge: addPaddingSegmentIfEdge)
    }
}
