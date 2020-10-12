//
//  COBChart.swift
//  LoopUI
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import SwiftCharts


public class COBChart: ChartProviding {
    public init() {
    }

    /// The chart points for COB
    public private(set) var cobPoints: [ChartPoint] = [] {
        didSet {
            if let lastDate = cobPoints.last?.x as? ChartAxisValueDate {
                endDate = lastDate.date
            }
        }
    }

    /// The minimum range to display for COB values.
    private var cobDisplayRangePoints: [ChartPoint] = [0, 10].map {
        return ChartPoint(
            x: ChartAxisValue(scalar: 0),
            y: ChartAxisValueInt($0)
        )
    }

    public private(set) var endDate: Date?

    private var cobChartCache: ChartPointsTouchHighlightLayerViewCache?
}

public extension COBChart {
    func didReceiveMemoryWarning() {
        cobPoints = []
        cobChartCache = nil
    }

    func generate(withFrame frame: CGRect, xAxisModel: ChartAxisModel, xAxisValues: [ChartAxisValue], axisLabelSettings: ChartLabelSettings, guideLinesLayerSettings: ChartGuideLinesLayerSettings, colors: ChartColorPalette, chartSettings: ChartSettings, labelsWidthY: CGFloat, gestureRecognizer: UIGestureRecognizer?, traitCollection: UITraitCollection) -> Chart
    {
        let yAxisValues = ChartAxisValuesStaticGenerator.generateYAxisValuesWithChartPoints(cobPoints + cobDisplayRangePoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: 10, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: axisLabelSettings) }, addPaddingSegmentIfEdge: false)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(labelsWidthY))

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxisLayer, yAxisLayer, innerFrame) = (coordsSpace.xAxisLayer, coordsSpace.yAxisLayer, coordsSpace.chartInnerFrame)

        // The COB area
        let lineModel = ChartLineModel(chartPoints: cobPoints, lineColor: UIColor.COBTintColor, lineWidth: 2, animDuration: 0, animDelay: 0)
        let cobLine = ChartPointsLineLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, lineModels: [lineModel])

        let cobArea = ChartPointsFillsLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, fills: [ChartPointsFill(chartPoints: cobPoints, fillColor: UIColor.COBTintColor.withAlphaComponent(0.5))])

        // Grid lines
        let gridLayer = ChartGuideLinesForValuesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, settings: guideLinesLayerSettings, axisValuesX: Array(xAxisValues.dropFirst().dropLast()), axisValuesY: yAxisValues)
        
        let currentTimeValue = ChartAxisValueDate(date: Date(), formatter: { _ in "" })
        let currentTimeSettings = ChartGuideLinesLayerSettings(linesColor: .COBTintColor, linesWidth: 0.5)
        let currentTimeLayer = ChartGuideLinesForValuesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, settings: currentTimeSettings, axisValuesX: [currentTimeValue], axisValuesY: [])

        if gestureRecognizer != nil {
            cobChartCache = ChartPointsTouchHighlightLayerViewCache(
                xAxisLayer: xAxisLayer,
                yAxisLayer: yAxisLayer,
                axisLabelSettings: axisLabelSettings,
                chartPoints: cobPoints,
                tintColor: UIColor.COBTintColor,
                gestureRecognizer: gestureRecognizer
            )
        }

        let layers: [ChartLayer?] = [
            gridLayer,
            currentTimeLayer,
            xAxisLayer,
            yAxisLayer,
            cobChartCache?.highlightLayer,
            cobArea,
            cobLine
        ]

        return Chart(frame: frame, innerFrame: innerFrame, settings: chartSettings, layers: layers.compactMap { $0 })
    }
}

public extension COBChart {
    func setCOBValues(_ cobValues: [CarbValue]) {
        let dateFormatter = DateFormatter(timeStyle: .short)
        let integerFormatter = NumberFormatter.integer

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
