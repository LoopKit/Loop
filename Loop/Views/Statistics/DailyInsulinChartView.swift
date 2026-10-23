//
//  DailyInsulinChartView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Charts
import LoopKitUI

/// Insulin delivered per calendar day, stacked by basal, automatic bolus and manual bolus,
/// with the average as a dashed line.
struct DailyInsulinChartView: View {
    let days: [DailyInsulinDelivery]
    let average: Double?

    @Environment(\.insulinTintColor) private var insulinTintColor

    private enum Part: CaseIterable {
        case basal, automaticBolus, manualBolus

        var name: String {
            switch self {
            case .basal:
                return NSLocalizedString("Basal", comment: "Daily insulin chart legend for basal delivery")
            case .automaticBolus:
                return NSLocalizedString("Automatic Bolus", comment: "Daily insulin chart legend for automatic boluses")
            case .manualBolus:
                return NSLocalizedString("Manual Bolus", comment: "Daily insulin chart legend for manual boluses")
            }
        }

        func units(_ totals: InsulinDeliveryTotals) -> Double {
            switch self {
            case .basal: return totals.basal
            case .automaticBolus: return totals.automaticBolus
            case .manualBolus: return totals.manualBolus
            }
        }
    }

    private var labelStride: Int {
        switch days.count {
        case ...8: return 1
        case ...15: return 2
        case ...31: return 7
        default: return 14
        }
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                ForEach(Part.allCases, id: \.self) { part in
                    BarMark(
                        x: .value("Day", day.start, unit: .day),
                        y: .value("Units", part.units(day.totals))
                    )
                    .foregroundStyle(by: .value("Delivery", part.name))
                }
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .chartForegroundStyleScale([
            Part.basal.name: insulinTintColor.opacity(0.35),
            Part.automaticBolus.name: insulinTintColor.opacity(0.65),
            Part.manualBolus.name: insulinTintColor,
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: labelStride)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .accessibilityLabel(Text(NSLocalizedString("Insulin delivered per day", comment: "Accessibility label for the daily insulin chart")))
    }
}
