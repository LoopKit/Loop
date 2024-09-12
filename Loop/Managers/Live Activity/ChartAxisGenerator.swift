//
//  ChartAxisGenerator.swift
//  Loop
//
//  Created by Bastiaan Verhaar on 12/09/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import SwiftCharts
import UIKit

struct ChartAxisGenerator {
    private static let yAxisStepSizeMGDLOverride: Double? = FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil
    private static let range = FeatureFlags.predictedGlucoseChartClampEnabled ? LoopConstants.glucoseChartDefaultDisplayBoundClamped : LoopConstants.glucoseChartDefaultDisplayBound
    private static let predictedGlucoseSoftBoundsMinimum = FeatureFlags.predictedGlucoseChartClampEnabled ? HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 40) : nil
    
    private static let minSegmentCount: Double = 2
    private static let addPaddingSegmentIfEdge = false
    private static let axisLabelSettings = ChartLabelSettings(font: .systemFont(ofSize: 14), fontColor: UIColor.secondaryLabel)
    
    // This logic is copied/ported from generateYAxisValuesUsingLinearSegmentStep
    static func getYAxis(points: [Double], isMmol: Bool) -> [Double] {
        let unit: HKUnit = isMmol ? .millimolesPerLiter : .milligramsPerDeciliter

        let glucoseDisplayRange = [
            range.lowerBound.doubleValue(for: unit),
            range.upperBound.doubleValue(for: unit)
        ]
        
        let actualPoints = points + glucoseDisplayRange
        let sortedChartPoints = points.sorted {(obj1, obj2) in
            return obj1 < obj2
        }
        
        guard let first = sortedChartPoints.first, let lastPar = sortedChartPoints.last else {
            print("Trying to generate Y axis without datapoints, returning empty array")
            return []
        }
        
        let maxSegmentCount: Double = glucoseValueBelowSoftBoundsMinimum(first, unit) ? 5 : 4
        
        guard lastPar >=~ first else {fatalError("Invalid range generating axis values")}
        let multiple: Double = !isMmol ? (yAxisStepSizeMGDLOverride ?? 25) : 1
        
        let last = needsToAddOne(lastPar, first) ? lastPar + 1 : lastPar
        
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
        
        // do not allow the first label to be displayed as -0
        while firstValue < 0 && firstValue.rounded() == -0 {
            firstValue = firstValue - segmentSize
        }
        
        if lastValue =~ last && addPaddingSegmentIfEdge {
            lastValue = lastValue + segmentSize
        }
        
        let distance = lastValue - firstValue
        var currentMultiple = multiple
        var segmentCount = distance / currentMultiple
        var potentialSegmentValues = stride(from: firstValue, to: lastValue, by: currentMultiple)

        /// Find the optimal number of segments and segment width
        /// If the number of segments is greater than desired, make each segment wider
        /// ensure no label of -0 will be displayed on the axis
        while segmentCount > maxSegmentCount ||
            !potentialSegmentValues.filter({ $0 < 0 && $0.rounded() == -0 }).isEmpty
        {
            currentMultiple += multiple
            segmentCount = distance / currentMultiple
            potentialSegmentValues = stride(from: firstValue, to: lastValue, by: currentMultiple)
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
            var scalar = offset + (Double(segment) * segmentSize)
            // a value that could be displayed as 0 should truly be 0 to have the zero-line drawn correctly.
            if scalar != 0,
                scalar.rounded() == 0
            {
                scalar = 0
            }
            return ChartAxisValueDouble(scalar, labelSettings: axisLabelSettings).scalar
        }
    }
    
    private static func needsToAddOne(_ a: Double, _ b: Double) -> Bool {
        return fabs(a - b) < Double.ulpOfOne
    }
    
    private static func glucoseValueBelowSoftBoundsMinimum(_ glucoseMinimum: Double, _ unit: HKUnit) -> Bool {
        guard let predictedGlucoseSoftBoundsMinimum = predictedGlucoseSoftBoundsMinimum else
        {
            return false
        }
            
        return HKQuantity(unit: unit, doubleValue: glucoseMinimum) < predictedGlucoseSoftBoundsMinimum
    }
}

fileprivate extension Double {
    static func >=~ (a: Double, b: Double) -> Bool {
        return a =~ b || a > b
    }
}
