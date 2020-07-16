//
//  InsulinModelChartView.swift
//  Loop
//
//  Created by Michael Pangburn on 7/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopUI


struct InsulinModelChartView: UIViewRepresentable {
    let chartManager: ChartsManager
    var glucoseUnit: HKUnit
    var selectedInsulinModelValues: [GlucoseValue]
    var unselectedInsulinModelValues: [[GlucoseValue]]
    var glucoseDisplayRange: ClosedRange<HKQuantity>

    func makeUIView(context: Context) -> ChartContainerView {
        let view = ChartContainerView()
        view.chartGenerator = { [chartManager] frame in
            chartManager.chart(atIndex: 0, frame: frame)?.view
        }
        return view
    }

    func updateUIView(_ chartContainerView: ChartContainerView, context: Context) {
        chartManager.invalidateChart(atIndex: 0)
        insulinModelChart.glucoseUnit = glucoseUnit
        insulinModelChart.setSelectedInsulinModelValues(selectedInsulinModelValues)
        insulinModelChart.setUnselectedInsulinModelValues(unselectedInsulinModelValues)
        insulinModelChart.glucoseDisplayRange = glucoseDisplayRange
        chartManager.prerender()
        chartContainerView.reloadChart()
    }

    private var insulinModelChart: InsulinModelChart {
        guard chartManager.charts.count == 1, let insulinModelChart = chartManager.charts.first as? InsulinModelChart else {
            fatalError("Expected exactly one insulin model chart in ChartsManager")
        }

        return insulinModelChart
    }
}
