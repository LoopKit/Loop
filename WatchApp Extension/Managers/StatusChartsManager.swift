//
//  StatusChartsManager.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/16/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import CoreGraphics
import UIKit
import HealthKit

class StatusChartsManager {
    var unit: HKUnit?
    var targetRanges: [WatchDatedRangeContext]?
    var temporaryOverride: WatchDatedRangeContext?
    var historicalGlucose: [HKQuantitySample]?
    var predictedGlucose: [WatchGlucoseContext]?

    func glucoseChart() -> UIImage? {
        guard let unit = unit, let historicalGlucose = historicalGlucose, historicalGlucose.count > 0 else {
            return nil
        }

        // Choose the min/max values from across all of our data sources
        var sampleValues = historicalGlucose.map { $0.quantity.doubleValue(for: unit) }
        sampleValues += predictedGlucose?.map { $0.value } ?? []
        sampleValues += targetRanges?.map { [$0.maxValue, $0.minValue] }.flatMap { $0 } ?? []
        if let temporaryOverride = temporaryOverride {
            sampleValues += [temporaryOverride.maxValue, temporaryOverride.minValue]
        }
        let bgMax = CGFloat(sampleValues.max()!) * 1.1
        let bgMin = CGFloat(sampleValues.min()!) * 0.75

        let glucoseChartSize = CGSize(width: 270, height: 152)
        let xMax = glucoseChartSize.width
        let yMax = glucoseChartSize.height
        let timeNow = CGFloat(Date().timeIntervalSince1970)

        let dateMax = predictedGlucose?.last?.startDate ?? Date().addingTimeInterval(TimeInterval(minutes: 180))
        let dateMin = historicalGlucose.first?.startDate ?? Date().addingTimeInterval(TimeInterval(minutes: -180))
        let timeMax = CGFloat(dateMax.timeIntervalSince1970)
        let timeMin = CGFloat(dateMin.timeIntervalSince1970)
        let yScale = yMax/(bgMax - bgMin)
        let xScale = xMax/(timeMax - timeMin)
        let xNow: CGFloat = xScale * (timeNow - timeMin)
        let pointSize: CGFloat = 4
        // When we draw points, they are drawn in a rectangle specified
        // by its corner coords, so often need to shift by half a point:
        let halfPoint = pointSize / 2

        var x: CGFloat = 0.0
        var y: CGFloat = 0.0

        let pointColor = UIColor(red:158/255, green:215/255, blue:245/255, alpha:1)
        // Target and override are the same, but with different alpha:
        let rangeColor = UIColor(red:158/255, green:215/255, blue:245/255, alpha:0.4)
        let overrideColor = UIColor(red:158/255, green:215/255, blue:245/255, alpha:0.6)
        // Different color for main range(s) when override is active
        let rangeOverridenColor = UIColor(red:158/255, green:215/255, blue:245/255, alpha:0.2)
        let highColor = UIColor(red:158/255, green:158/255, blue:24/255, alpha:1)
        let lowColor = UIColor(red:158/255, green:58/255, blue:24/255, alpha:1)


        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs = [NSAttributedStringKey.font: UIFont(name: "HelveticaNeue", size: 20)!, NSAttributedStringKey.paragraphStyle: paragraphStyle,
                     NSAttributedStringKey.foregroundColor: UIColor.white]

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .none

        let bgMaxLabel = numberFormatter.string(from: NSNumber(value: Double(bgMax)))!
        let bgMinLabel = numberFormatter.string(from: NSNumber(value: Double(bgMin)))!

        UIGraphicsBeginImageContext(glucoseChartSize)
        let imContext = UIGraphicsGetCurrentContext()!

        UIColor.darkGray.setStroke()
        // Mark the current time with a dashed line:
        imContext.setLineDash(phase: 1, lengths: [6, 6])
        imContext.setLineWidth(3)
        imContext.strokeLineSegments(between: [CGPoint(x: xNow, y: 0), CGPoint(x: xNow, y: yMax - 1)])
        // Clear the dash pattern:
        imContext.setLineDash(phase: 0, lengths:[])

        // Set color for glucose points and target range:
        pointColor.setFill()

        //  Plot target ranges:
        if let chartTargetRanges = targetRanges {
            rangeColor.setFill()

            // Check for overrides first, since we will color the main
            // range(s) differently depending on active override:

            // Override of target ranges.  Overrides that have
            // expired already can still show up here, so we need
            // to check and only show if they are active:
            if let override = temporaryOverride, override.endDate > Date() {
                overrideColor.setFill()

                // Top left corner is start date and max value:
                // Might be off the graph so keep it in:
                var targetStart = CGFloat(override.startDate.timeIntervalSince1970)
                // Only show the part of the override that is in the future:
                if  targetStart < timeNow {
                    targetStart = timeNow
                }
                var targetEnd = CGFloat(override.endDate.timeIntervalSince1970)
                if  targetEnd > timeMax {
                    targetEnd = timeMax
                }
                x = xScale * (targetStart - timeMin)
                // Don't let end go off the chart:
                let xEnd = xScale * (targetEnd - timeMin)
                let rangeWidth = xEnd - x
                y = yScale * (bgMax - CGFloat(override.maxValue))
                // Make sure range is at least a couple of pixels high:
                let rangeHeight = max(yScale * (bgMax - CGFloat(override.minValue)) - y , 3)

                imContext.fill(CGRect(x: x, y: y, width: rangeWidth, height: rangeHeight))
                // To mimic the Loop interface, add a second box
                // after this that reverts to original target color:
                if targetEnd < timeMax {
                    rangeColor.setFill()
                    imContext.fill(CGRect(x: x+rangeWidth, y: y, width: xMax - (x+rangeWidth), height: rangeHeight))
                }
                // Set a lighter color for main range(s) to follow:
                rangeOverridenColor.setFill()
            }

            // chartTargetRanges may be an array, so need to
            // iterate over it and possibly plot a target change if needed:

            for targetRange in chartTargetRanges {
                // Top left corner is start date and max value:
                // Might be off the graph so keep it in:
                var targetStart = CGFloat(targetRange.startDate.timeIntervalSince1970)
                if  targetStart < timeMin {
                    targetStart = timeMin
                }
                var targetEnd = CGFloat(targetRange.endDate.timeIntervalSince1970)
                if  targetEnd > timeMax {
                    targetEnd = timeMax
                }
                x = xScale * (targetStart - timeMin)
                // Don't let end go off the chart:
                let xEnd = xScale * (targetEnd - timeMin)
                let rangeWidth = xEnd - x
                y = yScale * (bgMax - CGFloat(targetRange.maxValue))
                // Make sure range is at least a couple of pixels high:
                let rangeHeight = max(yScale * (bgMax - CGFloat(targetRange.minValue)) - y , 3)

                imContext.fill(CGRect(x: x, y: y, width: rangeWidth, height: rangeHeight))
            }

        }

        pointColor.setFill()

        // Draw the glucose points:
        historicalGlucose.forEach { sample in
            let bgFloat = CGFloat(sample.quantity.doubleValue(for: unit))
            x = xScale * (CGFloat(sample.startDate.timeIntervalSince1970) - timeMin)
            y = yScale * (bgMax - bgFloat)
            if bgFloat > bgMax {
                // 'high' on graph is low y coords:
                y = halfPoint
                highColor.setFill()
            } else if bgFloat < bgMin {
                y = yMax - 2
                lowColor.setFill()
            } else {
                pointColor.setFill()
            }
            // Start by half a point width back to make
            // rectangle centered on where we want point center:
            imContext.fillEllipse(in: CGRect(x: x - halfPoint, y: y - halfPoint, width: pointSize, height: pointSize))
        }

        pointColor.setStroke()
        imContext.setLineDash(phase: 11, lengths: [10, 6])
        imContext.setLineWidth(3)
        // Create a path with the predicted glucose values:
        imContext.beginPath()
        var predictedPoints: [CGPoint] = []

        if let predictedGlucose = predictedGlucose, predictedGlucose.count > 2 {
            predictedGlucose.forEach { (sample) in
                let bgFloat = CGFloat(sample.value)
                x = xScale * (CGFloat(sample.startDate.timeIntervalSince1970) - timeMin)
                y = yScale * (bgMax - bgFloat)
                predictedPoints.append(CGPoint(x: x, y: y))
            }

            // Add points to the path, then draw it:
            imContext.addLines(between: predictedPoints)
            imContext.strokePath()
        }
        // Clear the dash pattern:
        imContext.setLineDash(phase: 0, lengths:[])

        // Put labels last so they are on top of text or points
        // in case of overlap.
        // Add a label for max BG on y axis
        bgMaxLabel.draw(with: CGRect(x: 6, y: 4, width: 40, height: 40), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        // Add a label for min BG on y axis
        bgMinLabel.draw(with: CGRect(x: 6, y: yMax-28, width: 40, height: 40), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)

        let timeLabel = "+\(Int(dateMax.timeIntervalSinceNow.hours))h"
        timeLabel.draw(with: CGRect(x: xMax - 50, y: 4, width: 40, height: 40), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)

        // Draw the box
        UIColor.darkGray.setStroke()
        imContext.stroke(CGRect(origin: CGPoint(x: 0, y: 0), size: glucoseChartSize))

        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
