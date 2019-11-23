//
//  DoseChart.swift
//  LoopUI
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import SwiftCharts


public class DoseChart: ChartProviding {
    public init() {
    }

    public private(set) var basalDosePoints: [ChartPoint] = []
    public private(set) var bolusDosePoints: [ChartPoint] = []

    /// Dose points selectable when highlighting
    public private(set) var allDosePoints: [ChartPoint] = [] {
        didSet {
            if let lastDate = allDosePoints.last?.x as? ChartAxisValueDate {
                endDate = lastDate.date
            }
        }
    }

    /// The minimum range to display for insulin values.
    private let doseDisplayRangePoints: [ChartPoint] = [0, 1].map {
        return ChartPoint(
            x: ChartAxisValue(scalar: 0),
            y: ChartAxisValueInt($0)
        )
    }

    public private(set) var endDate: Date?

    private var doseChartCache: ChartPointsTouchHighlightLayerViewCache?
}

public extension DoseChart {
    func didReceiveMemoryWarning() {
        basalDosePoints = []
        bolusDosePoints = []
        allDosePoints = []
        doseChartCache = nil
    }

    func generate(withFrame frame: CGRect, xAxisModel: ChartAxisModel, xAxisValues: [ChartAxisValue], axisLabelSettings: ChartLabelSettings, guideLinesLayerSettings: ChartGuideLinesLayerSettings, colors: ChartColorPalette, chartSettings: ChartSettings, labelsWidthY: CGFloat, gestureRecognizer: UIGestureRecognizer?, traitCollection: UITraitCollection) -> Chart
    {
        let integerFormatter = NumberFormatter.integer

        let yAxisValues = ChartAxisValuesStaticGenerator.generateYAxisValuesWithChartPoints(basalDosePoints + bolusDosePoints + doseDisplayRangePoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: log10(2) / 2, axisValueGenerator: { ChartAxisValueDoubleLog(screenLocDouble: $0, formatter: integerFormatter, labelSettings: axisLabelSettings) }, addPaddingSegmentIfEdge: true)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(labelsWidthY))

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxisLayer, yAxisLayer, innerFrame) = (coordsSpace.xAxisLayer, coordsSpace.yAxisLayer, coordsSpace.chartInnerFrame)

        // The dose area
        let lineModel = ChartLineModel(chartPoints: basalDosePoints, lineColor: colors.doseTint, lineWidth: 2, animDuration: 0, animDelay: 0)
        let doseLine = ChartPointsLineLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, lineModels: [lineModel])

        let doseArea = ChartPointsFillsLayer(
            xAxis: xAxisLayer.axis,
            yAxis: yAxisLayer.axis,
            fills: [ChartPointsFill(
                chartPoints: basalDosePoints,
                fillColor: colors.doseTint.withAlphaComponent(0.5),
                createContainerPoints: false
            )]
        )

        let bolusLayer: ChartPointsScatterDownTrianglesLayer<ChartPoint>?

        if bolusDosePoints.count > 0 {
            bolusLayer = ChartPointsScatterDownTrianglesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, chartPoints: bolusDosePoints, displayDelay: 0, itemSize: CGSize(width: 12, height: 12), itemFillColor: colors.doseTint)
        } else {
            bolusLayer = nil
        }

        // Grid lines
        let gridLayer = ChartGuideLinesForValuesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, settings: guideLinesLayerSettings, axisValuesX: Array(xAxisValues.dropFirst().dropLast()), axisValuesY: yAxisValues)

        let currentTimeValue = ChartAxisValueDate(date: Date(), formatter: { _ in "" })
        let currentTimeSettings = ChartGuideLinesLayerSettings(linesColor: colors.doseTint, linesWidth: 0.5)
        let currentTimeLayer = ChartGuideLinesForValuesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, settings: currentTimeSettings, axisValuesX: [currentTimeValue], axisValuesY: [])

        // 0-line
        let dummyZeroChartPoint = ChartPoint(x: ChartAxisValueDouble(0), y: ChartAxisValueDouble(0))
        let zeroGuidelineLayer = ChartPointsViewsLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, chartPoints: [dummyZeroChartPoint], viewGenerator: {(chartPointModel, layer, chart) -> UIView? in
            let width: CGFloat = 1
            let viewFrame = CGRect(x: chart.contentView.bounds.minX, y: chartPointModel.screenLoc.y - width / 2, width: chart.contentView.bounds.size.width, height: width)

            let v = UIView(frame: viewFrame)
            v.layer.backgroundColor = colors.doseTint.cgColor
            return v
        })

        if gestureRecognizer != nil {
            doseChartCache = ChartPointsTouchHighlightLayerViewCache(
                xAxisLayer: xAxisLayer,
                yAxisLayer: yAxisLayer,
                axisLabelSettings: axisLabelSettings,
                chartPoints: allDosePoints,
                tintColor: colors.doseTint,
                gestureRecognizer: gestureRecognizer
            )
        }

        let layers: [ChartLayer?] = [
            gridLayer,
            currentTimeLayer,
            xAxisLayer,
            yAxisLayer,
            zeroGuidelineLayer,
            doseChartCache?.highlightLayer,
            doseArea,
            doseLine,
            bolusLayer
        ]

        return Chart(frame: frame, innerFrame: innerFrame, settings: chartSettings, layers: layers.compactMap { $0 })
    }
}

public extension DoseChart {
    func setDoseEntries(_ doseEntries: [DoseEntry]) {
        let dateFormatter = DateFormatter(timeStyle: .short)
        let doseFormatter = NumberFormatter.dose

        var basalDosePoints = [ChartPoint]()
        var bolusDosePoints = [ChartPoint]()
        var allDosePoints = [ChartPoint]()

        for entry in doseEntries {
            let time = entry.endDate.timeIntervalSince(entry.startDate)

            if entry.type == .bolus && entry.netBasalUnits > 0 {
                let x = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                let y = ChartAxisValueDoubleLog(actualDouble: entry.unitsInDeliverableIncrements, unitString: "U", formatter: doseFormatter)

                let point = ChartPoint(x: x, y: y)
                bolusDosePoints.append(point)
                allDosePoints.append(point)
            } else if time > 0 {
                // TODO: Display the DateInterval
                let startX = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                let endX = ChartAxisValueDate(date: entry.endDate, formatter: dateFormatter)
                let zero = ChartAxisValueInt(0)
                let rate = entry.netBasalUnitsPerHour
                let value = ChartAxisValueDoubleLog(actualDouble: rate, unitString: "U/hour", formatter: doseFormatter)

                let valuePoints: [ChartPoint]

                if abs(rate) > .ulpOfOne {
                    valuePoints = [
                        ChartPoint(x: startX, y: value),
                        ChartPoint(x: endX, y: value)
                    ]
                } else {
                    valuePoints = []
                }

                basalDosePoints += [
                    ChartPoint(x: startX, y: zero)
                ] + valuePoints + [
                    ChartPoint(x: endX, y: zero)
                ]

                allDosePoints += valuePoints
            }
        }

        self.basalDosePoints = basalDosePoints
        self.bolusDosePoints = bolusDosePoints
        self.allDosePoints = allDosePoints
    }
}
