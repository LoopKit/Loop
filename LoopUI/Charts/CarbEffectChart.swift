//
//  CarbEffectChart.swift
//  LoopUI
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import SwiftCharts

public class CarbEffectChart: GlucoseChart, ChartProviding {
    /// The chart points for expected carb effect velocity
    public private(set) var carbEffectPoints: [ChartPoint] = [] {
        didSet {
            // don't extend the end date for carb effects
        }
    }

    /// The chart points for observed insulin counteraction effect velocity
    public private(set) var insulinCounteractionEffectPoints: [ChartPoint] = [] {
        didSet {
            // Extend 1 hour past the seen effect to ensure some future prediction is displayed
            if let lastDate = insulinCounteractionEffectPoints.last?.x as? ChartAxisValueDate {
                endDate = lastDate.date.addingTimeInterval(.hours(1))
            }
        }
    }

    /// The chart points used for selection in the carb effect chart
    public private(set) var allCarbEffectPoints: [ChartPoint] = []

    public private(set) var endDate: Date?

    private lazy var dateFormatter = DateFormatter(timeStyle: .short)
    private lazy var decimalFormatter = NumberFormatter.dose

    private var carbEffectChartCache: ChartPointsTouchHighlightLayerViewCache?
}

extension CarbEffectChart {
    public func didReceiveMemoryWarning() {
        carbEffectPoints = []
        insulinCounteractionEffectPoints = []
        allCarbEffectPoints = []

        carbEffectChartCache = nil
    }

    public func generate(withFrame frame: CGRect, xAxisModel: ChartAxisModel, xAxisValues: [ChartAxisValue], axisLabelSettings: ChartLabelSettings, guideLinesLayerSettings: ChartGuideLinesLayerSettings, colors: ChartColorPalette, chartSettings: ChartSettings, labelsWidthY: CGFloat, gestureRecognizer: UIGestureRecognizer?, traitCollection: UITraitCollection) -> Chart
    {
        /// The minimum range to display for carb effect values.
        let carbEffectDisplayRangePoints: [ChartPoint] = [0, glucoseUnit.chartableIncrement].map {
            return ChartPoint(
                x: ChartAxisValue(scalar: 0),
                y: ChartAxisValueDouble($0)
            )
        }

        let yAxisValues = ChartAxisValuesStaticGenerator.generateYAxisValuesWithChartPoints(carbEffectPoints + allCarbEffectPoints + carbEffectDisplayRangePoints,
            minSegmentCount: 2,
            maxSegmentCount: 4,
            multiple: glucoseUnit.chartableIncrement / 2,
            axisValueGenerator: {
                ChartAxisValueDouble($0, labelSettings: axisLabelSettings)
            },
            addPaddingSegmentIfEdge: false
        )

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(labelsWidthY))

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxisLayer, yAxisLayer, innerFrame) = (coordsSpace.xAxisLayer, coordsSpace.yAxisLayer, coordsSpace.chartInnerFrame)

        let carbFillColor = UIColor.COBTintColor.withAlphaComponent(0.8)
        let carbBlendMode: CGBlendMode
        if #available(iOSApplicationExtension 13.0, iOS 13.0, *) {
            switch traitCollection.userInterfaceStyle {
            case .dark:
                carbBlendMode = .plusLighter
            case .light, .unspecified:
                carbBlendMode = .plusDarker
            @unknown default:
                carbBlendMode = .plusDarker
            }
        } else {
            carbBlendMode = .colorBurn
        }

        // Carb effect
        let effectsLayer = ChartPointsFillsLayer(
            xAxis: xAxisLayer.axis,
            yAxis: yAxisLayer.axis,
            fills: [
                ChartPointsFill(chartPoints: carbEffectPoints, fillColor: UIColor.secondaryLabelColor.withAlphaComponent(0.5)),
                ChartPointsFill(chartPoints: insulinCounteractionEffectPoints, fillColor: carbFillColor, blendMode: carbBlendMode)
            ]
        )

        // Grid lines
        let gridLayer = ChartGuideLinesForValuesLayer(
            xAxis: xAxisLayer.axis,
            yAxis: yAxisLayer.axis,
            settings: guideLinesLayerSettings,
            axisValuesX: Array(xAxisValues.dropFirst().dropLast()),
            axisValuesY: yAxisValues
        )

        // 0-line
        let dummyZeroChartPoint = ChartPoint(x: ChartAxisValueDouble(0), y: ChartAxisValueDouble(0))
        let zeroGuidelineLayer = ChartPointsViewsLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, chartPoints: [dummyZeroChartPoint], viewGenerator: {(chartPointModel, layer, chart) -> UIView? in
            let width: CGFloat = 1
            let viewFrame = CGRect(x: chart.contentView.bounds.minX, y: chartPointModel.screenLoc.y - width / 2, width: chart.contentView.bounds.size.width, height: width)

            let v = UIView(frame: viewFrame)
            v.layer.backgroundColor = carbFillColor.cgColor
            return v
        })

        if gestureRecognizer != nil {
            carbEffectChartCache = ChartPointsTouchHighlightLayerViewCache(
                xAxisLayer: xAxisLayer,
                yAxisLayer: yAxisLayer,
                axisLabelSettings: axisLabelSettings,
                chartPoints: allCarbEffectPoints,
                tintColor: UIColor.COBTintColor,
                gestureRecognizer: gestureRecognizer
            )
        }

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxisLayer,
            yAxisLayer,
            zeroGuidelineLayer,
            carbEffectChartCache?.highlightLayer,
            effectsLayer
        ]

        return Chart(
            frame: frame,
            innerFrame: innerFrame,
            settings: chartSettings,
            layers: layers.compactMap { $0 }
        )
    }
}

