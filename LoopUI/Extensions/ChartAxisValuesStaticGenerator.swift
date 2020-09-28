//
//  ChartAxisValuesStaticGenerator.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-09-08.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftCharts

extension ChartAxisValuesStaticGenerator {
    // This is the same as SwiftChart ChartAxisValuesStaticGenerator.generateAxisValuesWithChartPoints(...) with the exception that the `currentMultiple` is calculated linearly instead of quadratically
    static func generateYAxisValuesUsingLinearSegmentStep(chartPoints: [ChartPoint],
                                                          minSegmentCount: Double,
                                                          maxSegmentCount: Double,
                                                          multiple: Double,
                                                          axisValueGenerator: ChartAxisValueStaticGenerator,
                                                          addPaddingSegmentIfEdge: Bool) -> [ChartAxisValue]
    {
        precondition(multiple > 0, "Invalid multiple: \(multiple)")
        
        let sortedChartPoints = chartPoints.sorted {(obj1, obj2) in
            return obj1.y.scalar < obj2.y.scalar
        }
        
        if let firstChartPoint = sortedChartPoints.first, let lastChartPoint = sortedChartPoints.last {
            let first = firstChartPoint.y.scalar
            let lastPar = lastChartPoint.y.scalar
            
            guard lastPar >=~ first else {fatalError("Invalid range generating axis values")}
            
            let last = lastPar =~ first ? lastPar + 1 : lastPar
            
            /// The first axis value will be less than or equal to the first scalar value, aligned with the desired multiple
            var firstValue = first - (first.truncatingRemainder(dividingBy: multiple))
            /// The last axis value will be greater than or equal to the last scalar value, aligned with the desired multiple
            let remainder = last.truncatingRemainder(dividingBy: multiple)
            var lastValue = remainder == 0 ? last : last + (multiple - remainder)
            var segmentSize = multiple
            
            /// If there should be a padding segment added when a scalar value falls on the first or last axis value, adjust the first and last axis values
            if firstValue =~ first && addPaddingSegmentIfEdge {
                firstValue = firstValue - segmentSize
            }
            if lastValue =~ last && addPaddingSegmentIfEdge {
                lastValue = lastValue + segmentSize
            }
            
            let distance = lastValue - firstValue
            var currentMultiple = multiple
            var segmentCount = distance / currentMultiple
            
            /// Find the optimal number of segments and segment width
            
            /// If the number of segments is greater than desired, make each segment wider
            while segmentCount > maxSegmentCount {
                // This is the only difference from SwiftCharts (i.e., currentMultiple *= 2)
                currentMultiple += multiple
                segmentCount = distance / currentMultiple
            }
            segmentCount = ceil(segmentCount)
            
            /// Increase the number of segments until there are enough as desired
            while segmentCount < minSegmentCount {
                segmentCount += 1
            }
            segmentSize = currentMultiple
            
            /// Generate axis values from the first value, segment size and number of segments
            let offset = firstValue
            return (0...Int(segmentCount)).map {segment in
                let scalar = offset + (Double(segment) * segmentSize)
                return axisValueGenerator(scalar)
            }
        } else {
            print("Trying to generate Y axis without datapoints, returning empty array")
            return []
        }
    }
}

fileprivate func =~ (a: Double, b: Double) -> Bool {
    return fabs(a - b) < Double.ulpOfOne
}

fileprivate func >=~ (a: Double, b: Double) -> Bool {
    return a =~ b || a > b
}
