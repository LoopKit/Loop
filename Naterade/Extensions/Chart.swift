//
//  Chart.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import GlucoseKit
import HealthKit
import LoopKit
import SwiftCharts


extension Chart {
    static func chartWithGlucoseData(data: [GlucoseValue], targets: GlucoseRangeSchedule?, inFrame frame: CGRect) -> Chart? {
        guard data.count > 0 else {
            return nil
        }

        let timeFormatter = NSDateFormatter()
        timeFormatter.dateFormat = "h a"

        // The actual data points
        let points = data.map({
            return ChartPoint(
                x: ChartAxisValueDate(date: $0.startDate, formatter: timeFormatter),
                y: ChartAxisValueDouble($0.quantity.doubleValueForUnit(HKUnit.milligramsPerDeciliterUnit()))
            )
        })

        let axisLabelSettings = ChartLabelSettings(font: UIFont.preferredFontForTextStyle(UIFontTextStyleCaption1), fontColor: UIColor.blackColor())

        // The axes, derived from the glucose data
        let xAxisValues = ChartAxisValuesGenerator.generateXAxisValuesWithChartPoints(points, minSegmentCount: 5, maxSegmentCount: 10, multiple: NSTimeInterval(hours: 1), axisValueGenerator: { ChartAxisValueDate(date: ChartAxisValueDate.dateFromScalar($0), formatter: timeFormatter, labelSettings: axisLabelSettings)
            }, addPaddingSegmentIfEdge: true)
        xAxisValues.first?.hidden = true
        xAxisValues.last?.hidden = true

        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(points, minSegmentCount: 3, maxSegmentCount: 8, multiple: 50, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: axisLabelSettings) }, addPaddingSegmentIfEdge: true)

        let xAxisModel = ChartAxisModel(axisValues: xAxisValues)
        let yAxisModel = ChartAxisModel(axisValues: yAxisValues)

        // The chart display settings
        let chartSettings = ChartSettings()
        chartSettings.top = 8
        chartSettings.trailing = 8

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)
        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The glucose targets
        var targetLayer: ChartPointsAreaLayer? = nil

        if let targets = targets {
            let targetPoints: [ChartPoint] = ChartPoint.pointsForGlucoseRangeSchedule(targets, onAxisValues: xAxisValues, dateFormatter: timeFormatter)

            targetLayer = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: targetPoints, areaColor: UIColor.glucoseTintColor.colorWithAlphaComponent(0.3), animDuration: 0, animDelay: 0, addContainerPoints: false)
        }

        // TODO: Add a line tracker layer

        // The glucose values
        let circles = ChartPointsScatterCirclesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: points, displayDelay: 1, itemSize: CGSize(width: 4, height: 4), itemFillColor: UIColor.glucoseTintColor)

        let layers: [ChartLayer?] = [
            targetLayer,
            xAxis,
            yAxis,
            circles
        ]

        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }
}