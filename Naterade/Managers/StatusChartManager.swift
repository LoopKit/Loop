//
//  Chart.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

import CarbKit
import GlucoseKit
import HealthKit
import InsulinKit
import LoopKit
import SwiftCharts


class StatusChartsManager {

    // MARK: - Configuration

    private lazy var chartSettings: ChartSettings = {
        let chartSettings = ChartSettings()
        chartSettings.top = 12
        chartSettings.trailing = 8
        chartSettings.labelsWidthY = 25

        return chartSettings
    }()

    private lazy var dateFormatter: NSDateFormatter = {
        let timeFormatter = NSDateFormatter()
        timeFormatter.dateFormat = "h a"

        return timeFormatter
    }()

    private lazy var axisLineColor = UIColor.clearColor()

    private lazy var axisLabelSettings = ChartLabelSettings(font: UIFont.preferredFontForTextStyle(UIFontTextStyleCaption1), fontColor: UIColor.secondaryLabelColor)

    private lazy var guideLinesLayerSettings = ChartGuideLinesLayerSettings(linesColor: UIColor.gridColor)

    var panGestureRecognizer: UIPanGestureRecognizer?

    // MARK: - Data

    var startDate = NSDate()

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    var glucoseValues: [GlucoseValue] = [] {
        didSet {
            glucosePoints = self.glucoseValues.map({
                return ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDouble($0.quantity.doubleValueForUnit(HKUnit.milligramsPerDeciliterUnit()))
                )
            })
        }
    }

    var IOBValues: [InsulinValue] = [] {
        didSet {
            IOBPoints = self.IOBValues.map {
                return ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDouble($0.value)
                )
            }
        }
    }

    var doseEntries: [DoseEntry] = [] {
        didSet {
            
        }
    }

    var COBValues: [CarbValue] = [] {
        didSet {

        }
    }

    // MARK: - State

    private var glucosePoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
            xAxisValues = nil
        }
    }

    private var IOBPoints: [ChartPoint] = [] {
        didSet {
            IOBChart = nil
            xAxisValues = nil
        }
    }

    private var xAxisValues: [ChartAxisValue]? {
        didSet {
            if let xAxisValues = xAxisValues {
                xAxisModel = ChartAxisModel(axisValues: xAxisValues, lineColor: axisLineColor)
            } else {
                xAxisModel = nil
            }
        }
    }

    private var xAxisModel: ChartAxisModel?

    private var glucoseChart: Chart?

    private var IOBChart: Chart?

    // MARK: - Generators

    func glucoseChartWithFrame(frame: CGRect) -> Chart? {
        if let chart = glucoseChart where chart.frame != frame {
            self.glucoseChart = nil
        }

        if glucoseChart == nil {
            glucoseChart = generateGlucoseChartWithFrame(frame)
        }

        return glucoseChart
    }

    private func generateGlucoseChartWithFrame(frame: CGRect) -> Chart? {
        guard glucosePoints.count > 1, let xAxisValues = xAxisValues, xAxisModel = xAxisModel else {
            return nil
        }

        // TODO: The segment/multiple values are unit-specific
        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(glucosePoints, minSegmentCount: 2, maxSegmentCount: 4, multiple: 25, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: self.axisLabelSettings) }, addPaddingSegmentIfEdge: true)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: axisLineColor)

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The glucose targets
        var targetLayer: ChartPointsAreaLayer? = nil

        if let targets = glucoseTargetRangeSchedule {
            let targetPoints: [ChartPoint] = ChartPoint.pointsForGlucoseRangeSchedule(targets, xAxisValues: xAxisValues, yAxisValues: yAxisValues)

            targetLayer = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: targetPoints, areaColor: UIColor.glucoseTintColor.colorWithAlphaComponent(0.3), animDuration: 0, animDelay: 0, addContainerPoints: false)
        }

        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .XAndY, settings: guideLinesLayerSettings, onlyVisibleX: true, onlyVisibleY: false)

        let circles = ChartPointsScatterCirclesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: glucosePoints, displayDelay: 1, itemSize: CGSize(width: 4, height: 4), itemFillColor: UIColor.glucoseTintColor)

        let highlightLayer = ChartPointsTouchHighlightLayer(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: glucosePoints,
            gestureRecognizer: panGestureRecognizer,
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

    func IOBChartWithFrame(frame: CGRect) -> Chart? {
        if let chart = IOBChart where chart.frame != frame {
            self.IOBChart = nil
        }

        if IOBChart == nil {
            IOBChart = generateIOBChartWithFrame(frame)
        }

        return IOBChart
    }

    private func generateIOBChartWithFrame(frame: CGRect) -> Chart? {
        guard IOBPoints.count > 1, let xAxisModel = xAxisModel else {
            return nil
        }

        var containerPoints = IOBPoints

        // Create a container line at 0
        if let first = IOBPoints.first {
            containerPoints.insert(ChartPoint(x: first.x, y: ChartAxisValueInt(0)), atIndex: 0)
        }

        if let last = IOBPoints.last {
            containerPoints.append(ChartPoint(x: last.x, y: ChartAxisValueInt(0)))
        }

        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(IOBPoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: 0.5, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: self.axisLabelSettings) }, addPaddingSegmentIfEdge: false)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: axisLineColor)

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The IOB area
        let lineModel = ChartLineModel(chartPoints: IOBPoints, lineColor: UIColor.IOBTintColor, lineWidth: 2, animDuration: 0, animDelay: 0)
        let IOBLine = ChartPointsLineLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, lineModels: [lineModel])

        let IOBArea = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: containerPoints, areaColor: UIColor.IOBTintColor.colorWithAlphaComponent(0.5), animDuration: 0, animDelay: 0, addContainerPoints: false)

        // Grid lines
        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .XAndY, settings: guideLinesLayerSettings, onlyVisibleX: true, onlyVisibleY: false)

        // 0-line
        let dummyZeroChartPoint = ChartPoint(x: ChartAxisValueDouble(0), y: ChartAxisValueDouble(0))
        let zeroGuidelineLayer = ChartPointsViewsLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: [dummyZeroChartPoint], viewGenerator: {(chartPointModel, layer, chart) -> UIView? in
            let width: CGFloat = 0.5
            let viewFrame = CGRectMake(innerFrame.origin.x, chartPointModel.screenLoc.y - width / 2, innerFrame.size.width, width)

            let v = UIView(frame: viewFrame)
            v.backgroundColor = UIColor.IOBTintColor
            return v
        })

        let highlightLayer = ChartPointsTouchHighlightLayer(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: IOBPoints,
            gestureRecognizer: panGestureRecognizer,
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
            zeroGuidelineLayer,
            IOBArea,
            IOBLine,
            highlightLayer
        ]

        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }

    private func generateXAxisValues() {
        let points = glucosePoints + IOBPoints

        guard points.count > 1 else {
            self.xAxisValues = []
            return
        }

        let timeFormatter = NSDateFormatter()
        timeFormatter.dateFormat = "h a"

        let xAxisValues = ChartAxisValuesGenerator.generateXAxisValuesWithChartPoints(points, minSegmentCount: 5, maxSegmentCount: 10, multiple: NSTimeInterval(hours: 1), axisValueGenerator: { ChartAxisValueDate(date: ChartAxisValueDate.dateFromScalar($0), formatter: timeFormatter, labelSettings: self.axisLabelSettings)
            }, addPaddingSegmentIfEdge: true)
        xAxisValues.first?.hidden = true
        xAxisValues.last?.hidden = true

        self.xAxisValues = xAxisValues
    }

    func prerender() {
        glucoseChart = nil
        IOBChart = nil

        generateXAxisValues()
    }
}
