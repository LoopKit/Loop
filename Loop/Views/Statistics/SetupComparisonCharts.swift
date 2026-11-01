//
//  SetupComparisonCharts.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit

/// A horizontal time-in-range bar for one period, lows on the left.
struct TimeInRangeStripe: View {
    let title: String
    let timeInRange: [GlucoseBand: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: NSLocalizedString("%@ in range", comment: "Time in range for a period (1: percent)"), percent(timeInRange[.target, default: 0])))
                    .font(.subheadline)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(GlucoseBand.allCases, id: \.self) { band in
                        Rectangle()
                            .fill(band.agpColor)
                            .frame(width: geometry.size.width * timeInRange[band, default: 0])
                    }
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(String(format: NSLocalizedString("%1$@ low · %2$@ high", comment: "Time below and above range for a period (1: percent below, 2: percent above)"),
                        percent(timeInRange[.low, default: 0] + timeInRange[.veryLow, default: 0]),
                        percent(timeInRange[.high, default: 0] + timeInRange[.veryHigh, default: 0])))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(fraction < 0.1 ? 1 : 0)))
    }
}

/// The median glucose by time of day before and after a setup change, with the 25–75% band since the change.
struct MedianComparisonChartView: View {
    let before: [AGPBand]
    let after: [AGPBand]
    let unit: LoopUnit

    private let leftInset: CGFloat = 34
    private let bottomInset: CGFloat = 18
    private let topInset: CGFloat = 6
    private let rightInset: CGFloat = 6

    private var topMgDL: Double { max(300, ((before + after).map(\.p75).max() ?? 300).rounded(.up)) }

    private func yLabel(_ mgdl: Double) -> String {
        let v = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl).doubleValue(for: unit)
        return unit == .milligramsPerDeciliter ? "\(Int(v.rounded()))" : String(format: "%.1f", v)
    }

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: leftInset, y: topInset,
                              width: size.width - leftInset - rightInset,
                              height: size.height - topInset - bottomInset)
            guard plot.width > 0, plot.height > 0 else { return }
            let top = topMgDL

            func x(_ band: AGPBand) -> CGFloat { plot.minX + CGFloat(band.timeOfDay / .days(1)) * plot.width }
            func y(_ mgdl: Double) -> CGFloat { plot.minY + CGFloat(1 - mgdl / top) * plot.height }
            func curve(_ bands: [AGPBand], _ value: (AGPBand) -> Double) -> Path {
                let points = bands.map { CGPoint(x: x($0), y: y(value($0))) }
                var path = Path()
                if let first = points.first {
                    path.move(to: first)
                    AGPChartView.addSmoothCurve(through: points, to: &path)
                }
                return path
            }

            for v in [70.0, 180] {
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y(v)))
                line.addLine(to: CGPoint(x: plot.maxX, y: y(v)))
                ctx.stroke(line, with: .color(GlucoseBand.target.agpColor), lineWidth: 1)
            }

            let afterSorted = after.sorted { $0.timeOfDay < $1.timeOfDay }
            if afterSorted.count > 1 {
                var band = curve(afterSorted, \.p75)
                let lower = afterSorted.reversed().map { CGPoint(x: x($0), y: y($0.p25)) }
                band.addLine(to: lower[0])
                AGPChartView.addSmoothCurve(through: lower, to: &band)
                band.closeSubpath()
                ctx.fill(band, with: .color(Color.accentColor.opacity(0.15)))
            }
            ctx.stroke(curve(before.sorted { $0.timeOfDay < $1.timeOfDay }, \.p50), with: .color(.secondary), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            ctx.stroke(curve(afterSorted, \.p50), with: .color(.accentColor), lineWidth: 2.5)

            for v in [70.0, 180, top] {
                ctx.draw(Text(yLabel(v)).font(.caption2).foregroundColor(.secondary),
                         at: CGPoint(x: plot.minX - 4, y: y(v)), anchor: .trailing)
            }
            for (hour, label) in [(0, "12a"), (6, "6a"), (12, "12p"), (18, "6p"), (24, "12a")] {
                ctx.draw(Text(label).font(.caption2).foregroundColor(.secondary),
                         at: CGPoint(x: plot.minX + CGFloat(hour) / 24 * plot.width, y: plot.maxY + 9), anchor: .center)
            }
        }
        .accessibilityLabel(Text(NSLocalizedString("Median glucose by time of day, before and since the change", comment: "Accessibility label for the setup comparison chart")))
    }
}
