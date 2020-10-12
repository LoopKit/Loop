//
//  DoseChart.swift
//  LoopUI
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import SwiftCharts

fileprivate struct DosePointsCache {
    let basal: [ChartPoint]
    let basalFill: [ChartPoint]
    let bolus: [ChartPoint]
    let highlight: [ChartPoint]
}

public class DoseChart: ChartProviding {
    public init() {
        doseEntries = []
    }
    
    public var doseEntries: [DoseEntry] {
        didSet {
            pointsCache = nil
        }
    }

    private var pointsCache: DosePointsCache? {
        didSet {
            if let pointsCache = pointsCache {
                if let lastDate = pointsCache.highlight.last?.x as? ChartAxisValueDate {
                    endDate = lastDate.date
                }
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
        pointsCache = nil
        doseChartCache = nil
    }

    func generate(withFrame frame: CGRect, xAxisModel: ChartAxisModel, xAxisValues: [ChartAxisValue], axisLabelSettings: ChartLabelSettings, guideLinesLayerSettings: ChartGuideLinesLayerSettings, colors: ChartColorPalette, chartSettings: ChartSettings, labelsWidthY: CGFloat, gestureRecognizer: UIGestureRecognizer?, traitCollection: UITraitCollection) -> Chart
    {
        let integerFormatter = NumberFormatter.integer
        
        let startDate = ChartAxisValueDate.dateFromScalar(xAxisValues.first!.scalar)
        
        let points = generateDosePoints(startDate: startDate)

        let yAxisValues = ChartAxisValuesStaticGenerator.generateYAxisValuesWithChartPoints(points.basal + points.bolus + doseDisplayRangePoints, minSegmentCount: 2, maxSegmentCount: 3, multiple: log(2) / 2, axisValueGenerator: { ChartAxisValueDoubleLog(screenLocDouble: $0, formatter: integerFormatter, labelSettings: axisLabelSettings) }, addPaddingSegmentIfEdge: true)

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(labelsWidthY))

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxisLayer, yAxisLayer, innerFrame) = (coordsSpace.xAxisLayer, coordsSpace.yAxisLayer, coordsSpace.chartInnerFrame)

        // The dose area
        let lineModel = ChartLineModel(chartPoints: points.basal, lineColor: colors.doseTint, lineWidth: 2, animDuration: 0, animDelay: 0)
        let doseLine = ChartPointsLineLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, lineModels: [lineModel])

        let doseArea = ChartPointsFillsLayer(
            xAxis: xAxisLayer.axis,
            yAxis: yAxisLayer.axis,
            fills: [ChartPointsFill(
                chartPoints: points.basalFill,
                fillColor: colors.doseTint.withAlphaComponent(0.5),
                createContainerPoints: false
            )]
        )

        let bolusLayer: ChartPointsScatterDownTrianglesLayer<ChartPoint>?
        
        if points.bolus.count > 0 {
            bolusLayer = ChartPointsScatterDownTrianglesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, chartPoints: points.bolus, displayDelay: 0, itemSize: CGSize(width: 12, height: 12), itemFillColor: colors.doseTint)
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
                chartPoints: points.highlight,
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
    
    private func generateDosePoints(startDate: Date) -> DosePointsCache {
        
        guard pointsCache == nil else {
            return pointsCache!
        }
        
        let dateFormatter = DateFormatter(timeStyle: .short)
        let doseFormatter = NumberFormatter.dose

        var basalPoints = [ChartPoint]()
        var basalFillPoints = [ChartPoint]()
        var bolusPoints = [ChartPoint]()
        var highlightPoints = [ChartPoint]()
        
        for entry in doseEntries {
            let time = entry.endDate.timeIntervalSince(entry.startDate)

            if entry.type == .bolus && entry.netBasalUnits > 0 {
                let x = ChartAxisValueDate(date: entry.startDate, formatter: dateFormatter)
                let y = ChartAxisValueDoubleLog(actualDouble: entry.unitsInDeliverableIncrements, unitString: "U", formatter: doseFormatter)

                let point = ChartPoint(x: x, y: y)
                bolusPoints.append(point)
                highlightPoints.append(point)
            } else if time > 0 {
                // TODO: Display the DateInterval
                let startX = ChartAxisValueDate(date: max(startDate, entry.startDate), formatter: dateFormatter)
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
                
                basalFillPoints += [ChartPoint(x: startX, y: zero)] + valuePoints + [ChartPoint(x: endX, y: zero)]
                
                if entry.startDate > startDate {
                    basalPoints += [ChartPoint(x: startX, y: zero)]
                }
                basalPoints += valuePoints + [ChartPoint(x: endX, y: zero)]

                highlightPoints += valuePoints
            }
        }
        
        let pointsCache = DosePointsCache(basal: basalPoints, basalFill: basalFillPoints, bolus: bolusPoints, highlight: highlightPoints)
        self.pointsCache = pointsCache
        return pointsCache
    }
}
