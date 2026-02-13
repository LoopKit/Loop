//
//  LoopInsights_AGPChartView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Dual-mode glucose chart:
/// - **AGP mode** (14-day lookback): Standard Ambulatory Glucose Profile — all days overlaid
///   into a single 24-hour view with percentile bands. Matches the IDC/AGP spec.
/// - **Profile mode** (all other periods): Glucose Profile — percentile bands spanning the
///   full analysis period with date-based X-axis.
/// iOS 15 compatible (no Charts framework).
struct LoopInsights_AGPChartView: View {

    /// P6: Accept pre-computed data instead of recomputing on every view body evaluation
    let agpData: [LoopInsightsAGPDataPoint]

    /// When true, renders as a standard 24-hour AGP overlay with hour labels.
    let isAGPMode: Bool

    @State private var showingAGPInfo = false
    @State private var showingProfileInfo = false

    private let targetLow: Double = 70
    private let targetHigh: Double = 180
    private let chartMinY: Double = 40
    private let chartMaxY: Double = 300
    private let leftMargin: Double = 28
    private let rightMargin: Double = 8
    private let topMargin: Double = 8
    private let bottomMargin: Double = 16

    /// Date range derived from the data
    private var startDate: Date { agpData.first?.date ?? Date() }
    private var endDate: Date { agpData.last?.date ?? Date() }
    private var totalDuration: TimeInterval { max(1, endDate.timeIntervalSince(startDate)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Title — AGP mode gets the proper name + info button
            if isAGPMode {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("Ambulatory Glucose Profile", comment: "LoopInsights AGP chart title"))
                        .font(.subheadline.weight(.semibold))
                    Button(action: { showingAGPInfo = true }) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("Glucose Profile", comment: "LoopInsights glucose profile chart title"))
                        .font(.subheadline.weight(.semibold))
                    Button(action: { showingProfileInfo = true }) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if agpData.isEmpty {
                Text(NSLocalizedString("Not enough data for glucose profile", comment: "LoopInsights AGP no data"))
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

                Spacer().frame(height: 6)

                // Legend
                legendView
            }
        }
        .alert(
            NSLocalizedString("Ambulatory Glucose Profile", comment: "LoopInsights AGP info alert title"),
            isPresented: $showingAGPInfo
        ) {
            Button(NSLocalizedString("OK", comment: "OK button")) {}
        } message: {
            Text(NSLocalizedString("AGP is a standardized reporting format developed by the International Diabetes Center. It overlays 14 days of CGM data into a single 24-hour view, displaying the median (P50), interquartile range (P25\u{2013}P75), and 10th/90th percentile bands.\n\nThis format lets you and your clinician spot recurring daily patterns \u{2014} like dawn phenomenon or post-meal spikes \u{2014} at a glance, using the same visual language across institutions.", comment: "LoopInsights AGP info alert message"))
        }
        .alert(
            NSLocalizedString("Glucose Profile", comment: "LoopInsights glucose profile info alert title"),
            isPresented: $showingProfileInfo
        ) {
            Button(NSLocalizedString("OK", comment: "OK button")) {}
        } message: {
            Text(NSLocalizedString("Glucose Profile displays your CGM data across the selected time period using percentile bands.\n\nThe median line (P50) shows your typical glucose at each point in time. The shaded bands show the interquartile range (P25\u{2013}P75) and the 10th/90th percentile spread, giving you a sense of variability.\n\nFor a standardized Ambulatory Glucose Profile (AGP) \u{2014} which overlays all days into a single 24-hour view \u{2014} select the 14-day lookback period.", comment: "LoopInsights glucose profile info alert message"))
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

        let firstX = xPosition(for: data[0].date, width: width)
        let firstUpperY = yPosition(for: data[0][keyPath: upperKey], height: height)
        path.move(to: CGPoint(x: firstX, y: firstUpperY))

        for point in data.dropFirst() {
            let x = xPosition(for: point.date, width: width)
            let y = yPosition(for: point[keyPath: upperKey], height: height)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        for point in data.reversed() {
            let x = xPosition(for: point.date, width: width)
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
            x: xPosition(for: first.date, width: width),
            y: yPosition(for: first.p50, height: height)
        ))

        for point in data.dropFirst() {
            path.addLine(to: CGPoint(
                x: xPosition(for: point.date, width: width),
                y: yPosition(for: point.p50, height: height)
            ))
        }

        return path
    }

    private func xAxisLabels(width: Double, height: Double) -> some View {
        let labels: [(date: Date, text: String)]
        if isAGPMode {
            labels = Self.generateAGPHourLabels(start: startDate, end: endDate)
        } else {
            labels = Self.generateDateLabels(start: startDate, end: endDate)
        }
        return ZStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                let x = xPosition(for: label.date, width: width)
                Text(label.text)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .position(x: x, y: height - 20)
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

    private func xPosition(for date: Date, width: Double) -> Double {
        let plotWidth = width - leftMargin - rightMargin
        let offset = date.timeIntervalSince(startDate)
        let fraction = offset / totalDuration
        return leftMargin + fraction * plotWidth
    }

    private func yPosition(for glucose: Double, height: Double) -> Double {
        let plotHeight = height - topMargin - bottomMargin
        let clamped = max(chartMinY, min(chartMaxY, glucose))
        let fraction = (clamped - chartMinY) / (chartMaxY - chartMinY)
        return topMargin + (1 - fraction) * plotHeight
    }

    // MARK: - X-Axis Label Generation

    /// Hour labels for AGP mode (24-hour overlay): 12a, 3a, 6a, … 9p
    private static func generateAGPHourLabels(start: Date, end: Date) -> [(date: Date, text: String)] {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return [] }

        let hours = [0, 3, 6, 9, 12, 15, 18, 21]
        return hours.map { hour in
            let fraction = Double(hour) / 24.0
            let date = start.addingTimeInterval(fraction * duration)
            return (date: date, text: formatHour(hour))
        }
    }

