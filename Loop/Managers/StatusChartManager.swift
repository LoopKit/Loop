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


final class StatusChartsManager {

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

    /// The amount of horizontal space reserved for fixed margins
    var fixedHorizontalMargin: CGFloat {
        return chartSettings.leading + chartSettings.trailing + (chartSettings.labelsWidthY ?? 0) + chartSettings.labelsToAxisSpacingY
    }

    private lazy var dateFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        return timeFormatter
    }()

    private lazy var doseFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2

        return numberFormatter
    }()

    private lazy var integerFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .none
        numberFormatter.maximumFractionDigits = 0

        return numberFormatter
    }()

    private lazy var axisLineColor = UIColor.clear

    private lazy var axisLabelSettings: ChartLabelSettings = ChartLabelSettings(font: UIFont.preferredFont(forTextStyle: UIFontTextStyle.caption1), fontColor: UIColor.secondaryLabelColor)

    private lazy var guideLinesLayerSettings: ChartGuideLinesLayerSettings = ChartGuideLinesLayerSettings(linesColor: UIColor.gridColor)

    var panGestureRecognizer: UIPanGestureRecognizer?

    // MARK: - Data

    var startDate = Date()

    var glucoseUnit: HKUnit = HKUnit.milligramsPerDeciliterUnit() {
        didSet {
            if glucoseUnit != oldValue {
                // Regenerate the glucose display points
                let oldRange = glucoseDisplayRange
                glucoseDisplayRange = oldRange
            }
        }
    }

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule?

    var glucoseValues: [GlucoseValue] = [] {
        didSet {
            let unitString = glucoseUnit.glucoseUnitDisplayString
            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: glucoseUnit)
            glucosePoints = glucoseValues.map {
                return ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: glucoseUnit), unitString: unitString, formatter: glucoseFormatter)
                )
            }
        }
    }

    var glucoseDisplayRange: (min: HKQuantity, max: HKQuantity)? {
        didSet {
            if let range = glucoseDisplayRange {
                glucoseDisplayRangePoints = [
                    ChartPoint(x: ChartAxisValue(scalar: 0), y: ChartAxisValueDouble(range.min.doubleValue(for: glucoseUnit))),
                    ChartPoint(x: ChartAxisValue(scalar: 0), y: ChartAxisValueDouble(range.max.doubleValue(for: glucoseUnit)))
                ]
            } else {
                glucoseDisplayRangePoints = []
            }
        }
    }

    var predictedGlucoseValues: [GlucoseValue] = [] {
        didSet {
            let unitString = glucoseUnit.glucoseUnitDisplayString
            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: glucoseUnit)

            predictedGlucosePoints = predictedGlucoseValues.map {
                return ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: glucoseUnit), unitString: unitString, formatter: glucoseFormatter)
                )
            }
        }
    }

    var alternatePredictedGlucoseValues: [GlucoseValue] = [] {
        didSet {
            let unitString = glucoseUnit.glucoseUnitDisplayString
            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: glucoseUnit)

            alternatePredictedGlucosePoints = alternatePredictedGlucoseValues.map {
                return ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: glucoseUnit), unitString: unitString, formatter: glucoseFormatter)
                )
            }
        }
    }

    var iobValues: [InsulinValue] = [] {
        didSet {
            iobPoints = iobValues.map {
                return ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDoubleUnit($0.value, unitString: "U", formatter: doseFormatter)
                )
            }
        }
    }

    var cobValues: [CarbValue] = [] {
        didSet {
            let unit = HKUnit.gram()
            let unitString = unit.unitString

            cobPoints = cobValues.map {
                ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: unit), unitString: unitString, formatter: integerFormatter)
                )
            }
        }
    }

    var doseEntries: [DoseEntry] = [] {
        didSet {
            var basalDosePoints = [ChartPoint]()
            var bolusDosePoints = [ChartPoint]()
            var allDosePoints = [ChartPoint]()

            for entry in doseEntries {
                switch entry.unit {
                case .unitsPerHour:
                    // TODO: Display the DateInterval
                    let startX = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                    let endX = ChartAxisValueDate(date: entry.endDate, formatter: dateFormatter)
                    let zero = ChartAxisValueInt(0)
                    let value = ChartAxisValueDoubleLog(actualDouble: entry.value, unitString: "U/hour", formatter: doseFormatter)

                    basalDosePoints += [
                        ChartPoint(x: startX, y: zero),
                        ChartPoint(x: startX, y: value),
                        ChartPoint(x: endX, y: value),
                        ChartPoint(x: endX, y: zero)
                    ]

                    if entry.value != 0 {
                        allDosePoints += [
                            ChartPoint(x: startX, y: value),
                            ChartPoint(x: endX, y: value)
                        ]
                    }
                case .units:
                    let x = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                    let y = ChartAxisValueDoubleLog(actualDouble: entry.value, unitString: "U", formatter: doseFormatter)

                    let point = ChartPoint(x: x, y: y)
                    bolusDosePoints.append(point)
                    allDosePoints.append(point)
                }
            }

            self.basalDosePoints = basalDosePoints
            self.bolusDosePoints = bolusDosePoints
            self.allDosePoints = allDosePoints
        }
    }

    // MARK: - State

    private var glucosePoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
            xAxisValues = nil
        }
    }

    private var glucoseDisplayRangePoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
        }
    }

    /// The chart points for predicted glucose
    var predictedGlucosePoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
            xAxisValues = nil
        }
    }

    /// The chart points for alternate predicted glucose
    var alternatePredictedGlucosePoints: [ChartPoint]?

    private var targetGlucosePoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
        }
    }

    private var targetOverridePoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
        }
    }

    private var targetOverrideDurationPoints: [ChartPoint] = [] {
        didSet {
            glucoseChart = nil
        }
    }

    /// The chart points for IOB
    var iobPoints: [ChartPoint] = [] {
        didSet {
            iobChart = nil
            xAxisValues = nil
        }
    }

    /// The minimum range to display for insulin values.
    private let iobDisplayRangePoints: [ChartPoint] = [0, 1].map {
        return ChartPoint(
            x: ChartAxisValue(scalar: 0),
            y: ChartAxisValueInt($0)
        )
    }

    /// The chart points for COB
    var cobPoints: [ChartPoint] = [] {
        didSet {
            cobChart = nil
            xAxisValues = nil
        }
    }

    /// The minimum range to display for COB values.
    private var cobDisplayRangePoints: [ChartPoint] = [0, 10].map {
        return ChartPoint(
            x: ChartAxisValue(scalar: 0),
            y: ChartAxisValueInt($0)
        )
    }

    private var basalDosePoints: [ChartPoint] = [] {
        didSet {
            doseChart = nil
            xAxisValues = nil
        }
    }

    private var bolusDosePoints: [ChartPoint] = [] {
        didSet {
            doseChart = nil
            xAxisValues = nil
        }
    }

    private var allDosePoints: [ChartPoint] = []

    private var xAxisValues: [ChartAxisValue]? {
        didSet {
            if let xAxisValues = xAxisValues, xAxisValues.count > 1 {
                xAxisModel = ChartAxisModel(axisValues: xAxisValues, lineColor: axisLineColor)
            } else {
                xAxisModel = nil
            }
        }
    }

    private var xAxisModel: ChartAxisModel?

    private var glucoseChart: Chart?

    private var iobChart: Chart?

    private var cobChart: Chart?

    private var doseChart: Chart?

    private var glucoseChartCache: ChartPointsTouchHighlightLayerViewCache?

    private var iobChartCache: ChartPointsTouchHighlightLayerViewCache?

    private var cobChartCache: ChartPointsTouchHighlightLayerViewCache?

    private var doseChartCache: ChartPointsTouchHighlightLayerViewCache?

    // MARK: - Generators

    func glucoseChartWithFrame(_ frame: CGRect) -> Chart? {
        if let chart = glucoseChart, chart.frame != frame {
            self.glucoseChart = nil
        }

        if glucoseChart == nil {
            glucoseChart = generateGlucoseChartWithFrame(frame)
        }

        return glucoseChart
    }

    private func generateGlucoseChartWithFrame(_ frame: CGRect) -> Chart? {
        guard let xAxisModel = xAxisModel else {
            return nil
        }

        let points = glucosePoints + predictedGlucosePoints + targetGlucosePoints + targetOverridePoints + glucoseDisplayRangePoints

        guard points.count > 1 else {
            return nil
        }

        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(points,
            minSegmentCount: 2,
            maxSegmentCount: 4,
            multiple: glucoseUnit.glucoseUnitYAxisSegmentSize,
            axisValueGenerator: {
                ChartAxisValueDouble($0, labelSettings: self.axisLabelSettings)
            },
            addPaddingSegmentIfEdge: false
        )

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: axisLineColor)

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The glucose targets
        var targetLayer: ChartPointsAreaLayer? = nil

        if targetGlucosePoints.count > 1 {
            let alpha: CGFloat = targetOverridePoints.count > 1 ? 0.15 : 0.3

            targetLayer = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: targetGlucosePoints, areaColor: UIColor.glucoseTintColor.withAlphaComponent(alpha), animDuration: 0, animDelay: 0, addContainerPoints: false)
        }

        var targetOverrideLayer: ChartPointsAreaLayer? = nil

        if targetOverridePoints.count > 1 {
            targetOverrideLayer = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: targetOverridePoints, areaColor: UIColor.glucoseTintColor.withAlphaComponent(0.3), animDuration: 0, animDelay: 0, addContainerPoints: false)
        }

        var targetOverrideDurationLayer: ChartPointsAreaLayer? = nil

        if targetOverrideDurationPoints.count > 1 {
            targetOverrideDurationLayer = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: targetOverrideDurationPoints, areaColor: UIColor.glucoseTintColor.withAlphaComponent(0.3), animDuration: 0, animDelay: 0, addContainerPoints: false)
        }

        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .xAndY, settings: guideLinesLayerSettings, onlyVisibleX: true, onlyVisibleY: false)

        let circles = ChartPointsScatterCirclesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: glucosePoints, displayDelay: 0, itemSize: CGSize(width: 4, height: 4), itemFillColor: UIColor.glucoseTintColor)

        var alternatePrediction: ChartLayer?

        if let altPoints = alternatePredictedGlucosePoints, altPoints.count > 1 {
            // TODO: Bug in ChartPointsLineLayer requires a non-zero animation to draw the dash pattern
            let lineModel = ChartLineModel(chartPoints: altPoints, lineColor: UIColor.glucoseTintColor, lineWidth: 2, animDuration: 0.0001, animDelay: 0, dashPattern: [6, 5])

            alternatePrediction = ChartPointsLineLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, lineModels: [lineModel])
        }

        var prediction: ChartLayer?

        if predictedGlucosePoints.count > 1 {
            let lineColor = (alternatePrediction == nil) ? UIColor.glucoseTintColor : UIColor.secondaryLabelColor

            // TODO: Bug in ChartPointsLineLayer requires a non-zero animation to draw the dash pattern
            let lineModel = ChartLineModel(
                chartPoints: predictedGlucosePoints,
                lineColor: lineColor,
                lineWidth: 1,
                animDuration: 0.0001,
                animDelay: 0,
                dashPattern: [6, 5]
            )

            prediction = ChartPointsLineLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, lineModels: [lineModel])
        }

        glucoseChartCache = ChartPointsTouchHighlightLayerViewCache(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: glucosePoints + (alternatePredictedGlucosePoints ?? predictedGlucosePoints),
            tintColor: UIColor.glucoseTintColor,
            labelCenterY: chartSettings.top,
            gestureRecognizer: panGestureRecognizer
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            targetLayer,
            targetOverrideLayer,
            targetOverrideDurationLayer,
            xAxis,
            yAxis,
            glucoseChartCache?.highlightLayer,
            prediction,
            alternatePrediction,
            circles
        ]

        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }

    func iobChartWithFrame(_ frame: CGRect) -> Chart? {
        if let chart = iobChart, chart.frame != frame {
            self.iobChart = nil
        }

        if iobChart == nil {
            iobChart = generateIOBChartWithFrame(frame)
        }

        return iobChart
    }

    private func generateIOBChartWithFrame(_ frame: CGRect) -> Chart? {
        guard let xAxisModel = xAxisModel else {
            return nil
        }

        var containerPoints = iobPoints

        // Create a container line at 0
        if let first = iobPoints.first {
            containerPoints.insert(ChartPoint(x: first.x, y: ChartAxisValueInt(0)), at: 0)
        }

        if let last = iobPoints.last {
            containerPoints.append(ChartPoint(x: last.x, y: ChartAxisValueInt(0)))
        }

        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(iobPoints + iobDisplayRangePoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: 0.5, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: self.axisLabelSettings) }, addPaddingSegmentIfEdge: false)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: axisLineColor)

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The IOB area
        let lineModel = ChartLineModel(chartPoints: iobPoints, lineColor: UIColor.IOBTintColor, lineWidth: 2, animDuration: 0, animDelay: 0)
        let iobLine = ChartPointsLineLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, lineModels: [lineModel])

        let iobArea: ChartPointsAreaLayer<ChartPoint>?

        if containerPoints.count > 1 {
            iobArea = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: containerPoints, areaColor: UIColor.IOBTintColor.withAlphaComponent(0.5), animDuration: 0, animDelay: 0, addContainerPoints: false)
        } else {
            iobArea = nil
        }

        // Grid lines
        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .xAndY, settings: guideLinesLayerSettings, onlyVisibleX: true, onlyVisibleY: false)

        // 0-line
        let dummyZeroChartPoint = ChartPoint(x: ChartAxisValueDouble(0), y: ChartAxisValueDouble(0))
        let zeroGuidelineLayer = ChartPointsViewsLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: [dummyZeroChartPoint], viewGenerator: {(chartPointModel, layer, chart) -> UIView? in
            let width: CGFloat = 0.5
            let viewFrame = CGRect(x: innerFrame.origin.x, y: chartPointModel.screenLoc.y - width / 2, width: innerFrame.size.width, height: width)

            let v = UIView(frame: viewFrame)
            v.backgroundColor = UIColor.IOBTintColor
            return v
        })

        iobChartCache = ChartPointsTouchHighlightLayerViewCache(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: iobPoints,
            tintColor: UIColor.IOBTintColor,
            labelCenterY: chartSettings.top,
            gestureRecognizer: panGestureRecognizer
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxis,
            yAxis,
            zeroGuidelineLayer,
            iobChartCache?.highlightLayer,
            iobArea,
            iobLine,
        ]

        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }

    func cobChartWithFrame(_ frame: CGRect) -> Chart? {
        if let chart = cobChart, chart.frame != frame {
            self.cobChart = nil
        }

        if cobChart == nil {
            cobChart = generateCOBChartWithFrame(frame)
        }

        return cobChart
    }

    private func generateCOBChartWithFrame(_ frame: CGRect) -> Chart? {
        guard let xAxisModel = xAxisModel else {
            return nil
        }

        var containerPoints = cobPoints

        // Create a container line at 0
        if let first = cobPoints.first {
            containerPoints.insert(ChartPoint(x: first.x, y: ChartAxisValueInt(0)), at: 0)
        }

        if let last = cobPoints.last {
            containerPoints.append(ChartPoint(x: last.x, y: ChartAxisValueInt(0)))
        }

        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(cobPoints + cobDisplayRangePoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: 10, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: self.axisLabelSettings) }, addPaddingSegmentIfEdge: false)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: axisLineColor)

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The COB area
        let lineModel = ChartLineModel(chartPoints: cobPoints, lineColor: UIColor.COBTintColor, lineWidth: 2, animDuration: 0, animDelay: 0)
        let cobLine = ChartPointsLineLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, lineModels: [lineModel])

        let cobArea: ChartPointsAreaLayer<ChartPoint>?

        if containerPoints.count > 0 {
            cobArea = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: containerPoints, areaColor: UIColor.COBTintColor.withAlphaComponent(0.5), animDuration: 0, animDelay: 0, addContainerPoints: false)
        } else {
            cobArea = nil
        }

        // Grid lines
        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .xAndY, settings: guideLinesLayerSettings, onlyVisibleX: true, onlyVisibleY: false)


        cobChartCache = ChartPointsTouchHighlightLayerViewCache(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: cobPoints,
            tintColor: UIColor.COBTintColor,
            labelCenterY: chartSettings.top,
            gestureRecognizer: panGestureRecognizer
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxis,
            yAxis,
            cobChartCache?.highlightLayer,
            cobArea,
            cobLine
        ]

        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }

    func doseChartWithFrame(_ frame: CGRect) -> Chart? {
        if let chart = doseChart, chart.frame != frame {
            self.doseChart = nil
        }

        if doseChart == nil {
            doseChart = generateDoseChartWithFrame(frame)
        }

        return doseChart
    }

    private func generateDoseChartWithFrame(_ frame: CGRect) -> Chart? {
        guard let xAxisModel = xAxisModel else {
            return nil
        }

        let yAxisValues = ChartAxisValuesGenerator.generateYAxisValuesWithChartPoints(basalDosePoints + bolusDosePoints + iobDisplayRangePoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: log10(2) / 2, axisValueGenerator: { ChartAxisValueDoubleLog(screenLocDouble: $0, formatter: self.integerFormatter, labelSettings: self.axisLabelSettings) }, addPaddingSegmentIfEdge: true)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: axisLineColor)

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxis, yAxis, innerFrame) = (coordsSpace.xAxis, coordsSpace.yAxis, coordsSpace.chartInnerFrame)

        // The dose area
        let lineModel = ChartLineModel(chartPoints: basalDosePoints, lineColor: UIColor.doseTintColor, lineWidth: 2, animDuration: 0, animDelay: 0)
        let doseLine = ChartPointsLineLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, lineModels: [lineModel])

        let doseArea: ChartPointsAreaLayer<ChartPoint>?

        if basalDosePoints.count > 1 {
            doseArea = ChartPointsAreaLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: basalDosePoints, areaColor: UIColor.doseTintColor.withAlphaComponent(0.5), animDuration: 0, animDelay: 0, addContainerPoints: false)
        } else {
            doseArea = nil
        }

        let bolusLayer: ChartPointsScatterDownTrianglesLayer<ChartPoint>?

        if bolusDosePoints.count > 0 {
            bolusLayer = ChartPointsScatterDownTrianglesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: bolusDosePoints, displayDelay: 0, itemSize: CGSize(width: 12, height: 12), itemFillColor: UIColor.doseTintColor)
        } else {
            bolusLayer = nil
        }

        // Grid lines
        let gridLayer = ChartGuideLinesLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, axis: .xAndY, settings: guideLinesLayerSettings, onlyVisibleX: true, onlyVisibleY: false)

        // 0-line
        let dummyZeroChartPoint = ChartPoint(x: ChartAxisValueDouble(0), y: ChartAxisValueDouble(0))
        let zeroGuidelineLayer = ChartPointsViewsLayer(xAxis: xAxis, yAxis: yAxis, innerFrame: innerFrame, chartPoints: [dummyZeroChartPoint], viewGenerator: {(chartPointModel, layer, chart) -> UIView? in
            let width: CGFloat = 1
            let viewFrame = CGRect(x: innerFrame.origin.x, y: chartPointModel.screenLoc.y - width / 2, width: innerFrame.size.width, height: width)

            let v = UIView(frame: viewFrame)
            v.backgroundColor = UIColor.doseTintColor
            return v
        })

        doseChartCache = ChartPointsTouchHighlightLayerViewCache(
            xAxis: xAxis,
            yAxis: yAxis,
            innerFrame: innerFrame,
            chartPoints: allDosePoints,
            tintColor: UIColor.doseTintColor,
            labelCenterY: chartSettings.top,
            gestureRecognizer: panGestureRecognizer
        )

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxis,
            yAxis,
            zeroGuidelineLayer,
            doseChartCache?.highlightLayer,
            doseArea,
            doseLine,
            bolusLayer
        ]
        
        return Chart(frame: frame, layers: layers.flatMap { $0 })
    }

    private func generateXAxisValues() {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h a"

        let points = [
            ChartPoint(x: ChartAxisValueDate(date: startDate, formatter: timeFormatter), y: ChartAxisValue(scalar: 0)),
            ChartPoint(x: ChartAxisValueDate(date: startDate.addingTimeInterval(TimeInterval(hours: 4)), formatter: timeFormatter), y: ChartAxisValue(scalar: 0)),
            glucosePoints.last,
            predictedGlucosePoints.last,
            iobPoints.last,
            cobPoints.last,
            basalDosePoints.last
        ].flatMap { $0 }

        guard points.count > 1 else {
            self.xAxisValues = []
            return
        }

        let xAxisValues = ChartAxisValuesGenerator.generateXAxisValuesWithChartPoints(points, minSegmentCount: 4, maxSegmentCount: 10, multiple: TimeInterval(hours: 1), axisValueGenerator: {
            ChartAxisValueDate(date: ChartAxisValueDate.dateFromScalar($0), formatter: timeFormatter, labelSettings: self.axisLabelSettings)
        }, addPaddingSegmentIfEdge: false)
        xAxisValues.first?.hidden = true
        xAxisValues.last?.hidden = true

        self.xAxisValues = xAxisValues
    }

    func prerender() {
        glucoseChart = nil
        iobChart = nil
        cobChart = nil

        generateXAxisValues()

        if let xAxisValues = xAxisValues, xAxisValues.count > 1,
            let targets = glucoseTargetRangeSchedule {
            targetGlucosePoints = ChartPoint.pointsForGlucoseRangeSchedule(targets, xAxisValues: xAxisValues)

            if let override = targets.temporaryOverride {
                targetOverridePoints = ChartPoint.pointsForGlucoseRangeScheduleOverride(override, xAxisValues: xAxisValues)

                targetOverrideDurationPoints = ChartPoint.pointsForGlucoseRangeScheduleOverrideDuration(override, xAxisValues: xAxisValues)
            } else {
                targetOverridePoints = []
                targetOverrideDurationPoints = []
            }
        }
    }
}


private extension HKUnit {
    var glucoseUnitYAxisSegmentSize: Double {
        if self == HKUnit.milligramsPerDeciliterUnit() {
            return 25
        } else {
            return 1
        }
    }
}
