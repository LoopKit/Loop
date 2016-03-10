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
        chartSettings.bottom = 0
        chartSettings.trailing = 8
        chartSettings.axisTitleLabelsToLabelsSpacing = 0
        chartSettings.labelsToAxisSpacingX = 6
        chartSettings.labelsWidthY = 30

        return chartSettings
    }()

    private lazy var dateFormatter: NSDateFormatter = {
        let timeFormatter = NSDateFormatter()
        timeFormatter.dateStyle = .NoStyle
        timeFormatter.timeStyle = .ShortStyle

        return timeFormatter
    }()

    private lazy var decimalFormatter: NSNumberFormatter = {
        let numberFormatter = NSNumberFormatter()
        numberFormatter.numberStyle = .DecimalStyle
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2

        return numberFormatter
    }()

    private lazy var integerFormatter: NSNumberFormatter = {
        let numberFormatter = NSNumberFormatter()
        numberFormatter.numberStyle = .NoStyle
        numberFormatter.maximumFractionDigits = 0

        return numberFormatter
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
            glucosePoints = glucoseValues.map({
                return ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDouble($0.quantity.doubleValueForUnit(HKUnit.milligramsPerDeciliterUnit()))
                )
            })
        }
    }

    var predictedGlucoseValues: [GlucoseValue] = [] {
        didSet {
            predictedGlucosePoints = predictedGlucoseValues.map({
                return ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDouble($0.quantity.doubleValueForUnit(HKUnit.milligramsPerDeciliterUnit()), formatter: integerFormatter)
                )
            })
        }
    }

    var IOBValues: [InsulinValue] = [] {
        didSet {
            IOBPoints = IOBValues.map {
                return ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDouble($0.value, formatter: decimalFormatter)
                )
            }
        }
    }

    var COBValues: [CarbValue] = [] {
        didSet {
            COBPoints = COBValues.map {
                ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDouble($0.quantity.doubleValueForUnit(HKUnit.gramUnit()), formatter: integerFormatter)
                )
            }
        }
    }

    var doseEntries: [DoseEntry] = [] {
        didSet {
            dosePoints = doseEntries.reduce([], combine: { (points, entry) -> [ChartPoint] in
                if entry.unit == .UnitsPerHour {
                    let startX = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                    let endX = ChartAxisValueDate(date: entry.endDate, formatter: dateFormatter)
                    let zero = ChartAxisValueInt(0)
                    let value = ChartAxisValueDoubleLog(actualDouble: entry.value, formatter: decimalFormatter)

                    let newPoints = [
                        ChartPoint(x: startX, y: zero),
                        ChartPoint(x: startX, y: value),
                        ChartPoint(x: endX, y: value),
                        ChartPoint(x: endX, y: zero)
                    ]

                    return points + newPoints
                } else {
                    return points
                }
            })
        }
    }

    // MARK: - State

    private var glucosePoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
            xAxisValues = nil
        }
    }

    private var predictedGlucosePoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
            xAxisValues = nil
        }
    }

    private var targetGlucosePoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
        }
    }

    private var IOBPoints: [ChartPoint] = [] {
        didSet {
            IOBChart = nil
            xAxisValues = nil
        }
    }

    private var COBPoints: [ChartPoint] = [] {
        didSet {
            COBChart = nil
            xAxisValues = nil
        }
    }

    private var dosePoints: [ChartPoint] = [] {
        didSet {
            doseChart = nil
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

    private var COBChart: Chart?

    private var doseChart: Chart?

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
        guard glucosePoints.count > 1, let xAxisModel = xAxisModel else {
            return nil
        }

        let allPoints = glucosePoints + predictedGlucosePoints

        // TODO: The segment/multiple values are unit-specific
        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(allPoints + targetGlucosePoints, minSegmentCount: 2, maxSegmentCount: 4, multiple: 25, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: self.axisLabelSettings) }, addPaddingSegmentIfEdge: true)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: axisLineColor)

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The glucose targets
        var targetLayer: ChartPointsAreaLayer? = nil

        if targetGlucosePoints.count > 1 {
            targetLayer = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: targetGlucosePoints, areaColor: UIColor.glucoseTintColor.colorWithAlphaComponent(0.3), animDuration: 0, animDelay: 0, addContainerPoints: false)
        }

        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .XAndY, settings: guideLinesLayerSettings, onlyVisibleX: true, onlyVisibleY: false)

        let circles = ChartPointsScatterCirclesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: glucosePoints, displayDelay: 0, itemSize: CGSize(width: 4, height: 4), itemFillColor: UIColor.glucoseTintColor)

        var prediction: ChartLayer?

        if predictedGlucosePoints.count > 1 {
            prediction = ChartPointsScatterCirclesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: predictedGlucosePoints, displayDelay: 0, itemSize: CGSize(width: 2, height: 2), itemFillColor: UIColor.glucoseTintColor.colorWithAlphaComponent(0.75))
        }

        let highlightLayer = StatusChartHighlightLayer(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: allPoints,
            tintColor: UIColor.glucoseTintColor,
            labelCenterY: chartSettings.top,
            gestureRecognizer: panGestureRecognizer
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            targetLayer,
            xAxis,
            yAxis,
            highlightLayer,
            prediction,
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

        let highlightLayer = StatusChartHighlightLayer(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: IOBPoints,
            tintColor: UIColor.IOBTintColor,
            labelCenterY: chartSettings.top,
            gestureRecognizer: panGestureRecognizer
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxis,
            yAxis,
            zeroGuidelineLayer,
            highlightLayer,
            IOBArea,
            IOBLine,
        ]

        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }

    func COBChartWithFrame(frame: CGRect) -> Chart? {
        if let chart = COBChart where chart.frame != frame {
            self.COBChart = nil
        }

        if COBChart == nil {
            COBChart = generateCOBChartWithFrame(frame)
        }

        return COBChart
    }

    private func generateCOBChartWithFrame(frame: CGRect) -> Chart? {
        guard COBPoints.count > 1, let xAxisModel = xAxisModel else {
            return nil
        }

        var containerPoints = COBPoints

        // Create a container line at 0
        if let first = COBPoints.first {
            containerPoints.insert(ChartPoint(x: first.x, y: ChartAxisValueInt(0)), atIndex: 0)
        }

        if let last = COBPoints.last {
            containerPoints.append(ChartPoint(x: last.x, y: ChartAxisValueInt(0)))
        }

        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(COBPoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: 10, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: self.axisLabelSettings) }, addPaddingSegmentIfEdge: false)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: axisLineColor)

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The COB area
        let lineModel = ChartLineModel(chartPoints: COBPoints, lineColor: UIColor.COBTintColor, lineWidth: 2, animDuration: 0, animDelay: 0)
        let COBLine = ChartPointsLineLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, lineModels: [lineModel])

        let COBArea = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: containerPoints, areaColor: UIColor.COBTintColor.colorWithAlphaComponent(0.5), animDuration: 0, animDelay: 0, addContainerPoints: false)

        // Grid lines
        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .XAndY, settings: guideLinesLayerSettings, onlyVisibleX: true, onlyVisibleY: false)


        let highlightLayer = StatusChartHighlightLayer(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: COBPoints,
            tintColor: UIColor.COBTintColor,
            labelCenterY: chartSettings.top,
            gestureRecognizer: panGestureRecognizer
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxis,
            yAxis,
            highlightLayer,
            COBArea,
            COBLine
        ]

        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }

    func doseChartWithFrame(frame: CGRect) -> Chart? {
        if let chart = doseChart where chart.frame != frame {
            self.doseChart = nil
        }

        if doseChart == nil {
            doseChart = generateDoseChartWithFrame(frame)
        }

        return doseChart
    }

    private func generateDoseChartWithFrame(frame: CGRect) -> Chart? {
        guard dosePoints.count > 1, let xAxisModel = xAxisModel else {
            return nil
        }

        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(dosePoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: log10(2) / 2, axisValueGenerator: { ChartAxisValueDoubleLog(screenLocDouble: $0, formatter: self.integerFormatter, labelSettings: self.axisLabelSettings) }, addPaddingSegmentIfEdge: true)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: axisLineColor)

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The dose area
        let lineModel = ChartLineModel(chartPoints: dosePoints, lineColor: UIColor.doseTintColor, lineWidth: 2, animDuration: 0, animDelay: 0)
        let doseLine = ChartPointsLineLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, lineModels: [lineModel])

        let doseArea = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: dosePoints, areaColor: UIColor.doseTintColor.colorWithAlphaComponent(0.5), animDuration: 0, animDelay: 0, addContainerPoints: false)

        // Grid lines
        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .XAndY, settings: guideLinesLayerSettings, onlyVisibleX: true, onlyVisibleY: false)

        // 0-line
        let dummyZeroChartPoint = ChartPoint(x: ChartAxisValueDouble(0), y: ChartAxisValueDouble(0))
        let zeroGuidelineLayer = ChartPointsViewsLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: [dummyZeroChartPoint], viewGenerator: {(chartPointModel, layer, chart) -> UIView? in
            let width: CGFloat = 1
            let viewFrame = CGRectMake(innerFrame.origin.x, chartPointModel.screenLoc.y - width / 2, innerFrame.size.width, width)

            let v = UIView(frame: viewFrame)
            v.backgroundColor = UIColor.doseTintColor
            return v
        })

        let highlightLayer = StatusChartHighlightLayer(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: dosePoints.filter { $0.y.scalar != 0 },
            tintColor: UIColor.doseTintColor,
            labelCenterY: chartSettings.top,
            gestureRecognizer: panGestureRecognizer
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxis,
            yAxis,
            zeroGuidelineLayer,
            highlightLayer,
            doseArea,
            doseLine
        ]
        
        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }

    private func generateXAxisValues() {
        let points = glucosePoints + predictedGlucosePoints + IOBPoints + COBPoints + dosePoints

        guard points.count > 1 else {
            self.xAxisValues = []
            return
        }

        let timeFormatter = NSDateFormatter()
        timeFormatter.dateFormat = "h a"

        let xAxisValues = ChartAxisValuesGenerator.generateXAxisValuesWithChartPoints(points, minSegmentCount: 5, maxSegmentCount: 10, multiple: NSTimeInterval(hours: 1), axisValueGenerator: { ChartAxisValueDate(date: ChartAxisValueDate.dateFromScalar($0), formatter: timeFormatter, labelSettings: self.axisLabelSettings)
            }, addPaddingSegmentIfEdge: false)
        xAxisValues.first?.hidden = true
        xAxisValues.last?.hidden = true

        self.xAxisValues = xAxisValues
    }

    func prerender() {
        glucoseChart = nil
        IOBChart = nil
        COBChart = nil

        generateXAxisValues()

        if let xAxisValues = xAxisValues where xAxisValues.count > 1,
            let targets = glucoseTargetRangeSchedule {
            targetGlucosePoints = ChartPoint.pointsForGlucoseRangeSchedule(targets, xAxisValues: xAxisValues)
        }
    }
}
