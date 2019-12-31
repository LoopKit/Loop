//
//  IOBChart.swift
//  LoopUI
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import SwiftCharts


public class IOBChart: ChartProviding {
    public init() {
    }

    /// The chart points for IOB
    public private(set) var iobPoints: [ChartPoint] = [] {
        didSet {
            if let lastDate = iobPoints.last?.x as? ChartAxisValueDate {
                endDate = lastDate.date
            }
        }
    }

    /// The minimum range to display for insulin values.
    private let iobDisplayRangePoints: [ChartPoint] = [0, 1].map {
        return ChartPoint(
            x: ChartAxisValue(scalar: 0),
            y: ChartAxisValueInt($0)
        )
    }

    public private(set) var endDate: Date?

    private var iobChartCache: ChartPointsTouchHighlightLayerViewCache?
}

public extension IOBChart {
    func didReceiveMemoryWarning() {
        iobPoints = []
        iobChartCache = nil
    }

    func generate(withFrame frame: CGRect, xAxisModel: ChartAxisModel, xAxisValues: [ChartAxisValue], axisLabelSettings: ChartLabelSettings, guideLinesLayerSettings: ChartGuideLinesLayerSettings, colors: ChartColorPalette, chartSettings: ChartSettings, labelsWidthY: CGFloat, gestureRecognizer: UIGestureRecognizer?, traitCollection: UITraitCollection) -> Chart
    {
        let yAxisValues = ChartAxisValuesStaticGenerator.generateYAxisValuesWithChartPoints(iobPoints + iobDisplayRangePoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: 0.5, axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: axisLabelSettings) }, addPaddingSegmentIfEdge: false)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(labelsWidthY))

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxisLayer, yAxisLayer, innerFrame) = (coordsSpace.xAxisLayer, coordsSpace.yAxisLayer, coordsSpace.chartInnerFrame)

        // The IOB area
        let lineModel = ChartLineModel(chartPoints: iobPoints, lineColor: UIColor.IOBTintColor, lineWidth: 2, animDuration: 0, animDelay: 0)
        let iobLine = ChartPointsLineLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, lineModels: [lineModel])

        let iobArea = ChartPointsFillsLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, fills: [ChartPointsFill(chartPoints: iobPoints, fillColor: UIColor.IOBTintColor.withAlphaComponent(0.5))])

        // Grid lines
        let gridLayer = ChartGuideLinesForValuesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, settings: guideLinesLayerSettings, axisValuesX: Array(xAxisValues.dropFirst().dropLast()), axisValuesY: yAxisValues)

        // 0-line
        let dummyZeroChartPoint = ChartPoint(x: ChartAxisValueDouble(0), y: ChartAxisValueDouble(0))
        let zeroGuidelineLayer = ChartPointsViewsLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, chartPoints: [dummyZeroChartPoint], viewGenerator: {(chartPointModel, layer, chart) -> UIView? in
            let width: CGFloat = 0.5
            let viewFrame = CGRect(x: chart.contentView.bounds.minX, y: chartPointModel.screenLoc.y - width / 2, width: chart.contentView.bounds.size.width, height: width)

            let v = UIView(frame: viewFrame)
            v.layer.backgroundColor = UIColor.IOBTintColor.cgColor
            return v
        })

        if gestureRecognizer != nil {
            iobChartCache = ChartPointsTouchHighlightLayerViewCache(
                xAxisLayer: xAxisLayer,
                yAxisLayer: yAxisLayer,
                axisLabelSettings: axisLabelSettings,
                chartPoints: iobPoints,
                tintColor: UIColor.IOBTintColor,
                gestureRecognizer: gestureRecognizer
            )
        }

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxisLayer,
            yAxisLayer,
            zeroGuidelineLayer,
            iobChartCache?.highlightLayer,
            iobArea,
            iobLine,
        ]

        return Chart(frame: frame, innerFrame: innerFrame, settings: chartSettings, layers: layers.compactMap { $0 })
    }
}

public extension IOBChart {
    func setIOBValues(_ iobValues: [InsulinValue]) {
        let dateFormatter = DateFormatter(timeStyle: .short)
        let doseFormatter = NumberFormatter.dose

        iobPoints = iobValues.map {
            return ChartPoint(
                x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                y: ChartAxisValueDoubleUnit($0.value, unitString: "U", formatter: doseFormatter)
            )
        }
    }
}
