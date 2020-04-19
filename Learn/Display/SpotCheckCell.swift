//
//  ForecastErrorCell.swift
//  Learn
//
//  Created by Pete Schwamb on 2/23/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopUI
import SwiftCharts
import LoopKit
import HealthKit


class SpotCheckCell: LessonCellProviding {

    let date: DateInterval
    let actualGlucose: [GlucoseValue]
    let forecasts: [Forecast]
    let glucoseUnit: HKUnit
    let dateFormatter: DateIntervalFormatter
    
    private let colors: ChartColorPalette
    
    private let axisLabelSettings: ChartLabelSettings

    private let guideLinesLayerSettings: ChartGuideLinesLayerSettings
    
    private let chartSettings: ChartSettings
    
    private let labelsWidthY: CGFloat = 30
    
    public var gestureRecognizer: UIGestureRecognizer?
    
    private var xAxisValues: [ChartAxisValue]? {
        didSet {
            if let xAxisValues = xAxisValues, xAxisValues.count > 1 {
                xAxisModel = ChartAxisModel(axisValues: xAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(20))
            } else {
                xAxisModel = nil
            }
        }
    }
    
    private var xAxisModel: ChartAxisModel?
    
    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        let dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current)!
        let isAmPmTimeFormat = dateFormat.firstIndex(of: "a") != nil
        formatter.dateFormat = isAmPmTimeFormat
            ? "h a"
            : "H:mm"
        return formatter
    }()

    
    private var glucoseChartCache: ChartPointsTouchHighlightLayerViewCache?
    
    private var chart: Chart?


    init(date: DateInterval, actualGlucose: [GlucoseValue], forecasts: [Forecast], colors: ChartColorPalette, settings: ChartSettings, glucoseUnit: HKUnit, dateFormatter: DateIntervalFormatter) {
        self.date = date
        self.actualGlucose = actualGlucose
        self.forecasts = forecasts
        self.colors = colors
        self.chartSettings = settings
        self.glucoseUnit = glucoseUnit
        self.dateFormatter = dateFormatter
        
        axisLabelSettings = ChartLabelSettings(
            font: .systemFont(ofSize: 14),  // caption1, but hard-coded until axis can scale with type preference
            fontColor: colors.axisLabel
        )

        guideLinesLayerSettings = ChartGuideLinesLayerSettings(linesColor: colors.grid)
        
        generateXAxisValues()
    }
    
    func glucosePointsFromValues(_ glucoseValues: [GlucoseValue]) -> [ChartPoint] {
        let unitFormatter = QuantityFormatter()
        unitFormatter.unitStyle = .short
        unitFormatter.setPreferredNumberFormatter(for: glucoseUnit)
        let unitString = unitFormatter.string(from: glucoseUnit)
        let dateFormatter = DateFormatter(timeStyle: .short)

        return glucoseValues.map {
            return ChartPoint(
                x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: glucoseUnit), unitString: unitString, formatter: unitFormatter.numberFormatter)
            )
        }
    }
    
    public func generateChart(withFrame frame: CGRect) -> Chart?
    {
        
        guard let xAxisModel = xAxisModel, let xAxisValues = xAxisValues else {
            return nil
        }

        let glucosePoints = glucosePointsFromValues(actualGlucose)
        
        let points = glucosePoints

        let yAxisValues = ChartAxisValuesStaticGenerator.generateYAxisValuesWithChartPoints(points,
            minSegmentCount: 2,
            maxSegmentCount: 4,
            multiple: glucoseUnit.chartableIncrement * 25,
            axisValueGenerator: {
                ChartAxisValueDouble($0, labelSettings: axisLabelSettings)
            },
            addPaddingSegmentIfEdge: false
        )

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(labelsWidthY))

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxisLayer, yAxisLayer, innerFrame) = (coordsSpace.xAxisLayer, coordsSpace.yAxisLayer, coordsSpace.chartInnerFrame)


        // Grid lines
        let gridLayer = ChartGuideLinesForValuesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, settings: guideLinesLayerSettings, axisValuesX: Array(xAxisValues.dropFirst().dropLast()), axisValuesY: yAxisValues)

        // Glucose
        let circles = ChartPointsScatterCirclesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, chartPoints: glucosePoints, displayDelay: 0, itemSize: CGSize(width: 4, height: 4), itemFillColor: colors.glucoseTint, optimized: true)

        var prediction: ChartLayer?
        
        let selectedForecast = forecasts[forecasts.count / 2]
        
        let predictedGlucosePoints = glucosePointsFromValues(selectedForecast.predictedGlucose)

        if predictedGlucosePoints.count > 1 {
            let lineColor = colors.glucoseTint

            let lineModel = ChartLineModel.predictionLine(
                points: predictedGlucosePoints,
                color: lineColor,
                width: 1
            )

            prediction = ChartPointsLineLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, lineModels: [lineModel])
        }
        
        if gestureRecognizer != nil {
            glucoseChartCache = ChartPointsTouchHighlightLayerViewCache(
                xAxisLayer: xAxisLayer,
                yAxisLayer: yAxisLayer,
                axisLabelSettings: axisLabelSettings,
                chartPoints: glucosePoints + predictedGlucosePoints,
                tintColor: colors.glucoseTint,
                gestureRecognizer: gestureRecognizer
            )
        }

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxisLayer,
            yAxisLayer,
            glucoseChartCache?.highlightLayer,
            circles,
            prediction,
        ]

        self.chart = Chart(
            frame: frame,
            innerFrame: innerFrame,
            settings: chartSettings,
            layers: layers.compactMap { $0 }
        )
        
        return self.chart
    }
    
    private func generateXAxisValues() {
        
        let points = [
            ChartPoint(
                x: ChartAxisValueDate(date: date.start, formatter: self.timeFormatter),
                y: ChartAxisValue(scalar: 0)
            ),
            ChartPoint(
                x: ChartAxisValueDate(date: date.end, formatter: self.timeFormatter),
                y: ChartAxisValue(scalar: 0)
            )
        ]

        let xAxisValues = ChartAxisValuesStaticGenerator.generateXAxisValuesWithChartPoints(points,
            minSegmentCount: 2,
            maxSegmentCount: 12,
            multiple: TimeInterval(hours: 3),
            axisValueGenerator: {
                ChartAxisValueDate(
                    date: ChartAxisValueDate.dateFromScalar($0),
                    formatter: timeFormatter,
                    labelSettings: axisLabelSettings
                )
            },
            addPaddingSegmentIfEdge: false
        )
        xAxisValues.first?.hidden = true
        xAxisValues.last?.hidden = true

        self.xAxisValues = xAxisValues
    }

    func registerCell(for tableView: UITableView) {
        tableView.register(UINib(nibName: "ChartTableViewCell", bundle: nil), forCellReuseIdentifier: ChartTableViewCell.className)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChartTableViewCell.className) as! ChartTableViewCell

        cell.chartContentView.chartGenerator = { [weak self] (frame) in
            return self?.generateChart(withFrame: frame)?.view
        }

        cell.titleLabel?.text = dateFormatter.string(from: date)
        cell.subtitleLabel?.text = "Forecast Spot Check"

        return cell
    }
}