extension CarbEffectChart {
    /// Convert an array of GlucoseEffects (as glucose values) into glucose effect velocity (glucose/min) for charting
    ///
    /// - Parameter effects: A timeline of glucose values representing glucose change
    public func setCarbEffects(_ effects: [GlucoseEffect]) {
        let unit = glucoseUnit.unitDivided(by: .minute())
        let unitString = unit.unitString

        var lastDate = effects.first?.endDate
        var lastValue = effects.first?.quantity.doubleValue(for: glucoseUnit)
        let minuteInterval = 5.0

        var carbEffectPoints = [ChartPoint]()

        let zero = ChartAxisValueInt(0)

        for effect in effects.dropFirst() {
            let value = effect.quantity.doubleValue(for: glucoseUnit)
            let valuePerMinute = (value - lastValue!) / minuteInterval
            lastValue = value

            let startX = ChartAxisValueDate(date: lastDate!, formatter: dateFormatter)
            let endX = ChartAxisValueDate(date: effect.endDate, formatter: dateFormatter)
            lastDate = effect.endDate

            let valueY = ChartAxisValueDoubleUnit(valuePerMinute, unitString: unitString, formatter: decimalFormatter)

            carbEffectPoints += [
                ChartPoint(x: startX, y: zero),
                ChartPoint(x: startX, y: valueY),
                ChartPoint(x: endX, y: valueY),
                ChartPoint(x: endX, y: zero)
            ]
        }

        self.carbEffectPoints = carbEffectPoints
    }

    /// Charts glucose effect velocity
    ///
    /// - Parameter effects: A timeline of glucose velocity values
    public func setInsulinCounteractionEffects(_ effects: [GlucoseEffectVelocity]) {
        let unit = glucoseUnit.unitDivided(by: .minute())
        let unitString = String(format: NSLocalizedString("%1$@/min", comment: "Format string describing glucose units per minute (1: glucose unit string)"), glucoseUnit.localizedShortUnitString)

        var insulinCounteractionEffectPoints: [ChartPoint] = []
        var allCarbEffectPoints: [ChartPoint] = []

        let zero = ChartAxisValueInt(0)

        for effect in effects {
            let startX = ChartAxisValueDate(date: effect.startDate, formatter: dateFormatter)
            let endX = ChartAxisValueDate(date: effect.endDate, formatter: dateFormatter)
            let value = ChartAxisValueDoubleUnit(effect.quantity.doubleValue(for: unit), unitString: unitString, formatter: decimalFormatter)

            guard value.scalar != 0 else {
                continue
            }

            let valuePoint = ChartPoint(x: endX, y: value)

            insulinCounteractionEffectPoints += [
                ChartPoint(x: startX, y: zero),
                ChartPoint(x: startX, y: value),
                valuePoint,
                ChartPoint(x: endX, y: zero)
            ]

            allCarbEffectPoints.append(valuePoint)
        }

        self.insulinCounteractionEffectPoints = insulinCounteractionEffectPoints
        self.allCarbEffectPoints = allCarbEffectPoints
    }
}
