//
//  RedesignLiveActivity.swift
//  Loop Widget Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import ActivityKit
import Charts
import HealthKit
import LoopCore
import LoopKit
import SwiftUI
import WidgetKit

/// The Live Activity in the redesign's style. It reads the same `GlucoseActivityAttributes` as the
/// classic one, so the Live Activity settings (chart, bottom row, limits) keep working.
@available(iOS 16.2, *)
enum RedesignLiveActivity {
    typealias Context = ActivityViewContext<GlucoseActivityAttributes>
    private typealias P = LoopDesign.Palette

    // MARK: - Shared pieces

    private static func unitName(_ context: Context) -> String {
        (context.state.isMmol ? HKUnit.millimolesPerLiter : HKUnit.milligramsPerDeciliter).localizedShortUnitString
    }

    private static func format(_ value: Double, _ context: Context) -> String {
        NumberFormatter.glucoseFormatter(for: context.state.isMmol ? .millimolesPerLiter : .milligramsPerDeciliter).string(from: value) ?? "–"
    }

    static func range(_ context: Context) -> WidgetDesign.Range? {
        WidgetDesign.Range(context.state.currentGlucose, isMmol: context.state.isMmol)
    }

    static func status(_ context: Context) -> WidgetDesign.LoopStatus {
        WidgetDesign.LoopStatus(closedLoop: context.state.isCloseLoop, lastCompleted: context.state.lastCompleted, now: context.state.date)
    }

