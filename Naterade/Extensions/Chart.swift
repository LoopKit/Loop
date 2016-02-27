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
    static func generateXAxisValuesWithChartPoints(points: [ChartPoint]) -> [ChartAxisValue] {
        guard points.count > 1 else {
            return []
        }

        let timeFormatter = NSDateFormatter()
        timeFormatter.dateFormat = "h a"

        let axisLabelSettings = ChartLabelSettings(font: UIFont.preferredFontForTextStyle(UIFontTextStyleCaption1), fontColor: UIColor.secondaryLabelColor)

        let xAxisValues = ChartAxisValuesGenerator.generateXAxisValuesWithChartPoints(points, minSegmentCount: 5, maxSegmentCount: 10, multiple: NSTimeInterval(hours: 1), axisValueGenerator: { ChartAxisValueDate(date: ChartAxisValueDate.dateFromScalar($0), formatter: timeFormatter, labelSettings: axisLabelSettings)
            }, addPaddingSegmentIfEdge: true)
        xAxisValues.first?.hidden = true
        xAxisValues.last?.hidden = true

        return xAxisValues
    }

    static func chartWithGlucosePoints(points: [ChartPoint], xAxisValues: [ChartAxisValue], targets: GlucoseRangeSchedule?, frame: CGRect, gestureRecognizer: UIPanGestureRecognizer? = nil) -> Chart? {
        guard points.count > 1 && xAxisValues.count > 0 else {
            return nil
        }

        let axisLabelSettings = ChartLabelSettings(font: UIFont.preferredFontForTextStyle(UIFontTextStyleCaption1), fontColor: UIColor.secondaryLabelColor)

        // TODO: The segment/multiple values are unit-specific
        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(points, minSegmentCount: 2, maxSegmentCount: 4, multiple: 25, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: axisLabelSettings) }, addPaddingSegmentIfEdge: true)

        let xAxisModel = ChartAxisModel(axisValues: xAxisValues, lineColor: UIColor.clearColor())
        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: UIColor.clearColor())

        // The chart display settings. We do two passes of the coords calculation to sit the y-axis labels inside the inner space.
        let chartSettings = ChartSettings()
        chartSettings.top = 12
        chartSettings.trailing = 8

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The glucose targets
        var targetLayer: ChartPointsAreaLayer? = nil

        if let targets = targets {
            let targetPoints: [ChartPoint] = ChartPoint.pointsForGlucoseRangeSchedule(targets, xAxisValues: xAxisValues, yAxisValues: yAxisValues)

            targetLayer = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: targetPoints, areaColor: UIColor.glucoseTintColor.colorWithAlphaComponent(0.3), animDuration: 0, animDelay: 0, addContainerPoints: false)
        }

        // Grid lines

        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .XAndY, settings: ChartGuideLinesLayerSettings(linesColor: UIColor.gridColor), onlyVisibleX: true, onlyVisibleY: false)

        // The glucose values
        let circles = ChartPointsScatterCirclesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: points, displayDelay: 1, itemSize: CGSize(width: 4, height: 4), itemFillColor: UIColor.glucoseTintColor)

        let highlightLayer = ChartPointsTouchHighlightLayer(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: points,
            gestureRecognizer: gestureRecognizer,
            modelFilter: { (screenLoc, chartPointModels) -> ChartPointLayerModel<ChartPoint>? in
                if let index = chartPointModels.map({ $0.screenLoc.x }).findClosestElementIndexToValue(screenLoc.x) {
                    return chartPointModels[index]
                } else {
                    return nil
                }
            },
            viewGenerator: { (chartPointModel, layer, chart) -> UIView? in
                let view = ChartPointEllipseView(center: chartPointModel.screenLoc, diameter: 16)
                view.fillColor = UIColor.glucoseTintColor.colorWithAlphaComponent(0.5)

                return view
            }
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            targetLayer,
            xAxis,
            yAxis,
            highlightLayer,
            circles
        ]

        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }

    static func chartWithIOBPoints(points: [ChartPoint], xAxisValues: [ChartAxisValue], frame: CGRect, gestureRecognizer: UIPanGestureRecognizer? = nil) -> Chart? {
        guard points.count > 1 && xAxisValues.count > 0 else {
            return nil
        }

        let axisLabelSettings = ChartLabelSettings(font: UIFont.preferredFontForTextStyle(UIFontTextStyleCaption1), fontColor: UIColor.secondaryLabelColor)

        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(points, minSegmentCount: 2, maxSegmentCount: 4, multiple: 0.25, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: axisLabelSettings) }, addPaddingSegmentIfEdge: false)

        let xAxisModel = ChartAxisModel(axisValues: xAxisValues, lineColor: UIColor.clearColor())
        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: UIColor.clearColor())

        // The chart display settings. We do two passes of the coords calculation to sit the y-axis labels inside the inner space.
        let chartSettings = ChartSettings()
        chartSettings.top = 12
        chartSettings.trailing = 8

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The IOB area
        let iobLayer = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: points, areaColor: UIColor.IOBTintColor, animDuration: 0, animDelay: 0, addContainerPoints: true)

        // Grid lines

        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .XAndY, settings: ChartGuideLinesLayerSettings(linesColor: UIColor.gridColor), onlyVisibleX: true, onlyVisibleY: false)

        let highlightLayer = ChartPointsTouchHighlightLayer(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: points,
            gestureRecognizer: gestureRecognizer,
            modelFilter: { (screenLoc, chartPointModels) -> ChartPointLayerModel<ChartPoint>? in
                if let index = chartPointModels.map({ $0.screenLoc.x }).findClosestElementIndexToValue(screenLoc.x) {
                    return chartPointModels[index]
                } else {
                    return nil
                }
            },
            viewGenerator: { (chartPointModel, layer, chart) -> UIView? in
                let view = ChartPointEllipseView(center: chartPointModel.screenLoc, diameter: 16)
                view.fillColor = UIColor.IOBTintColor.colorWithAlphaComponent(0.5)

                return view
            }
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxis,
            yAxis,
            iobLayer,
            highlightLayer
        ]
        
        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }
}