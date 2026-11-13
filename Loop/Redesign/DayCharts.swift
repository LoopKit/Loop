//
//  DayCharts.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Charts
import UIKit

private typealias P = LoopDesign.Palette

// MARK: - Shared axis helpers

enum DayAxis {
    /// Midnight, 6 AM, noon and 6 PM inside `window`, by the clock, so a day when the clocks change still marks 6 AM.
    static func quarterDayMarks(in window: DateInterval, calendar: Calendar = .current) -> [Date] {
        var marks: [Date] = []
        var day = calendar.startOfDay(for: window.start)
        while day <= window.end {
            for hour in [0, 6, 12, 18] {
                if let mark = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), window.contains(mark) {
                    marks.append(mark)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return marks
    }

    static func hourLabel(_ date: Date) -> String {
        date.formatted(.dateTime.hour())
    }

    /// Gaps of more than 30 minutes between readings, so a chart can say where data is missing.
    static func gaps(in points: [GlucosePoint], window: DateInterval, until end: Date) -> [DateInterval] {
        let limit: TimeInterval = 30 * 60
        var gaps: [DateInterval] = []
        var previous = window.start
        for point in points.sorted(by: { $0.date < $1.date }) where window.contains(point.date) {
            if point.date.timeIntervalSince(previous) > limit {
                gaps.append(DateInterval(start: previous, end: point.date))
            }
            previous = point.date
        }
        let last = min(end, window.end)
        if last.timeIntervalSince(previous) > limit {
            gaps.append(DateInterval(start: previous, end: last))
        }
        return gaps
    }

    static func gapMessage(_ gaps: [DateInterval], window: DateInterval, until end: Date) -> String? {
        guard let longest = gaps.max(by: { $0.duration < $1.duration }) else { return nil }
        // A gap over the whole period would read "0:00 – 0:00".
        if gaps.count == 1, longest.start == window.start, longest.end == min(end, window.end) {
            return window.contains(end)
                ? NSLocalizedString("No CGM data yet today", comment: "Chart note: there are no glucose readings so far today")
                : NSLocalizedString("No CGM data on this day", comment: "Chart note: there are no glucose readings for the whole day")
        }
        let start = LoopFormat.time(longest.start)
        let end = LoopFormat.time(longest.end)
        if gaps.count > 1 {
            let others = String.localizedStringWithFormat(NSLocalizedString("%lld shorter gaps", comment: "Chart note: how many other, shorter gaps in glucose readings there were; follows the longest gap. (1: number of gaps)"), gaps.count - 1)
            return String(format: NSLocalizedString("No CGM data %1$@ – %2$@ and %3$@", comment: "Chart note: the longest gap in glucose readings, plus the shorter ones. (1: start time; 2: end time; 3: number of shorter gaps, e.g. 2 shorter gaps)"), start, end, others)
        }
        return String(format: NSLocalizedString("No CGM data %1$@ – %2$@", comment: "Chart note: a gap in glucose readings. (1: start time; 2: end time)"), start, end)
    }
}

// MARK: - InsulinTimeline

/// Carbs, glucose and insulin for one day on one shared time axis.
///
/// The lanes are drawn in a single chart with stacked y ranges so they can't drift apart: insulin 0–30,
/// glucose 36–92 (the fixed 2–20 mmol/L scale), carb markers at 97.
struct InsulinTimelineView: View {
    let history: DayHistory
    let unit: GlucoseUnitStyle
    let targetBands: [TargetBand]
    var now: Date = Date()
    var height: CGFloat = 260

    @State private var selection: Date?
    @Environment(\.colorScheme) private var colorScheme

    private static let insulinTop = 30.0
    private static let basalTop = 12.0
    private static let glucoseRange = 36.0...92.0
    private static let carbLane = 97.0

    private var window: DateInterval { history.window }

    private func y(glucose mgdl: Double) -> Double {
        let domain = unit.dayDomain
        let value = min(max(unit.value(mgdl), domain.lowerBound), domain.upperBound)
        let fraction = (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return Self.glucoseRange.lowerBound + fraction * (Self.glucoseRange.upperBound - Self.glucoseRange.lowerBound)
    }

    private var maxBasal: Double {
        max(0.5, (history.basal.map(\.rate) + history.scheduledBasal.map(\.rate)).max() ?? 0)
    }

    private var maxBolus: Double {
        max(1, history.boluses.map(\.units).max() ?? 0)
    }

    private func y(basal rate: Double) -> Double { rate / maxBasal * Self.basalTop }
    private func y(bolus units: Double) -> Double { max(1.5, units / maxBolus * (Self.insulinTop - 4)) }

    private var gaps: [DateInterval] { DayAxis.gaps(in: history.glucose, window: window, until: now) }

    /// Labels closer than this to the previous label are dropped so they don't overprint; the marks still draw.
    private var labelSpacing: TimeInterval { window.duration / 7 }

    private func spacedIDs<T>(_ items: [T], date: (T) -> Date, id: (T) -> String) -> Set<String> {
        var kept = Set<String>()
        var last: Date?
        for item in items.sorted(by: { date($0) < date($1) }) {
            if let last, date(item).timeIntervalSince(last) < labelSpacing { continue }
            kept.insert(id(item))
            last = date(item)
        }
        return kept
    }

    /// One label per run of carb entries closer together than `labelSpacing`, giving the run's total.
    /// It sits after the run's last marker, so no later marker in the run draws over it.
    private var carbLabels: [String: Double] {
        var labels: [String: Double] = [:]
        var runStart: Date?
        var runLast: (id: String, total: Double)?
        for carb in history.carbs.sorted(by: { $0.date < $1.date }) {
            if let start = runStart, let last = runLast, carb.date.timeIntervalSince(start) < labelSpacing {
                runLast = (carb.id, last.total + carb.grams)
            } else {
                if let last = runLast { labels[last.id] = last.total }
                runStart = carb.date
                runLast = (carb.id, carb.grams)
            }
        }
        if let last = runLast { labels[last.id] = last.total }
        return labels
    }
    private var labelledBoluses: Set<String> { spacedIDs(history.boluses.filter { !$0.automatic }, date: \.date, id: \.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
            chart
                .frame(height: height)
            if let message = DayAxis.gapMessage(gaps, window: window, until: now), history.source == .loop || !history.glucose.isEmpty {
                Text(message)
                    .font(LoopDesign.Typeface.footnote)
                    .foregroundStyle(LoopDesign.Palette.inkMuted)
            }
        }
    }

    private var chart: some View {
        Chart {
            // Quarter-day rules
            ForEach(DayAxis.quarterDayMarks(in: window), id: \.self) { mark in
                RuleMark(x: .value("Time", mark))
                    .foregroundStyle(P.grid)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            // Glucose lane
            ForEach(Array(targetBands.enumerated()), id: \.offset) { _, band in
                RectangleMark(xStart: .value("Start", band.start), xEnd: .value("End", band.end),
                              yStart: .value("Low", y(glucose: band.range.lowerBound)), yEnd: .value("High", y(glucose: band.range.upperBound)))
                    .foregroundStyle(P.targetBand)
            }
            ForEach(Array(history.glucose.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("Time", point.date), y: .value("Glucose", y(glucose: point.mgdl)))
                    .symbolSize(10)
                    .foregroundStyle(P.glucose)
            }

            // Carb markers
            let carbLabels = carbLabels
            ForEach(history.carbs) { carb in
                PointMark(x: .value("Time", carb.date), y: .value("Carbs", Self.carbLane))
                    .symbolSize(60)
                    .foregroundStyle(P.carbs)
                    .annotation(position: .trailing, spacing: 2) {
                        if let grams = carbLabels[carb.id] {
                            Text(LoopFormat.grams(grams))
                                .font(LoopDesign.Typeface.caption)
                                .foregroundStyle(P.carbsInk)
                        }
                    }
            }

            // Delivered basal, edged, then the schedule dashed over it
            // Draw each recorded segment independently; a gap must not become an interpolated delivery area.
            ForEach(Array(history.basal.enumerated()), id: \.offset) { _, segment in
                RectangleMark(xStart: .value("Start", segment.start), xEnd: .value("End", segment.end),
                              yStart: .value("Base", 0), yEnd: .value("Basal", y(basal: segment.rate)))
                    .foregroundStyle(P.basal)
                RuleMark(xStart: .value("Start", segment.start), xEnd: .value("End", segment.end), y: .value("Basal", y(basal: segment.rate)))
                    .foregroundStyle(P.basalEdge)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(Array(history.scheduledBasal.enumerated()), id: \.offset) { _, value in
                RuleMark(xStart: .value("Start", value.start), xEnd: .value("End", value.end), y: .value("Scheduled", y(basal: value.rate)))
                    .foregroundStyle(P.basalScheduled)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // Boluses over basal: solid for manual with a label, hatched for automatic.
            // Each sits in a card-coloured slot a point wider, so it never touches the basal behind it.
            ForEach(history.boluses) { bolus in
                RectangleMark(x: .value("Time", bolus.date), yStart: .value("Base", 0), yEnd: .value("Bolus", y(bolus: bolus.units)), width: .fixed(7))
                    .foregroundStyle(P.surfaceRaised)
            }
            let bolusLabels = labelledBoluses
            ForEach(history.boluses) { bolus in
                if bolus.automatic {
                    RectangleMark(x: .value("Time", bolus.date), yStart: .value("Base", 0), yEnd: .value("Bolus", y(bolus: bolus.units)), width: .fixed(5))
                        .foregroundStyle(Hatch.paint(P.bolus, scheme: colorScheme))
                } else {
                    RectangleMark(x: .value("Time", bolus.date), yStart: .value("Base", 0), yEnd: .value("Bolus", y(bolus: bolus.units)), width: .fixed(5))
                        .foregroundStyle(P.bolus)
                        .annotation(position: .top, spacing: 2) {
                            if bolusLabels.contains(bolus.id) {
                                Text(LoopFormat.number(bolus.units, decimals: 1))
                                    .font(LoopDesign.Typeface.caption)
                                    .foregroundStyle(P.insulinInk)
                            }
                        }
                }
            }

            // Now
            if window.contains(now) {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(P.inkMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            if let selection {
                RuleMark(x: .value("Selected", selection))
                    .foregroundStyle(P.ink.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: window.start...window.end)
        .chartYScale(domain: 0...104)
        .chartXAxis {
            AxisMarks(values: DayAxis.quarterDayMarks(in: window)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(DayAxis.hourLabel(date))
                    }
                }
                .font(LoopDesign.Typeface.caption)
                .foregroundStyle(P.inkMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: unit.dayTicks.map { y(glucose: unit.mgdl($0)) }) { value in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel {
                    if let mapped = value.as(Double.self), let tick = unit.dayTicks.first(where: { abs(y(glucose: unit.mgdl($0)) - mapped) < 0.01 }) {
                        Text(tick.formatted())
                    }
                }
                .font(LoopDesign.Typeface.caption)
                .foregroundStyle(P.inkMuted)
            }
        }
        .chartOverlay { proxy in
            ScrubOverlay(proxy: proxy, selection: $selection, clampTo: window)
        }
        .overlay(alignment: .top) {
            if let selection {
                ScrubCallout(rows: scrubRows(at: selection))
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func scrubRows(at date: Date) -> [ScrubCallout.Row] {
        var rows: [ScrubCallout.Row] = [.init(label: nil, value: LoopFormat.time(date), color: P.ink)]
        if let glucose = nearest(history.glucose.map { ($0.date, $0.mgdl) }, to: date, within: 10 * 60) {
            rows.append(.init(label: NSLocalizedString("Glucose", comment: "Chart callout label for the glucose reading at the touched time"), value: "\(unit.format(glucose)) \(unit.unitName)", color: P.glucoseInk))
        }
        if let iob = nearest(history.iob.map { ($0.date, $0.value) }, to: date, within: 10 * 60) {
            rows.append(.init(label: NSLocalizedString("IOB", comment: "Abbreviation for insulin on board (active insulin)"), value: LoopFormat.doseUnits(iob), color: P.insulinInk))
        }
        if let cob = nearest(history.cob.map { ($0.date, $0.value) }, to: date, within: 10 * 60) {
            rows.append(.init(label: NSLocalizedString("COB", comment: "Abbreviation for carbs on board (active carbohydrate)"), value: LoopFormat.grams(cob), color: P.carbsInk))
        }
        if let segment = LoopHistoryMath.basalRate(at: date, in: history.basal) {
            let value = segment.kind == .suspended
                ? NSLocalizedString("Suspended", comment: "Chart callout value: insulin delivery was suspended at the touched time")
                : LoopFormat.rate(segment.rate)
            rows.append(.init(label: NSLocalizedString("Basal", comment: "Chart callout label for the basal rate at the touched time"), value: value, color: P.ink))
        }
        if let bolus = history.boluses.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
           abs(bolus.date.timeIntervalSince(date)) < 5 * 60 {
            rows.append(.init(label: bolus.automatic
                              ? NSLocalizedString("Automatic bolus", comment: "Chart callout label for a bolus Loop delivered automatically near the touched time")
                              : NSLocalizedString("Bolus", comment: "Chart callout label for a bolus near the touched time"),
                              value: LoopFormat.doseUnits(bolus.units), color: P.insulinInk))
        }
        return rows
    }

    private var accessibilitySummary: String {
        let day = LoopFormat.weekdayDay(window.start)
        let bolus = LoopFormat.totalUnits(history.bolusUnits)
        let basal = LoopFormat.totalUnits(history.basalUnits)
        let carbs = LoopFormat.grams(history.carbGrams)
        if let last = history.glucose.last {
            return String(format: NSLocalizedString("Insulin timeline, %1$@, bolus %2$@, basal %3$@, carbs %4$@, latest glucose %5$@ %6$@", comment: "VoiceOver summary of the day's insulin timeline chart. (1: weekday and date; 2: bolus total, e.g. 12.5 U; 3: basal total; 4: carbs total, e.g. 140 g; 5: latest glucose value; 6: glucose unit, mmol/L or mg/dL)"), day, bolus, basal, carbs, unit.format(last.mgdl), unit.unitName)
        }
        return String(format: NSLocalizedString("Insulin timeline, %1$@, bolus %2$@, basal %3$@, carbs %4$@", comment: "VoiceOver summary of the day's insulin timeline chart with no glucose readings. (1: weekday and date; 2: bolus total, e.g. 12.5 U; 3: basal total; 4: carbs total, e.g. 140 g)"), day, bolus, basal, carbs)
    }
}

func nearest(_ values: [(Date, Double)], to date: Date, within limit: TimeInterval) -> Double? {
    guard let best = values.min(by: { abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date)) }),
          abs(best.0.timeIntervalSince(date)) <= limit else {
        return nil
    }
    return best.1
}

// MARK: - Scrubbing

/// Touch and hold then drag to scrub; a plain swipe still scrolls the page.
///
/// A UIKit long-press recogniser is used because a SwiftUI long-press-then-drag gesture inside a table cell
/// takes every drag that starts on the chart, so the page couldn't scroll past it.
struct ScrubOverlay: View {
    let proxy: ChartProxy
    @Binding var selection: Date?
    let clampTo: DateInterval

    var body: some View {
        GeometryReader { geometry in
            if #available(iOS 18.0, *) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(ScrubPressRecognizer { location in
                        update(location, in: geometry)
                    } onEnd: {
                        selection = nil
                    })
            } else {
                Color.clear
            }
        }
    }

    private func update(_ location: CGPoint, in geometry: GeometryProxy) {
        guard let frame = proxy.plotFrame else { return }
        let origin = geometry[frame].origin
        if let date: Date = proxy.value(atX: location.x - origin.x) {
            selection = min(max(date, clampTo.start), clampTo.end)
        }
    }
}

@available(iOS 18.0, *)
private struct ScrubPressRecognizer: UIGestureRecognizerRepresentable {
    let onChange: (CGPoint) -> Void
    let onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.3
        recognizer.allowableMovement = 12
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.localLocation)
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }
}

struct ScrubCallout: View {
    struct Row: Hashable {
        let label: String?
        let value: String
        let color: Color
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: LoopDesign.Space.s1) {
                    if let label = row.label {
                        Text(label).foregroundStyle(P.inkMuted)
                    }
                    Text(row.value).foregroundStyle(row.color).fontWeight(.semibold)
                }
            }
        }
        .font(LoopDesign.Typeface.footnote.monospacedDigit())
        .padding(.horizontal, LoopDesign.Space.s2)
        .padding(.vertical, LoopDesign.Space.s1)
        .background(P.surfaceRaised, in: RoundedRectangle(cornerRadius: LoopDesign.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: LoopDesign.Radius.sm).strokeBorder(P.separator))
    }
}

// MARK: - Prediction

/// The last three hours of readings and Loop's dashed prediction for the next three.
struct PredictionChartView: View {
    let readings: [GlucosePoint]
    let prediction: [GlucosePoint]
    let unit: GlucoseUnitStyle
    let targetBands: [TargetBand]
    var now: Date = Date()
    var height: CGFloat = 150

    @State private var selection: Date?

    private var window: DateInterval {
        DateInterval(start: now.addingTimeInterval(-3 * 3600), end: now.addingTimeInterval(3 * 3600))
    }

    private func clamp(_ mgdl: Double) -> Double {
        min(max(unit.value(mgdl), unit.dayDomain.lowerBound), unit.dayDomain.upperBound)
    }

    private var futurePrediction: [GlucosePoint] {
        prediction.filter { $0.date >= now.addingTimeInterval(-5 * 60) && $0.date <= window.end }
    }

    var body: some View {
        Chart {
            ForEach(Array(targetBands.enumerated()), id: \.offset) { _, band in
                RectangleMark(xStart: .value("Start", band.start), xEnd: .value("End", band.end),
                              yStart: .value("Low", clamp(band.range.lowerBound)), yEnd: .value("High", clamp(band.range.upperBound)))
                    .foregroundStyle(P.targetBand)
            }
            ForEach(Array(readings.filter { window.contains($0.date) }.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("Time", point.date), y: .value("Glucose", clamp(point.mgdl)))
                    .symbolSize(12)
                    .foregroundStyle(P.glucose)
            }
            ForEach(Array(futurePrediction.enumerated()), id: \.offset) { index, point in
                LineMark(x: .value("Time", point.date), y: .value("Predicted", clamp(point.mgdl)), series: .value("Series", "prediction"))
                    .foregroundStyle(P.glucose)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .topTrailing, spacing: 0) {
                        if index == futurePrediction.count - 1 {
                            Text(unit.format(point.mgdl))
                                .font(LoopDesign.Typeface.caption.weight(.semibold))
                                .foregroundStyle(P.ink)
                        }
                    }
            }
            RuleMark(x: .value("Now", now))
                .foregroundStyle(P.inkMuted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            if let selection {
                RuleMark(x: .value("Selected", selection))
                    .foregroundStyle(P.ink.opacity(0.6))
            }
        }
        .frame(height: height)
        .chartXScale(domain: window.start...window.end)
        .chartYScale(domain: unit.dayDomain)
        .chartXAxis {
            AxisMarks(values: [window.start, now, window.end]) { value in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(abs(date.timeIntervalSince(now)) < 60 ? NSLocalizedString("now", comment: "Prediction chart x-axis label marking the current time") : LoopFormat.time(date))
                    }
                }
                .font(LoopDesign.Typeface.caption)
                .foregroundStyle(P.inkMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: unit.dayTicks) { _ in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel().font(LoopDesign.Typeface.caption).foregroundStyle(P.inkMuted)
            }
        }
        .chartOverlay { proxy in
            ScrubOverlay(proxy: proxy, selection: $selection, clampTo: window)
        }
        .overlay(alignment: .top) {
            if let selection {
                ScrubCallout(rows: scrubRows(at: selection)).allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func scrubRows(at date: Date) -> [ScrubCallout.Row] {
        var rows: [ScrubCallout.Row] = [.init(label: nil, value: LoopFormat.time(date), color: P.ink)]
        let source = date <= now ? readings : prediction
        if let value = nearest(source.map { ($0.date, $0.mgdl) }, to: date, within: 10 * 60) {
            rows.append(.init(label: date <= now
                              ? NSLocalizedString("Glucose", comment: "Chart callout label for the glucose reading at the touched time")
                              : NSLocalizedString("Predicted", comment: "Prediction chart callout label for Loop's predicted glucose at the touched time"),
                              value: "\(unit.format(value)) \(unit.unitName)", color: P.glucoseInk))
        }
        return rows
    }

    private var accessibilitySummary: String {
        guard let last = futurePrediction.last else {
            return NSLocalizedString("Glucose prediction unavailable", comment: "VoiceOver label for the prediction chart when Loop has no prediction")
        }
        return String(format: NSLocalizedString("Loop predicts %1$@ %2$@ by %3$@", comment: "VoiceOver summary of the prediction chart. (1: predicted glucose value; 2: glucose unit, mmol/L or mg/dL; 3: time of the prediction)"), unit.format(last.mgdl), unit.unitName, LoopFormat.time(last.date))
    }
}

// MARK: - IOB and COB

/// Insulin and carbs on board over the same window, each against its own coloured axis.
struct IOBCOBChartView: View {
    let iob: [TimedValue]
    let cob: [TimedValue]
    let window: DateInterval
    var now: Date = Date()
    var height: CGFloat = 140

    @State private var selection: Date?

    private var iobMax: Double { max(1, (iob.map(\.value).max() ?? 0) * 1.1) }
    private var iobMin: Double { min(0, (iob.map(\.value).min() ?? 0) * 1.1) }
    private var cobMax: Double { max(10, (cob.map(\.value).max() ?? 0) * 1.1) }

    /// COB drawn on the IOB scale.
    private func scaled(cob value: Double) -> Double { value / cobMax * iobMax }

    private var iobTicks: [Double] {
        let step = Self.niceStep(iobMax / 2)
        return stride(from: (iobMin / step).rounded(.down) * step, through: iobMax, by: step).map { $0 }
    }

    private var cobTicks: [Double] {
        let step = Self.niceStep(cobMax / 2)
        return stride(from: 0, through: cobMax, by: step).map { $0 }
    }

    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let nice: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10
        return nice * magnitude
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(P.inkMuted)
                .lineStyle(StrokeStyle(lineWidth: 1))

            ForEach(Array(cob.enumerated()), id: \.offset) { _, value in
                AreaMark(x: .value("Time", value.date), yStart: .value("Base", 0), yEnd: .value("COB", scaled(cob: value.value)), series: .value("Series", "cob-fill"))
                    .foregroundStyle(P.carbs.opacity(0.14))
                LineMark(x: .value("Time", value.date), y: .value("COB", scaled(cob: value.value)), series: .value("Series", value.date > now ? "cob-projected" : "cob"))
                    .foregroundStyle(P.carbs)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: value.date > now ? [4, 3] : []))
            }
            ForEach(Array(iob.enumerated()), id: \.offset) { _, value in
                AreaMark(x: .value("Time", value.date), yStart: .value("Base", 0), yEnd: .value("IOB", value.value), series: .value("Series", "iob-fill"))
                    .foregroundStyle(P.insulin.opacity(0.14))
                LineMark(x: .value("Time", value.date), y: .value("IOB", value.value), series: .value("Series", value.date > now ? "iob-projected" : "iob"))
                    .foregroundStyle(P.insulin)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: value.date > now ? [4, 3] : []))
            }
            if window.contains(now) {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(P.inkMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
            }
            if let selection {
                RuleMark(x: .value("Selected", selection)).foregroundStyle(P.ink.opacity(0.6))
            }
        }
        .frame(height: height)
        .chartXScale(domain: window.start...window.end)
        .chartYScale(domain: iobMin...iobMax)
        .chartXAxis {
            AxisMarks(values: DayAxis.quarterDayMarks(in: window)) { value in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(DayAxis.hourLabel(date)) }
                }
                .font(LoopDesign.Typeface.caption)
                .foregroundStyle(P.inkMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: iobTicks) { value in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(v.formatted(.number.precision(.fractionLength(0...1)))) }
                }
                .font(LoopDesign.Typeface.caption)
                .foregroundStyle(P.insulinInk)
            }
            AxisMarks(position: .trailing, values: cobTicks.map { scaled(cob: $0) }) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text((v / iobMax * cobMax).formatted(.number.precision(.fractionLength(0)))) }
                }
                .font(LoopDesign.Typeface.caption)
                .foregroundStyle(P.carbsInk)
            }
        }
        .chartOverlay { proxy in
            ScrubOverlay(proxy: proxy, selection: $selection, clampTo: window)
        }
        .overlay(alignment: .top) {
            if let selection {
                ScrubCallout(rows: scrubRows(at: selection)).allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func scrubRows(at date: Date) -> [ScrubCallout.Row] {
        var rows: [ScrubCallout.Row] = [.init(label: nil, value: LoopFormat.time(date), color: P.ink)]
        if let value = nearest(iob.map { ($0.date, $0.value) }, to: date, within: 10 * 60) {
            rows.append(.init(label: NSLocalizedString("IOB", comment: "Abbreviation for insulin on board (active insulin)"), value: LoopFormat.doseUnits(value), color: P.insulinInk))
        }
        if let value = nearest(cob.map { ($0.date, $0.value) }, to: date, within: 10 * 60) {
            rows.append(.init(label: NSLocalizedString("COB", comment: "Abbreviation for carbs on board (active carbohydrate)"), value: LoopFormat.grams(value), color: P.carbsInk))
        }
        return rows
    }

    private var accessibilitySummary: String {
        let iobNow = nearest(iob.map { ($0.date, $0.value) }, to: now, within: 10 * 60)
        let cobNow = nearest(cob.map { ($0.date, $0.value) }, to: now, within: 10 * 60)
        let unknown = NSLocalizedString("unknown", comment: "VoiceOver value when active insulin or carbs at the current time isn't known")
        return String(format: NSLocalizedString("Active insulin %1$@, active carbs %2$@", comment: "VoiceOver summary of the active insulin and carbs chart. (1: insulin on board, e.g. 1.25 U, or unknown; 2: carbs on board, e.g. 20 g, or unknown)"), iobNow.map(LoopFormat.doseUnits) ?? unknown, cobNow.map(LoopFormat.grams) ?? unknown)
    }
}
