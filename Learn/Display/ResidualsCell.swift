//
//  ResidualsCell.swift
//  Learn
//
//  Created by Pete Schwamb on 4/18/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopUI
import SwiftCharts
import LoopKit
import HealthKit

class ResidualsCell: LessonCellProviding {

    let date: DateInterval
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
    
    private var glucoseChartCache: ChartPointsTouchHighlightLayerViewCache?
    
    private var chart: Chart?


    init(date: DateInterval, forecasts: [Forecast], colors: ChartColorPalette, settings: ChartSettings, glucoseUnit: HKUnit, dateFormatter: DateIntervalFormatter) {
        self.date = date
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
    
    func pointsFromResiduals(_ forecasts: [Forecast]) -> [ChartPoint] {
        let unitFormatter = QuantityFormatter()
        unitFormatter.unitStyle = .short
        unitFormatter.setPreferredNumberFormatter(for: glucoseUnit)
        let unitString = unitFormatter.string(from: glucoseUnit)
        
        var points = [ChartPoint]()

        for forecast in forecasts {
            let forecastPoints: [ChartPoint] = forecast.residuals.map {
                return ChartPoint(
                    x: ChartAxisValueDouble($0.startDate.timeIntervalSince(forecast.startTime).hours),
                    y: ChartAxisValueDoubleUnit($0.quantity.doubleValue(for: glucoseUnit), unitString: unitString, formatter: unitFormatter.numberFormatter)
                )
            }
            points.append(contentsOf: forecastPoints)
        }
        return points
    }
    
    public func generateChart(withFrame frame: CGRect) -> Chart?
    {
        
        guard let xAxisModel = xAxisModel, let xAxisValues = xAxisValues else {
            return nil
        }
        
        let chartPoints = pointsFromResiduals(forecasts)
        
        let yAxisValues = ChartAxisValuesStaticGenerator.generateYAxisValuesWithChartPoints(chartPoints,
            minSegmentCount: 2,
            maxSegmentCount: 4,
            multiple: 2,
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
        let circles = ChartPointsScatterCirclesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, chartPoints: chartPoints, displayDelay: 0, itemSize: CGSize(width: 4, height: 4), itemFillColor: UIColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.1), optimized: true)

        
        if gestureRecognizer != nil {
            glucoseChartCache = ChartPointsTouchHighlightLayerViewCache(
                xAxisLayer: xAxisLayer,
                yAxisLayer: yAxisLayer,
                axisLabelSettings: axisLabelSettings,
                chartPoints: chartPoints,
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
        
        let lastResidualOffset: TimeInterval = forecasts.map { (forecast) -> TimeInterval in
            return forecast.residuals.map { $0.startDate.timeIntervalSince(forecast.startTime) }.max() ?? 0
        }.max() ?? 0
        
        let points = [
            ChartPoint(
                x: ChartAxisValueDouble(0),
                y: ChartAxisValue(scalar: 0)
            ),
            ChartPoint(
                x: ChartAxisValueDouble(lastResidualOffset),
                y: ChartAxisValue(scalar: 0)
            )
        ]
        
        let formatter = NumberFormatter()

        let xAxisValues = ChartAxisValuesStaticGenerator.generateXAxisValuesWithChartPoints(points,
            minSegmentCount: 2,
            maxSegmentCount: 12,
            multiple: TimeInterval(hours: 1),
            axisValueGenerator: {
                ChartAxisValueDoubleUnit(TimeInterval($0).hours, unitString: HKUnit.hour().unitString, formatter: formatter)
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
        cell.subtitleLabel?.text = "Residuals"

        return cell
    }
}