    /// Low and high in words, otherwise the unit and the change, as under the Now screen's number.
    @ViewBuilder
    private static func detail(_ context: Context) -> some View {
        if let range = range(context) {
            HStack(spacing: LoopDesign.Space.s1) {
                Circle().fill(range.color).frame(width: 7, height: 7)
                Text(range.text)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(P.ink)
        } else {
            Text(WidgetDesign.readingDetail(unit: unitName(context), delta: context.state.delta))
                .font(.caption)
                .foregroundStyle(P.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private static func eventually(_ context: Context) -> String? {
        context.state.eventualGlucose.map {
            String(format: NSLocalizedString("Eventually %1$@ %2$@", comment: "Header detail of the Next 3 hours card on the Now screen: the glucose Loop predicts at the end of its prediction. (1: glucose value; 2: glucose unit)"), format($0, context), unitName(context))
        }
    }

    private static func hero(_ context: Context, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetGlucoseValue(value: format(context.state.currentGlucose, context), trend: context.state.trendType, size: size)
            detail(context)
        }
    }

    // MARK: - Lock Screen

    static func lockScreen(_ context: Context) -> some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s1) {
            HStack(alignment: .top) {
                hero(context, size: context.attributes.mode == .large ? 30 : 38)
                Spacer(minLength: LoopDesign.Space.s2)
                VStack(alignment: .trailing, spacing: 4) {
                    WidgetStatusLine(status: status(context))
                    if let eventually = eventually(context) {
                        Text(eventually)
                            .font(.caption)
                            .foregroundStyle(P.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            if context.attributes.mode == .large {
                RedesignActivityChart(context: context)
                    .frame(height: 54)
            }
            let tiles = tileItems(context)
            if !tiles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tiles, id: \.self) { item in
                        tile(item, context, inline: context.attributes.mode == .large)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay {
            if context.state.ended {
                Text(NSLocalizedString("Open the app to update the widget", comment: "No comment"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(P.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .privacySensitive()
        .activityBackgroundTint(P.surfaceRaised.opacity(0.92))
        .activitySystemActionForegroundColor(P.ink)
    }

    /// The watch and CarPlay size: the number, the change and the prediction.
    static func smallFamily(_ context: Context) -> some View {
        HStack(alignment: .center) {
            hero(context, size: 26)
            Spacer(minLength: LoopDesign.Space.s1)
            VStack(alignment: .trailing, spacing: 2) {
                Circle().fill(status(context).color).frame(width: 8, height: 8)
                if let eventual = context.state.eventualGlucose {
                    Text(format(eventual, context))
                        .font(.system(.headline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(P.ink)
                    Text(NSLocalizedString("Eventually", comment: "Short label above the glucose Loop predicts at the end of its prediction, in a small tile on the widget and Live Activity. Keep it to one short word, such as 'Forecast'."))
                        .font(.caption2)
                        .foregroundStyle(P.inkMuted)
                }
            }
        }
        .padding(LoopDesign.Space.s3)
        .privacySensitive()
    }

    /// The configured bottom row, less the reading and its change, which the hero already shows.
    private static func tileItems(_ context: Context) -> [BottomRowItem] {
        context.state.bottomRow.filter { item in
            switch item.type {
            case .currentBg: return false
            case .generic: return item.value != context.state.delta || item.unit != ""
            case .basal: return true
            }
        }
    }

    @ViewBuilder
    private static func tile(_ item: BottomRowItem, _ context: Context, inline: Bool) -> some View {
        switch item.type {
        case .basal:
            WidgetTile(label: NSLocalizedString("Basal", comment: "Label of a tile showing the current basal rate (Now screen) or the day's basal insulin total (Today so far totals)"), inline: inline) {
                Text(String(format: NSLocalizedString("%1$@ U/h", comment: "Insulin rate in units per hour. (1: number)"), WidgetDesign.signed(item.rate, decimals: 2)))
                    .foregroundStyle(P.insulinInk)
            }
        case .generic, .currentBg:
            WidgetTile(label: item.label, inline: inline) {
                switch item.unit {
                case "U":
                    Text(String(format: NSLocalizedString("%1$@ U", comment: "Insulin amount in units. (1: number)"), item.value))
                        .foregroundStyle(P.insulinInk)
                case "g":
                    Text(String(format: NSLocalizedString("%1$@ g", comment: "Amount of carbohydrate in grams. (1: number)"), item.value))
                        .foregroundStyle(P.carbsInk)
                default:
                    Text(item.value)
                        .foregroundStyle(P.ink)
                }
            }
        }
    }

    // MARK: - Dynamic Island

    static func dynamicIsland(_ context: Context) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                hero(context, size: 34)
                    .padding(.leading, LoopDesign.Space.s1)
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
            }
            // The trailing region is narrow, so it holds only the prediction, labelled like the widget's tile;
            // Loop's status gets the full width above the chart, where long translations still fit.
            DynamicIslandExpandedRegion(.trailing) {
                if let eventual = context.state.eventualGlucose {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(NSLocalizedString("Eventually", comment: "Short label above the glucose Loop predicts at the end of its prediction, in a small tile on the widget and Live Activity. Keep it to one short word, such as 'Forecast'."))
                            .font(.caption2)
                            .foregroundStyle(P.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(format(eventual, context))
                            .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(P.ink)
                    }
                    .padding(.trailing, LoopDesign.Space.s1)
                    .padding(.top, LoopDesign.Space.s1)
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(alignment: .leading, spacing: LoopDesign.Space.s1) {
                    WidgetStatusLine(status: status(context), font: .caption.weight(.medium))
                    RedesignActivityChart(context: context)
                        .frame(height: 46)
                }
                .padding(.horizontal, LoopDesign.Space.s1)
            }
        } compactLeading: {
            HStack(spacing: 3) {
                Text(format(context.state.currentGlucose, context))
                    .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                if let trend = context.state.trendType {
                    Image(systemName: WidgetDesign.trendSymbol(trend))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(P.glucose)
                }
            }
        } compactTrailing: {
            HStack(spacing: 4) {
                if let range = range(context) {
                    Text(range.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(range.color)
                } else {
                    Text(context.state.delta)
                        .font(.system(.caption, design: .rounded).weight(.medium).monospacedDigit())
                        .foregroundStyle(Color(white: 0.75))
                }
                Circle().fill(status(context).color).frame(width: 6, height: 6)
            }
            .minimumScaleFactor(0.6)
        } minimal: {
            Text(format(context.state.currentGlucose, context))
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
        // The island's outline says low or high, so the number itself stays white.
        .keylineTint(range(context)?.color ?? P.glucose)
    }
}

// MARK: - Chart

/// The Now screen's prediction chart, sized for the Live Activity: blue readings, Loop's dashed
/// prediction and the target band.
@available(iOS 16.2, *)
struct RedesignActivityChart: View {
    let context: ActivityViewContext<GlucoseActivityAttributes>
    private typealias P = LoopDesign.Palette

    private var lowerLimit: Double {
        context.state.isMmol ? context.attributes.lowerLimitChartMmol : context.attributes.lowerLimitChartMg
    }

    private var upperLimit: Double {
        context.state.isMmol ? context.attributes.upperLimitChartMmol : context.attributes.upperLimitChartMg
    }

    /// With "use limits" on, readings outside them take the Trends range colours; the rest stay blue.
    private func color(_ value: Double) -> Color {
        guard context.attributes.useLimits else { return P.glucose }
        if value < lowerLimit { return P.rangeLow }
        if value > upperLimit { return P.rangeHigh }
        return P.glucose
    }

    private var prediction: [(Date, Double)] {
        guard context.attributes.addPredictiveLine, let start = context.state.predicatedStartDate else { return [] }
        let interval = context.state.predicatedInterval ?? .minutes(5)
        let end = start.addingTimeInterval(.hours(3))
        return context.state.predicatedGlucose.enumerated()
            .map { (start.addingTimeInterval(interval * Double($0.offset)), $0.element) }
            .filter { $0.0 <= end }
    }

    private var domain: ClosedRange<Double> {
        let marks = context.state.yAxisMarks
        return (marks.first ?? 0)...(marks.last ?? 1)
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, domain.lowerBound), domain.upperBound)
    }

    /// The readings Loop sent and its prediction, at least an hour ahead, as on the Now screen's chart.
    private var window: ClosedRange<Date> {
        let now = context.state.date
        let start = min(context.state.glucoseSamples.first?.x ?? now.addingTimeInterval(.hours(-3)), now.addingTimeInterval(.hours(-1)))
        let end = max(prediction.last?.0 ?? now, now.addingTimeInterval(.hours(1)))
        return start...end
    }

    var body: some View {
        Chart {
            ForEach(context.state.glucoseRanges.filter { $0.endDate > window.lowerBound && $0.startDate < window.upperBound }) { band in
                RectangleMark(xStart: .value("Start", max(band.startDate, window.lowerBound)), xEnd: .value("End", min(band.endDate, window.upperBound)),
                              yStart: .value("Low", clamp(band.minValue)), yEnd: .value("High", clamp(max(band.maxValue, band.minValue + domainPadding))))
                    .foregroundStyle(band.isOverride ? P.accent.opacity(0.25) : P.targetBand)
            }
            ForEach(Array(context.state.glucoseSamples.enumerated()), id: \.offset) { _, sample in
                PointMark(x: .value("Time", sample.x), y: .value("Glucose", clamp(sample.y)))
                    .symbolSize(9)
                    .foregroundStyle(color(sample.y))
            }
            ForEach(Array(prediction.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.0), y: .value("Predicted", clamp(point.1)), series: .value("Series", "prediction"))
                    .foregroundStyle(P.glucose)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            RuleMark(x: .value("Now", context.state.date))
                .foregroundStyle(P.inkMuted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .chartXScale(domain: window)
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: axisLabels) { _ in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel().font(LoopDesign.Typeface.caption).foregroundStyle(P.inkMuted)
            }
        }
        .chartXAxis {
            AxisMarks(values: hourMarks) { _ in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel(format: .dateTime.hour()).font(LoopDesign.Typeface.caption).foregroundStyle(P.inkMuted)
            }
        }
        .chartLegend(.hidden)
        .overlay(alignment: .topTrailing) {
            if let preset = context.state.preset, preset.endDate > context.state.date {
                Text(preset.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(P.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(P.accent.opacity(0.25), in: Capsule())
            }
        }
        .accessibilityHidden(true)
    }

    /// Whole hours inside the window, kept clear of the edges so their labels aren't clipped.
    private var hourMarks: [Date] {
        let calendar = Calendar.current
        guard var hour = calendar.dateInterval(of: .hour, for: window.lowerBound)?.end else { return [] }
        var marks: [Date] = []
        while hour <= window.upperBound.addingTimeInterval(.minutes(-25)) {
            if hour >= window.lowerBound.addingTimeInterval(.minutes(12)) { marks.append(hour) }
            hour = hour.addingTimeInterval(.hours(1))
        }
        return marks
    }

    /// Every other value Loop suggests, so labels don't crowd a chart this short.
    private var axisLabels: [Double] {
        let marks = context.state.yAxisMarks
        return marks.count > 3 ? marks.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) : marks
    }

    /// A single-value target is drawn as a thin band, so it stays visible.
    private var domainPadding: Double {
        (domain.upperBound - domain.lowerBound) / 60
    }
}
