//
//  AGPChartView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopUI

/// The ambulatory glucose profile, styled after the IDC / captūrAGP report.
///
/// The percentile bands (5–95% and 25–75%) are each built once as a single
/// continuous shape, then filled with the glucose-zone colors (green target,
/// gold high, orange very-high, red lows) by clipping each color to that zone's
/// horizontal stripe. Because every zone clips the *same* band path, the colored
/// segments always line up at the zone boundaries. Drawn with a `Canvas` for
/// full control over the clipping. Glucose is plotted in the user's display unit.
struct AGPChartView: View {
    let profile: [AGPBand]
    let unit: LoopUnit
    var targetLowMgDL: Double = 70
    var targetHighMgDL: Double = 180

    private struct Zone { let lo: Double, hi: Double, band: GlucoseBand }

    private var topMgDL: Double { max(350, (profile.map { $0.p95 }.max() ?? 350).rounded(.up)) }
    private var zones: [Zone] {
        [Zone(lo: 0, hi: 54, band: .veryLow),
         Zone(lo: 54, hi: 70, band: .low),
         Zone(lo: 70, hi: 180, band: .target),
         Zone(lo: 180, hi: 250, band: .high),
         Zone(lo: 250, hi: topMgDL, band: .veryHigh)]
    }

    private func display(_ mgdl: Double) -> Double {
        LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl).doubleValue(for: unit)
    }
    private func yLabel(_ mgdl: Double) -> String {
        let v = display(mgdl)
        return unit == .milligramsPerDeciliter ? "\(Int(v.rounded()))" : String(format: "%.1f", v)
    }

    private let leftInset: CGFloat = 34
    private let bottomInset: CGFloat = 18
    private let topInset: CGFloat = 6
    private let rightInset: CGFloat = 6
    private let medianColor = Color(red: 0.16, green: 0.40, blue: 0.20)

    /// Append a smooth (Catmull-Rom) curve through `points` to a path already
    /// positioned at `points[0]`.
    static func addSmoothCurve(through points: [CGPoint], to path: inout Path) {
        guard points.count > 1 else { return }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(points.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: leftInset, y: topInset,
                              width: size.width - leftInset - rightInset,
                              height: size.height - topInset - bottomInset)
            guard plot.width > 0, plot.height > 0 else { return }
            let pts = profile.sorted { $0.timeOfDay < $1.timeOfDay }
            guard !pts.isEmpty else { return }
            let top = topMgDL

            func x(_ hour: Double) -> CGFloat { plot.minX + CGFloat(hour / 24) * plot.width }
            func y(_ mgdl: Double) -> CGFloat { plot.minY + CGFloat(1 - mgdl / top) * plot.height }

            func bandPath(_ lo: (AGPBand) -> Double, _ hi: (AGPBand) -> Double) -> Path {
                let topPts = pts.map { CGPoint(x: x($0.timeOfDay / 3600), y: y(hi($0))) }
                let botPts = pts.reversed().map { CGPoint(x: x($0.timeOfDay / 3600), y: y(lo($0))) }
                var p = Path()
                p.move(to: topPts[0])
                Self.addSmoothCurve(through: topPts, to: &p)
                p.addLine(to: botPts[0])
                Self.addSmoothCurve(through: botPts, to: &p)
                p.closeSubpath()
                return p
            }
            let outer = bandPath({ $0.p05 }, { $0.p95 })
            let inner = bandPath({ $0.p25 }, { $0.p75 })

            // Y gridlines.
            for v in [54.0, 70, 180, 250, top] {
                var grid = Path()
                grid.move(to: CGPoint(x: plot.minX, y: y(v)))
                grid.addLine(to: CGPoint(x: plot.maxX, y: y(v)))
                ctx.stroke(grid, with: .color(.gray.opacity(0.25)), lineWidth: 0.5)
            }

            // Bands: fill each glucose zone's color, clipped to that zone's stripe.
            for z in zones {
                let stripe = CGRect(x: plot.minX, y: y(z.hi), width: plot.width, height: y(z.lo) - y(z.hi))
                ctx.drawLayer { layer in
                    layer.clip(to: Path(stripe))
                    layer.fill(outer, with: .color(z.band.agpColor.opacity(0.35)))
                    layer.fill(inner, with: .color(z.band.agpColor.opacity(0.75)))
                }
            }

            // Target-range boundaries.
            for t in [targetLowMgDL, targetHighMgDL] {
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y(t)))
                line.addLine(to: CGPoint(x: plot.maxX, y: y(t)))
                ctx.stroke(line, with: .color(GlucoseBand.target.agpColor), lineWidth: 1.5)
            }

            // Median.
            let medPts = pts.map { CGPoint(x: x($0.timeOfDay / 3600), y: y($0.p50)) }
            var med = Path()
            med.move(to: medPts[0])
            Self.addSmoothCurve(through: medPts, to: &med)
            ctx.stroke(med, with: .color(medianColor), lineWidth: 2.5)

            // Y-axis labels.
            for v in [54.0, 70, 180, 250, top] {
                ctx.draw(Text(yLabel(v)).font(.caption2).foregroundColor(.secondary),
                         at: CGPoint(x: plot.minX - 4, y: y(v)), anchor: .trailing)
            }
            // X-axis labels.
            for (hour, label) in [(0, "12a"), (6, "6a"), (12, "12p"), (18, "6p"), (24, "12a")] {
                ctx.draw(Text(label).font(.caption2).foregroundColor(.secondary),
                         at: CGPoint(x: x(Double(hour)), y: plot.maxY + 9), anchor: .center)
            }
        }
        .accessibilityLabel(Text(NSLocalizedString("Daily glucose pattern", comment: "Accessibility label for the daily glucose pattern (AGP) chart")))
    }
}

#if DEBUG
#Preview {
    let bands: [AGPBand] = (0..<48).map { i in
        let hour = Double(i) * 0.5
        let base = 150.0 + 55 * sin((hour - 4) / 24 * 2 * .pi)
        let spread = 25 + 18 * (1 + sin((hour - 8) / 24 * 2 * .pi))
        return AGPBand(
            timeOfDay: (Double(i) + 0.5) * 1800,
            p05: max(45, base - spread * 1.8), p25: base - spread * 0.7,
            p50: base, p75: base + spread * 0.8, p95: base + spread * 1.9
        )
    }
    return AGPChartView(profile: bands, unit: .milligramsPerDeciliter)
        .frame(height: 260)
        .padding()
}
#endif
