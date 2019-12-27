//
//  Chart.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopCore
import LoopKit
import SwiftCharts
import os.log


open class ChartsManager {
    private let log = OSLog(category: "ChartsManager")

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        let dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current)!
        let isAmPmTimeFormat = dateFormat.firstIndex(of: "a") != nil
        formatter.dateFormat = isAmPmTimeFormat
            ? "h a"
            : "H:mm"
        return formatter
    }()

    public init(colors: ChartColorPalette, settings: ChartSettings, charts: [ChartProviding], traitCollection: UITraitCollection) {
        self.colors = colors
        self.chartSettings = settings
        self.charts = charts
        self.traitCollection = traitCollection
        self.chartsCache = Array(repeating: nil, count: charts.count)

        axisLabelSettings = ChartLabelSettings(
            font: .systemFont(ofSize: 14),  // caption1, but hard-coded until axis can scale with type preference
            fontColor: colors.axisLabel
        )

        guideLinesLayerSettings = ChartGuideLinesLayerSettings(linesColor: colors.grid)
    }

    // MARK: - Configuration

    private let colors: ChartColorPalette

    private let chartSettings: ChartSettings

    private let labelsWidthY: CGFloat = 30

    public let charts: [ChartProviding]

    /// The amount of horizontal space reserved for fixed margins
    public var fixedHorizontalMargin: CGFloat {
        return chartSettings.leading + chartSettings.trailing + labelsWidthY + chartSettings.labelsToAxisSpacingY
    }

    private let axisLabelSettings: ChartLabelSettings

    private let guideLinesLayerSettings: ChartGuideLinesLayerSettings

    public var gestureRecognizer: UIGestureRecognizer?

    // MARK: - UITraitEnvironment

    public var traitCollection: UITraitCollection

    public func didReceiveMemoryWarning() {
        log.info("Purging chart data in response to memory warning")

        for chart in charts {
            chart.didReceiveMemoryWarning()
        }

        xAxisValues = nil
    }

    // MARK: - Data

    /// The earliest date on the X-axis
    public var startDate = Date() {
        didSet {
            if startDate != oldValue {
                log.debug("New chart start date: %@", String(describing: startDate))
                xAxisValues = nil

                // Set a new minimum end date
                endDate = startDate.addingTimeInterval(.hours(3))
            }
        }
    }

    /// The latest date on the X-axis
    private var endDate = Date() {
        didSet {
            if endDate != oldValue {
                log.debug("New chart end date: %@", String(describing: endDate))
                xAxisValues = nil
            }
        }
    }

    /// The latest allowed date on the X-axis
    public var maxEndDate = Date.distantFuture {
        didSet {
            if maxEndDate != oldValue {
                log.debug("New chart max end date: %@", String(describing: maxEndDate))
            }

            endDate = min(endDate, maxEndDate)
        }
    }

    /// Updates the endDate using a new candidate date
    /// 
    /// Dates are rounded up to the next hour.
    ///
    /// - Parameter date: The new candidate date
    public func updateEndDate(_ date: Date) {
        if date > endDate {
            let components = DateComponents(minute: 0)
            endDate = min(
                maxEndDate,
                Calendar.current.nextDate(
                    after: date,
                    matching: components,
                    matchingPolicy: .strict,
                    direction: .forward
                ) ?? date
            )
        }
    }

    // MARK: - State

    private var xAxisValues: [ChartAxisValue]? {
        didSet {
            if let xAxisValues = xAxisValues, xAxisValues.count > 1 {
                xAxisModel = ChartAxisModel(axisValues: xAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(20))
            } else {
                xAxisModel = nil
            }

            chartsCache.replaceAllElements(with: nil)
        }
    }

    private var xAxisModel: ChartAxisModel?

    private var chartsCache: [Chart?]

    // MARK: - Generators

    public func chart(atIndex index: Int, frame: CGRect) -> Chart? {
        if let chart = chartsCache[index], chart.frame != frame {
            chartsCache[index] = nil
        }

        if chartsCache[index] == nil, let xAxisModel = xAxisModel, let xAxisValues = xAxisValues {
            chartsCache[index] = charts[index].generate(withFrame: frame, xAxisModel: xAxisModel, xAxisValues: xAxisValues, axisLabelSettings: axisLabelSettings, guideLinesLayerSettings: guideLinesLayerSettings, colors: colors, chartSettings: chartSettings, labelsWidthY: labelsWidthY, gestureRecognizer: gestureRecognizer, traitCollection: traitCollection)
        }

        return chartsCache[index]
    }

    public func invalidateChart(atIndex index: Int) {
        chartsCache[index] = nil
    }

    // MARK: - Shared Axis

    private func generateXAxisValues() {
        if let endDate = charts.compactMap({ $0.endDate }).max() {
            updateEndDate(endDate)
        }

        let points = [
            ChartPoint(
                x: ChartAxisValueDate(date: startDate, formatter: timeFormatter),
                y: ChartAxisValue(scalar: 0)
            ),
            ChartPoint(
                x: ChartAxisValueDate(date: endDate, formatter: timeFormatter),
                y: ChartAxisValue(scalar: 0)
            )
        ]

        let segments = ceil(endDate.timeIntervalSince(startDate).hours)

        let xAxisValues = ChartAxisValuesStaticGenerator.generateXAxisValuesWithChartPoints(points,
            minSegmentCount: segments - 1,
            maxSegmentCount: segments + 1,
            multiple: TimeInterval(hours: 1),
            axisValueGenerator: {
                ChartAxisValueDate(
                    date: ChartAxisValueDate.dateFromScalar($0),
                    formatter: timeFormatter,
                    labelSettings: self.axisLabelSettings
                )
            },
            addPaddingSegmentIfEdge: false
        )
        xAxisValues.first?.hidden = true
        xAxisValues.last?.hidden = true

        self.xAxisValues = xAxisValues
    }

    /// Runs any necessary steps before rendering charts
    public func prerender() {
        if xAxisValues == nil {
            generateXAxisValues()
        }
    }
}

fileprivate extension Array {
    mutating func replaceAllElements(with element: Element) {
        self = Array(repeating: element, count: count)
    }
}


public protocol ChartProviding {
    /// Instructs the chart to clear its non-critical resources like caches
    func didReceiveMemoryWarning()

    /// The last date represented in the chart data
    var endDate: Date? { get }

    /// Creates a chart from the current data
    ///
    /// - Returns: A new chart object
    func generate(withFrame frame: CGRect,
        xAxisModel: ChartAxisModel,
        xAxisValues: [ChartAxisValue],
        axisLabelSettings: ChartLabelSettings,
        guideLinesLayerSettings: ChartGuideLinesLayerSettings,
        colors: ChartColorPalette,
        chartSettings: ChartSettings,
        labelsWidthY: CGFloat,
        gestureRecognizer: UIGestureRecognizer?,
        traitCollection: UITraitCollection
    ) -> Chart
}

