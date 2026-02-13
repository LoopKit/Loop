//
//  LoopInsights_AGPChartView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit

/// Ambulatory Glucose Profile chart: renders percentile bands (p10/p25/p50/p75/p90)
/// as layered SwiftUI Paths over a 24-hour x-axis. iOS 15 compatible (no Charts framework).
struct LoopInsights_AGPChartView: View {

    let glucoseSamples: [StoredGlucoseSample]

    /// Computed AGP data points (48 points, every 30 min)
    private var agpData: [LoopInsightsAGPDataPoint] {
        Self.computeAGP(from: glucoseSamples)
    }

    private let targetLow: Double = 70
    private let targetHigh: Double = 180
    private let chartMinY: Double = 40
    private let chartMaxY: Double = 300
    private let leftMargin: Double = 28
    private let rightMargin: Double = 8
    private let topMargin: Double = 8
    private let bottomMargin: Double = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(NSLocalizedString("Ambulatory Glucose Profile", comment: "LoopInsights AGP chart title"))
                .font(.subheadline.weight(.semibold))

            if agpData.isEmpty {
                Text(NSLocalizedString("Not enough data for AGP chart", comment: "LoopInsights AGP no data"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack(alignment: .topLeading) {
                        // Target range band (70-180)
                        targetRangePath(width: w, height: h)
                            .fill(Color.green.opacity(0.12))

                        // Y-axis grid lines at target boundaries
                        targetGridLines(width: w, height: h)

                        // P10-P90 band (lightest)
                        percentileBand(data: agpData, lowerKey: \.p10, upperKey: \.p90, width: w, height: h)
                            .fill(Color.blue.opacity(0.12))

                        // P25-P75 band (medium)
                        percentileBand(data: agpData, lowerKey: \.p25, upperKey: \.p75, width: w, height: h)
                            .fill(Color.blue.opacity(0.25))

                        // P50 median line (bold)
                        medianLine(data: agpData, width: w, height: h)
                            .stroke(Color.blue, lineWidth: 2.5)

                        // Y-axis labels
                        yAxisLabels(width: w, height: h)

                        // X-axis labels
                        xAxisLabels(width: w, height: h)
                    }
                }
                .frame(height: 180)

                // Legend
                legendView
            }
        }
    }

    // MARK: - Legend

    private var legendView: some View {
        HStack(spacing: 0) {
            legendItem(color: Color.green.opacity(0.3), label: "70-180")
            Spacer()
            legendItem(color: Color.blue.opacity(0.12), label: "P10-P90")
            Spacer()
            legendItem(color: Color.blue.opacity(0.25), label: "P25-P75")
            Spacer()
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.blue)
                    .frame(width: 14, height: 2.5)
                Text("Median")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Chart Components

    /// Target range as a proper Path that fills the correct Y band
    private func targetRangePath(width: Double, height: Double) -> Path {
        let plotLeft = leftMargin
        let plotRight = width - rightMargin
        let topY = yPosition(for: targetHigh, height: height)
        let bottomY = yPosition(for: targetLow, height: height)

        var path = Path()
        path.addRect(CGRect(
            x: plotLeft,
            y: topY,
            width: plotRight - plotLeft,
            height: bottomY - topY
        ))
        return path
    }

    /// Dashed grid lines at 70 and 180
    private func targetGridLines(width: Double, height: Double) -> some View {
        let plotLeft = leftMargin
        let plotRight = width - rightMargin
        let y70 = yPosition(for: targetLow, height: height)
        let y180 = yPosition(for: targetHigh, height: height)

        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: plotLeft, y: y70))
                p.addLine(to: CGPoint(x: plotRight, y: y70))
            }
            .stroke(Color.green.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

            Path { p in
                p.move(to: CGPoint(x: plotLeft, y: y180))
                p.addLine(to: CGPoint(x: plotRight, y: y180))
            }
            .stroke(Color.green.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
        }
    }

    private func percentileBand<L: KeyPath<LoopInsightsAGPDataPoint, Double>, U: KeyPath<LoopInsightsAGPDataPoint, Double>>(
        data: [LoopInsightsAGPDataPoint],
        lowerKey: L,
        upperKey: U,
        width: Double,
        height: Double
    ) -> Path {
        var path = Path()
        guard !data.isEmpty else { return path }

        // Upper line (left to right)
        let firstX = xPosition(for: data[0].minuteOfDay, width: width)
        let firstUpperY = yPosition(for: data[0][keyPath: upperKey], height: height)
        path.move(to: CGPoint(x: firstX, y: firstUpperY))

        for point in data.dropFirst() {
            let x = xPosition(for: point.minuteOfDay, width: width)
            let y = yPosition(for: point[keyPath: upperKey], height: height)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Lower line (right to left)
        for point in data.reversed() {
            let x = xPosition(for: point.minuteOfDay, width: width)
            let y = yPosition(for: point[keyPath: lowerKey], height: height)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }

    private func medianLine(data: [LoopInsightsAGPDataPoint], width: Double, height: Double) -> Path {
        var path = Path()
        guard let first = data.first else { return path }

        path.move(to: CGPoint(
            x: xPosition(for: first.minuteOfDay, width: width),
            y: yPosition(for: first.p50, height: height)
        ))

        for point in data.dropFirst() {
            path.addLine(to: CGPoint(
                x: xPosition(for: point.minuteOfDay, width: width),
                y: yPosition(for: point.p50, height: height)
            ))
        }

        return path
    }

    private func xAxisLabels(width: Double, height: Double) -> some View {
        let hours = [0, 3, 6, 9, 12, 15, 18, 21]
        return ZStack {
            ForEach(hours, id: \.self) { hour in
                let x = xPosition(for: hour * 60, width: width)
                Text(formatHour(hour))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .position(x: x, y: height - 4)
            }
        }
    }

    private func yAxisLabels(width: Double, height: Double) -> some View {
        let values: [Double] = [70, 120, 180, 250]
        return ZStack {
            ForEach(values, id: \.self) { value in
                let y = yPosition(for: value, height: height)
                Text("\(Int(value))")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .position(x: 14, y: y)
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 10)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Coordinate Mapping

    private func xPosition(for minuteOfDay: Int, width: Double) -> Double {
        let plotWidth = width - leftMargin - rightMargin
        return leftMargin + (Double(minuteOfDay) / 1440.0) * plotWidth
    }

    private func yPosition(for glucose: Double, height: Double) -> Double {
        let plotHeight = height - topMargin - bottomMargin
        let clamped = max(chartMinY, min(chartMaxY, glucose))
        let fraction = (clamped - chartMinY) / (chartMaxY - chartMinY)
        return topMargin + (1 - fraction) * plotHeight  // Inverted Y axis
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12a" }
        if h < 12 { return "\(h)a" }
        if h == 12 { return "12p" }
        return "\(h - 12)p"
    }

    // MARK: - AGP Computation

    /// Compute AGP data: 48 time points (every 30 min), each with percentiles
    static func computeAGP(from samples: [StoredGlucoseSample]) -> [LoopInsightsAGPDataPoint] {
        guard !samples.isEmpty else { return [] }

        let calendar = Calendar.current

        // Bucket samples by 30-minute windows
        var buckets: [Int: [Double]] = [:]  // minuteOfDay → glucose values
        for sample in samples {
            let hour = calendar.component(.hour, from: sample.startDate)
            let minute = calendar.component(.minute, from: sample.startDate)
            let minuteOfDay = hour * 60 + minute
            let bucket = (minuteOfDay / 30) * 30  // Round to nearest 30-min
            buckets[bucket, default: []].append(
                sample.quantity.doubleValue(for: .milligramsPerDeciliter)
            )
        }

        var dataPoints: [LoopInsightsAGPDataPoint] = []
        for minuteOfDay in stride(from: 0, to: 1440, by: 30) {
            guard let values = buckets[minuteOfDay], values.count >= 3 else { continue }
            let sorted = values.sorted()
            let count = sorted.count

            dataPoints.append(LoopInsightsAGPDataPoint(
                minuteOfDay: minuteOfDay,
                p10: sorted[max(0, Int(Double(count) * 0.1))],
                p25: sorted[max(0, Int(Double(count) * 0.25))],
                p50: sorted[count / 2],
                p75: sorted[min(count - 1, Int(Double(count) * 0.75))],
                p90: sorted[min(count - 1, Int(Double(count) * 0.9))]
            ))
        }

        return dataPoints.sorted { $0.minuteOfDay < $1.minuteOfDay }
    }
}