    /// Date labels for profile mode (multi-day time series)
    private static func generateDateLabels(start: Date, end: Date) -> [(date: Date, text: String)] {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return [] }

        let days = duration / 86400
        let labelCount: Int
        let formatter = DateFormatter()

        if days <= 4 {
            labelCount = 7
            formatter.dateFormat = "E ha"
        } else if days <= 10 {
            labelCount = 7
            formatter.dateFormat = "E M/d"
        } else if days <= 45 {
            labelCount = 6
            formatter.dateFormat = "M/d"
        } else {
            labelCount = 6
            formatter.dateFormat = "M/d"
        }

        var labels: [(date: Date, text: String)] = []
        for i in 0...labelCount {
            let fraction = Double(i) / Double(labelCount)
            let date = start.addingTimeInterval(fraction * duration)
            labels.append((date: date, text: formatter.string(from: date)))
        }
        return labels
    }

    private static func formatHour(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12a" }
        if h < 12 { return "\(h)a" }
        if h == 12 { return "12p" }
        return "\(h - 12)p"
    }

    // MARK: - Computation

    /// Compute standard AGP: overlay all days into a single 24-hour profile with 48 × 30-minute buckets.
    /// Used when the lookback period is 14 days.
    static func computeStandardAGP(from samples: [(date: Date, mgdl: Double)]) -> [LoopInsightsAGPDataPoint] {
        guard !samples.isEmpty else { return [] }

        let calendar = Calendar.current
        // Reference day: midnight of the earliest sample's date
        let refDay = calendar.startOfDay(for: samples.min(by: { $0.date < $1.date })!.date)

        var buckets: [Int: [Double]] = [:]
        for sample in samples {
            let hour = calendar.component(.hour, from: sample.date)
            let minute = calendar.component(.minute, from: sample.date)
            let minuteOfDay = hour * 60 + minute
            let bucket = (minuteOfDay / 30) * 30
            buckets[bucket, default: []].append(sample.mgdl)
        }

        var dataPoints: [LoopInsightsAGPDataPoint] = []
        for minuteOfDay in stride(from: 0, to: 1440, by: 30) {
            guard let values = buckets[minuteOfDay], values.count >= 3 else { continue }
            let s = values.sorted()
            let count = s.count
            let date = refDay.addingTimeInterval(Double(minuteOfDay) * 60 + 15 * 60) // bucket midpoint

            dataPoints.append(LoopInsightsAGPDataPoint(
                date: date,
                p10: s[max(0, Int(Double(count) * 0.1))],
                p25: s[max(0, Int(Double(count) * 0.25))],
                p50: s[count / 2],
                p75: s[min(count - 1, Int(Double(count) * 0.75))],
                p90: s[min(count - 1, Int(Double(count) * 0.9))]
            ))
        }

        return dataPoints.sorted { $0.date < $1.date }
    }

    /// Compute glucose profile: ~48 time-window buckets spanning the full sample period.
    /// Used for all lookback periods except 14 days.
    static func computeProfile(from samples: [(date: Date, mgdl: Double)]) -> [LoopInsightsAGPDataPoint] {
        guard samples.count >= 3 else { return [] }

        let sorted = samples.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else { return [] }

        let totalDuration = last.date.timeIntervalSince(first.date)
        guard totalDuration > 0 else { return [] }

        let bucketCount = 48
        let bucketDuration = totalDuration / Double(bucketCount)

        var buckets: [[Double]] = Array(repeating: [], count: bucketCount)
        for sample in sorted {
            let offset = sample.date.timeIntervalSince(first.date)
            let index = min(Int(offset / bucketDuration), bucketCount - 1)
            buckets[index].append(sample.mgdl)
        }

        var dataPoints: [LoopInsightsAGPDataPoint] = []
        for i in 0..<bucketCount {
            let values = buckets[i]
            guard values.count >= 3 else { continue }
            let s = values.sorted()
            let count = s.count
            let midDate = first.date.addingTimeInterval((Double(i) + 0.5) * bucketDuration)

            dataPoints.append(LoopInsightsAGPDataPoint(
                date: midDate,
                p10: s[max(0, Int(Double(count) * 0.1))],
                p25: s[max(0, Int(Double(count) * 0.25))],
                p50: s[count / 2],
                p75: s[min(count - 1, Int(Double(count) * 0.75))],
                p90: s[min(count - 1, Int(Double(count) * 0.9))]
            ))
        }

        return dataPoints
    }
}
