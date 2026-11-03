//
//  TrendsComponents.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Charts

private typealias P = LoopDesign.Palette

// MARK: - RangeSelector

enum TrendsPeriod: Int, CaseIterable, Identifiable {
    case day = 1
    case week = 7
    case twoWeeks = 14
    case month = 30
    case quarter = 90

    var id: Int { rawValue }

    var label: String {
        self == .day
            ? NSLocalizedString("Day (Trends period)", value: "Day", comment: "Trends period picker: a period of one calendar day (not daytime)")
            : String(format: NSLocalizedString("%1$@ d", comment: "Trends period picker, short label for a period of several days, e.g. 7 d. (1: number of days)"),
                     LoopFormat.number(Double(rawValue), decimals: 0))
    }

    var accessibilityName: String {
        self == .day
            ? NSLocalizedString("Day (Trends period)", value: "Day", comment: "Trends period picker: a period of one calendar day (not daytime)")
            : String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: "Trends period picker, VoiceOver name for a period of several days. (1: number of days)"), rawValue)
    }

    /// The period ending on `endDay` (inclusive), cut off at `now` when it ends today.
    func interval(endingOn endDay: Date, now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDay))!
        let start = calendar.date(byAdding: .day, value: -rawValue, to: endOfDay)!
        return DateInterval(start: start, end: min(endOfDay, now))
    }
}

struct RangeSelectorView: View {
    @Binding var period: TrendsPeriod
    @Binding var endDay: Date
    var now: Date = Date()

    private var calendar: Calendar { .current }

    private var canStepForward: Bool {
        !calendar.isDate(endDay, inSameDayAs: now) && endDay < now
    }

    var body: some View {
        VStack(spacing: LoopDesign.Space.s3) {
            Picker(NSLocalizedString("Period", comment: "Trends: VoiceOver label of the picker that chooses how many days the screen covers"),
                   selection: $period.animation(.snappy(duration: 0.2))) {
                ForEach(TrendsPeriod.allCases) { option in
                    Text(option.label)
                        .accessibilityLabel(option.accessibilityName)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                StepButton(systemName: "chevron.left", label: NSLocalizedString("Previous period", comment: "VoiceOver label for the Trends button that moves back one period")) { step(-1) }
                Spacer()
                Text(LoopFormat.range(period.interval(endingOn: endDay, now: now).start, endDay))
                    .font(LoopDesign.Typeface.headline.monospacedDigit())
                    .foregroundStyle(P.ink)
                Spacer()
                StepButton(systemName: "chevron.right", label: NSLocalizedString("Next period", comment: "VoiceOver label for the Trends button that moves forward one period"), enabled: canStepForward) { step(1) }
            }
        }
    }

    private func step(_ direction: Int) {
        guard let next = calendar.date(byAdding: .day, value: direction * period.rawValue, to: endDay) else { return }
        endDay = min(next, now)
    }
}

// MARK: - StatGrid

struct StatTile: Identifiable {
    let label: String
    let value: String
    let unit: String?
    let detail: String?
    var valueColor: Color = LoopDesign.Palette.ink
    /// The consensus target for the figure, e.g. "aim < 7%".
    var aim: String? = nil
    /// When the figure is less representative than usual, e.g. GMI over a short period.
    var caveat: String? = nil
    var id: String { label }
}

struct StatGridView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let tiles: [StatTile]

    /// Pairs of tiles, so both tiles in a row take the taller one's height; one per row at accessibility sizes.
    private var rows: [[StatTile]] {
        let shown = Array(tiles.prefix(6))
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        return stride(from: 0, to: shown.count, by: perRow).map { Array(shown[$0..<min($0 + perRow, shown.count)]) }
    }

    var body: some View {
        Grid(horizontalSpacing: LoopDesign.Space.s2, verticalSpacing: LoopDesign.Space.s2) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { tile in
                        tileView(tile)
                    }
                }
            }
        }
    }

    private func tileView(_ tile: StatTile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.label)
                .font(LoopDesign.Typeface.footnote)
                .foregroundStyle(P.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(tile.value)
                    .font(LoopDesign.Typeface.statValue)
                    .foregroundStyle(tile.valueColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let unit = tile.unit {
                    Text(unit)
                        .font(LoopDesign.Typeface.footnote)
                        .foregroundStyle(P.inkMuted)
                }
            }
            if let detail = tile.detail {
                // Not capped: a detail can run to two lines of its own, which wrap again at large sizes.
                Text(detail)
                    .font(LoopDesign.Typeface.footnote)
                    .foregroundStyle(P.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let aim = tile.aim {
                Text(aim)
                    .font(LoopDesign.Typeface.footnote)
                    .foregroundStyle(P.inkMuted)
            }
            if let caveat = tile.caveat {
                Text(caveat)
                    .font(LoopDesign.Typeface.caption)
                    .foregroundStyle(P.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LoopDesign.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(P.surfaceSunken, in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - TimeInRange

extension LoopHistoryMath.RangeBand {
    /// The band's name in the user's language.
    var localizedName: String {
        switch self {
        case .veryHigh: return NSLocalizedString("Very high", comment: "Time in range band: glucose above 250 mg/dL (13.9 mmol/L)")
        case .high: return NSLocalizedString("High", comment: "Time in range band: glucose 181–250 mg/dL (10.1–13.9 mmol/L)")
        case .inRange: return NSLocalizedString("In range", comment: "Time in range band: glucose 70–180 mg/dL (3.9–10.0 mmol/L)")
        case .low: return NSLocalizedString("Low", comment: "Time in range band: glucose 54–69 mg/dL (3.0–3.8 mmol/L)")
        case .veryLow: return NSLocalizedString("Very low", comment: "Time in range band: glucose below 54 mg/dL (3.0 mmol/L)")
        }
    }

    /// The consensus target for the band. High and low are aims for all time above or below range,
    /// so they say so; the others are the band's own.
    var localizedTarget: String {
        switch self {
        case .veryHigh: return ConsensusTarget.under(5)
        case .high: return String(format: NSLocalizedString("%1$@ above range", comment: "Time in range High row: the consensus target for all time above range, high and very high together. (1: target, e.g. < 25%)"), ConsensusTarget.under(25))
        case .inRange: return ConsensusTarget.over(70)
        case .low: return String(format: NSLocalizedString("%1$@ below range", comment: "Time in range Low row: the consensus target for all time below range, low and very low together. (1: target, e.g. < 4%)"), ConsensusTarget.under(4))
        case .veryLow: return ConsensusTarget.under(1)
        }
    }

    /// Consensus thresholds with the user's decimal separator, e.g. "3,9–10,0".
    func localizedThresholds(_ unit: GlucoseUnitStyle) -> String {
        let decimals = unit.isMmol ? 1 : 0
        let n: (Double) -> String = { LoopFormat.number($0, decimals: decimals) }
        switch (self, unit.isMmol) {
        case (.veryHigh, true): return "> " + n(13.9)
        case (.high, true): return n(10.1) + "–" + n(13.9)
        case (.inRange, true): return n(3.9) + "–" + n(10.0)
        case (.low, true): return n(3.0) + "–" + n(3.8)
        case (.veryLow, true): return "< " + n(3.0)
        case (.veryHigh, false): return "> " + n(250)
        case (.high, false): return n(181) + "–" + n(250)
        case (.inRange, false): return n(70) + "–" + n(180)
        case (.low, false): return n(54) + "–" + n(69)
        case (.veryLow, false): return "< " + n(54)
        }
    }
}

/// "12%" in the user's language.
private func percentText(_ value: Double, decimals: Int = 0) -> String {
    String(format: NSLocalizedString("%1$@%%", comment: "A percentage. (1: number)"), LoopFormat.number(value, decimals: decimals))
}

/// The international consensus targets for CGM metrics, written as "< 4%", "> 70%" or "≤ 36%".
enum ConsensusTarget {
    static func under(_ percent: Double) -> String { "< " + percentText(percent) }
    static func over(_ percent: Double) -> String { "> " + percentText(percent) }
    static func atMost(_ percent: Double) -> String { "≤ " + percentText(percent) }
    static func percent(_ percent: Double) -> String { percentText(percent) }

    /// "aim < 7%", under a figure.
    static func aim(_ target: String) -> String {
        String(format: NSLocalizedString("aim %1$@", comment: "Trends: the consensus target under a figure, in lower case. (1: target, e.g. < 7%)"), target)
    }
}

struct TimeInRangeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Fractions per band, 0–1, of the time with CGM readings.
    let fractions: [LoopHistoryMath.RangeBand: Double]
    /// Hours a day with CGM readings, so a band's hours leave out time without them.
    let hoursPerDay: Double
    let unit: GlucoseUnitStyle

    private var percentages: [LoopHistoryMath.RangeBand: Int] { LoopHistoryMath.roundedPercentages(fractions) }

    static func color(_ band: LoopHistoryMath.RangeBand) -> Color {
        switch band {
        case .veryHigh: return GlucoseBand.veryHigh.agpColor
        case .high: return GlucoseBand.high.agpColor
        case .inRange: return GlucoseBand.target.agpColor
        case .low: return GlucoseBand.low.agpColor
        case .veryLow: return GlucoseBand.veryLow.agpColor
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: LoopDesign.Space.s4) {
            bar
                .frame(width: 14)
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                ForEach(LoopHistoryMath.RangeBand.allCases) { band in
                    row(band)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var bar: some View {
        GeometryReader { geometry in
            let minimum: CGFloat = 4
            let bands = LoopHistoryMath.RangeBand.allCases
            let raw = bands.map { CGFloat(fractions[$0] ?? 0) }
            let floors = raw.map { $0 > 0 ? max(minimum, $0 * geometry.size.height) : 0 }
            let spare = geometry.size.height - floors.reduce(0, +)
            // Trim the space the minimums borrowed from the largest band.
            let largest = raw.indices.max { raw[$0] < raw[$1] } ?? 2
            VStack(spacing: 1) {
                ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                    let height = index == largest ? max(0, floors[index] + spare) : floors[index]
                    if height > 0 {
                        Rectangle().fill(Self.color(band)).frame(height: max(0, height - 1))
                    }
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityHidden(true)
    }

    private func row(_ band: LoopHistoryMath.RangeBand) -> some View {
        let fraction = fractions[band] ?? 0
        let hours = fraction * hoursPerDay
        let hoursText = String(format: NSLocalizedString("%1$@ h", comment: "Time in range row: average hours a day spent in the band, abbreviated. (1: hours with one decimal)"),
                               LoopFormat.number(hours, decimals: 1))
        let percent = Text(percentText(Double(percentages[band] ?? 0)))
            .font(LoopDesign.Typeface.statValueSmall)
            .foregroundStyle(P.ink)
        let name = Text(band.localizedName)
            .font(LoopDesign.Typeface.subhead)
            .foregroundStyle(P.ink)
        return Group {
            if typeSize.isAccessibilitySize {
                // One figure per line, so nothing is squeezed into a column.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s2) {
                        percent
                        name
                    }
                    Text(verbatim: "\(band.localizedThresholds(unit)) · \(hoursText) · \(band.localizedTarget)")
                        .font(LoopDesign.Typeface.footnote)
                        .foregroundStyle(P.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s2) {
                    percent.frame(minWidth: 52, alignment: .trailing)
                    name
                    Text(band.localizedThresholds(unit))
                        .font(LoopDesign.Typeface.footnote)
                        .foregroundStyle(P.inkMuted)
                    Spacer(minLength: LoopDesign.Space.s1)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(hoursText)
                            .font(LoopDesign.Typeface.footnote.monospacedDigit())
                        Text(band.localizedTarget)
                            .font(LoopDesign.Typeface.caption)
                    }
                    .foregroundStyle(P.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: NSLocalizedString("%1$@, %2$@ %3$@: %4$@ percent, %5$@ hours a day", comment: "VoiceOver label for a Time in range row. (1: band name, e.g. In range, 2: glucose thresholds, e.g. 3.9–10.0, 3: glucose unit, 4: percentage number, 5: average hours a day with one decimal)"),
                                   band.localizedName, band.localizedThresholds(unit), unit.unitName,
                                   LoopFormat.number(Double(percentages[band] ?? 0), decimals: 0), LoopFormat.number(hours, decimals: 1))
                            + ", " + ConsensusTarget.aim(band.localizedTarget))
    }
}

// MARK: - AGP

struct TrendsAGPChart: View {
    let slots: [LoopHistoryMath.AGPSlot]
    let readings: [GlucosePoint]
    let days: Int
    let unit: GlucoseUnitStyle
    let targetRange: ClosedRange<Double>?
    var height: CGFloat = 180

    private func v(_ mgdl: Double) -> Double {
        min(max(unit.value(mgdl), unit.agpDomain.lowerBound), unit.agpDomain.upperBound)
    }

    private static let hourTicks = [0, 360, 720, 1080, 1440]

    private static func label(minute: Int) -> String {
        let minute = minute % 1440
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date())!
        return DayAxis.hourLabel(date)
    }

    var enoughDays: Bool { days >= 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
            if readings.isEmpty {
                ChartPlaceholder(message: NSLocalizedString("No CGM data in this period", comment: "Trends chart placeholder when the period has no glucose readings"), height: height)
            } else {
                chart.frame(height: height)
                if !enoughDays {
                    Text(String(format: NSLocalizedString("Not enough days for a pattern: %1$@ of 5", comment: "Trends Daily pattern footnote when fewer than 5 days have readings; the chart shows raw readings instead. (1: days with readings)"),
                                LoopFormat.number(Double(days), decimals: 0)))
                        .font(LoopDesign.Typeface.footnote)
                        .foregroundStyle(P.inkMuted)
                }
            }
        }
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private var chart: some View {
        Chart {
            if let targetRange {
                RectangleMark(xStart: .value("Start", 0), xEnd: .value("End", 1440),
                              yStart: .value("Low", v(targetRange.lowerBound)), yEnd: .value("High", v(targetRange.upperBound)))
                    .foregroundStyle(P.targetBand)
            }
            if enoughDays {
                ForEach(slots, id: \.minute) { slot in
                    AreaMark(x: .value("Time", slot.minute), yStart: .value("5%", v(slot.p5)), yEnd: .value("95%", v(slot.p95)), series: .value("Band", "outer"))
                        .foregroundStyle(P.agpOuter)
                        .interpolationMethod(.monotone)
                }
                ForEach(slots, id: \.minute) { slot in
                    AreaMark(x: .value("Time", slot.minute), yStart: .value("25%", v(slot.p25)), yEnd: .value("75%", v(slot.p75)), series: .value("Band", "inner"))
                        .foregroundStyle(P.agpInner)
                        .interpolationMethod(.monotone)
                }
                ForEach(slots, id: \.minute) { slot in
                    LineMark(x: .value("Time", slot.minute), y: .value("Median", v(slot.p50)), series: .value("Band", "median"))
                        .foregroundStyle(P.glucose)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                }
            } else {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, point in
                    PointMark(x: .value("Time", minuteOfDay(point.date)), y: .value("Glucose", v(point.mgdl)))
                        .symbolSize(8)
                        .foregroundStyle(P.glucose)
                }
            }
        }
        .chartXScale(domain: 0...1440)
        .chartYScale(domain: unit.agpDomain)
        .chartXAxis {
            AxisMarks(values: Self.hourTicks) { value in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel {
                    if let minute = value.as(Int.self) { Text(Self.label(minute: minute)) }
                }
                .font(LoopDesign.Typeface.caption)
                .foregroundStyle(P.inkMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: unit.agpTicks) { _ in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel().font(LoopDesign.Typeface.caption).foregroundStyle(P.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard enoughDays, let high = slots.max(by: { $0.p50 < $1.p50 }), let low = slots.min(by: { $0.p50 < $1.p50 }) else {
            return NSLocalizedString("Daily pattern: not enough days", comment: "VoiceOver label for the Trends Daily pattern chart when fewer than 5 days have readings")
        }
        let span = String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: "A number of days, e.g. a Trends period or how many days are averaged. (1: number of days)"), days)
        return String(format: NSLocalizedString("Daily pattern over %1$@. Median highest %2$@ at %3$@, lowest %4$@ at %5$@", comment: "VoiceOver label for the Trends Daily pattern chart. (1: days with readings, e.g. 14 days; 2: highest median glucose; 3: time of day; 4: lowest median glucose; 5: time of day)"),
                      span, unit.format(high.p50), Self.label(minute: high.minute), unit.format(low.p50), Self.label(minute: low.minute))
    }
}

// MARK: - InsulinSplit

/// Basal against bolus in one capsule: basal, then manual bolus, then automatic bolus.
struct InsulinSplitBar: View {
    let split: InsulinSplit
    /// A 6-point line for list headers. It is still tall enough to show the automatic bolus stripes.
    var hairline = false
    @Environment(\.colorScheme) private var scheme

    private enum Part: CaseIterable { case basal, manual, automatic }

    private func units(_ part: Part) -> Double {
        switch part {
        case .basal: return split.basal
        // Unclassified bolus draws as plain bolus.
        case .manual: return split.manualBolus + split.unclassifiedBolus
        case .automatic: return split.automaticBolus
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let parts = Part.allCases.filter { units($0) > 0 }
            let gap: CGFloat = hairline ? 1.5 : 2.5
            let width = geometry.size.width - gap * CGFloat(max(0, parts.count - 1))
            let minimum: CGFloat = hairline ? 2 : 4
            let widths = parts.map { max(minimum, width * units($0) / max(split.total, .ulpOfOne)) }
            // Take what the minimums add from the widest part, so the bar keeps its length.
            let excess = widths.reduce(0, +) - width
            let widest = widths.indices.max { widths[$0] < widths[$1] }
            HStack(spacing: gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    segment(part).frame(width: max(0, widths[index] - (index == widest ? excess : 0)))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: hairline ? 6 : 14)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segment(_ part: Part) -> some View {
        switch part {
        case .basal:
            Rectangle().fill(LoopDesign.Palette.basal)
                .overlay(alignment: .trailing) {
                    if !hairline { Rectangle().fill(LoopDesign.Palette.basalEdge).frame(width: 2) }
                }
        case .manual:
            Rectangle().fill(LoopDesign.Palette.bolus)
        case .automatic:
            Rectangle().fill(Hatch.paint(LoopDesign.Palette.bolus, scheme: scheme))
        }
    }
}

/// Basal and bolus in units and shares, how the bolus divides, and the total.
struct InsulinSplitView: View {
    let split: InsulinSplit
    /// Today so far, rather than a whole day or a per-day average.
    var partial = false
    /// What the basal schedule delivers over the same time, shown under the basal row.
    var scheduledBasal: Double?
    /// How many of the days the schedule covers, e.g. "20 of 90 days", when that is fewer than the split's.
    var scheduledNote: String?
    /// Today against a usual day, e.g. "Usually 28.4 U by 19:46", under the total.
    var usual: String?
    /// The split as one capsule, where no chart above already draws it.
    var showsBar = true
    /// The total is the dashed average line of the chart above, so it carries that line's swatch.
    var averageLine = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s3) {
            if showsBar {
                InsulinSplitBar(split: split)
            }
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                row(.basal, NSLocalizedString("Basal", comment: "Basal and bolus row: insulin delivered as basal"), split.basal, split.basalPercent)
                // No swatch: nothing on the chart draws the schedule.
                if let scheduledBasal {
                    Text(Self.scheduledText(scheduledBasal, note: scheduledNote))
                        .font(LoopDesign.Typeface.footnote.monospacedDigit())
                        .foregroundStyle(LoopDesign.Palette.inkMuted)
                        .padding(.leading, 10 + LoopDesign.Space.s2)
                }
                row(.solid(LoopDesign.Palette.bolus), NSLocalizedString("Bolus", comment: "Basal and bolus row: insulin delivered as bolus, manual and automatic"), split.bolus, split.bolusPercent)
                // Manual, automatic and unknown add up to the bolus row. Unknown has no swatch of its own: it is drawn
                // as plain bolus, like manual.
                if split.bolus >= 0.005 {
                    FlowLayout(spacing: LoopDesign.Space.s3, lineSpacing: 2) {
                        if showsBolusDetail {
                            part(.solid(LoopDesign.Palette.bolus), String(format: NSLocalizedString("Manual %1$@", comment: "Basal and bolus: bolus the person gave. (1: units, e.g. 16.2 U)"), LoopFormat.totalUnits(split.manualBolus)))
                            part(.hatch(LoopDesign.Palette.bolus), String(format: NSLocalizedString("Automatic %1$@", comment: "Basal and bolus: bolus Loop gave automatically. (1: units, e.g. 5.4 U)"), LoopFormat.totalUnits(split.automaticBolus)))
                        }
                        if !split.isClassified {
                            Text(Self.unknownText(split.unclassifiedBolus))
                        }
                    }
                    .font(LoopDesign.Typeface.footnote.monospacedDigit())
                    .foregroundStyle(LoopDesign.Palette.inkMuted)
                    .padding(.leading, 10 + LoopDesign.Space.s2)
                }
                Divider().padding(.vertical, 2)
                HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s2) {
                    if averageLine {
                        LegendSwatch(swatch: .dash(LoopDesign.Palette.ink)).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                    }
                    Text(partial
                         ? NSLocalizedString("Total so far", comment: "Basal and bolus total row for today, which isn't over yet")
                         : NSLocalizedString("Total", comment: "Basal and bolus total row: basal plus bolus"))
                        .font(LoopDesign.Typeface.subhead.weight(.semibold))
                        .foregroundStyle(LoopDesign.Palette.ink)
                    Spacer()
                    Text(LoopFormat.totalUnits(split.total))
                        .font(LoopDesign.Typeface.statValueSmall)
                        .foregroundStyle(LoopDesign.Palette.ink)
                }
                if let usual {
                    Text(usual)
                        .font(LoopDesign.Typeface.footnote.monospacedDigit())
                        .foregroundStyle(LoopDesign.Palette.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(split, partial: partial, scheduledBasal: scheduledBasal.map { Self.scheduledText($0, note: scheduledNote) },
                                                    showsBolusDetail: showsBolusDetail, usual: usual))
    }

    /// Manual and automatic, when any bolus says which it was; a split that is all unknown shows only that.
    private var showsBolusDetail: Bool {
        split.manualBolus + split.automaticBolus >= 0.005
    }

    /// "3.2 U unknown": bolus whose record doesn't say whether it was manual or automatic.
    private static func unknownText(_ units: Double) -> String {
        String(format: NSLocalizedString("%1$@ unknown", comment: "Basal and bolus: bolus whose record doesn't say whether it was manual or automatic, such as some in Apple Health, after the manual and automatic amounts. (1: units, e.g. 3.2 U)"), LoopFormat.totalUnits(units))
    }

    /// "Scheduled 18.0 U", or "Scheduled 18.0 U · 20 of 90 days" when the schedule is known for only some days.
    private static func scheduledText(_ units: Double, note: String?) -> String {
        let text = String(format: NSLocalizedString("Scheduled %1$@", comment: "Basal and bolus: what the basal schedule delivers over the same time, under the basal row. (1: units, e.g. 18.0 U)"), LoopFormat.totalUnits(units))
        return note.map { "\(text) · \($0)" } ?? text
    }

    private func row(_ swatch: LegendItem.Swatch, _ label: String, _ units: Double, _ percent: Int) -> some View {
        let amount = HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s2) {
            Text(LoopFormat.totalUnits(units))
                .font(LoopDesign.Typeface.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(LoopDesign.Palette.ink)
            Text(verbatim: "\(percent)%")
                .font(LoopDesign.Typeface.footnote.monospacedDigit())
                .foregroundStyle(LoopDesign.Palette.inkMuted)
                .frame(minWidth: typeSize.isAccessibilitySize ? nil : 38, alignment: .trailing)
        }
        return AdaptiveRow(spacing: typeSize.isAccessibilitySize ? 0 : LoopDesign.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s2) {
                LegendSwatch(swatch: swatch).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(label)
                    .font(LoopDesign.Typeface.subhead)
                    .foregroundStyle(LoopDesign.Palette.ink)
            }
            if !typeSize.isAccessibilitySize {
                Spacer()
            }
            amount
        }
    }

    private func part(_ swatch: LegendItem.Swatch, _ text: String) -> some View {
        HStack(spacing: LoopDesign.Space.s1) {
            LegendSwatch(swatch: swatch)
            Text(text)
        }
    }

    static func accessibilityLabel(_ split: InsulinSplit, partial: Bool, scheduledBasal: String? = nil, showsBolusDetail: Bool = false,
                                   usual: String? = nil) -> String {
        var parts = [
            String(format: NSLocalizedString("Basal %1$@, %2$@ percent", comment: "VoiceOver: basal units and share. (1: units, 2: percentage number)"), LoopFormat.totalUnits(split.basal), "\(split.basalPercent)"),
            String(format: NSLocalizedString("Bolus %1$@, %2$@ percent", comment: "VoiceOver: bolus units and share. (1: units, 2: percentage number)"), LoopFormat.totalUnits(split.bolus), "\(split.bolusPercent)"),
        ]
        if showsBolusDetail {
            let text = String(format: NSLocalizedString("%1$@ manual, %2$@ automatic", comment: "VoiceOver: how the bolus divides. (1: manual units, 2: automatic units)"),
                              LoopFormat.totalUnits(split.manualBolus), LoopFormat.totalUnits(split.automaticBolus))
            parts.append(split.isClassified ? text : "\(text), \(unknownText(split.unclassifiedBolus))")
        } else if !split.isClassified {
            parts.append(unknownText(split.unclassifiedBolus))
        }
        parts.append(String(format: partial
                            ? NSLocalizedString("Total so far %1$@", comment: "VoiceOver: today's total insulin so far. (1: units)")
                            : NSLocalizedString("Total %1$@", comment: "VoiceOver: total insulin. (1: units)"),
                            LoopFormat.totalUnits(split.total)))
        if let scheduledBasal {
            parts.insert(scheduledBasal, at: 1)
        }
        if let usual {
            parts.append(usual)
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - InsulinDailyTotals

struct InsulinDailyTotalsView: View {
    let totals: [LoopHistoryMath.DayTotal]
    /// Weekly averages instead of days, for periods past 30 days.
    let weekly: Bool
    /// Calculated from the original daily totals, even when the bars are weekly averages.
    let average: Double
    var height: CGFloat = 170
    @Environment(\.colorScheme) private var scheme

    private var yMax: Double {
        let top = max(totals.map(\.total).max() ?? 0, average)
        return max(10, Self.niceStep(top / 4) * 5)
    }

    struct BolusPart: Equatable {
        let start: Double
        let end: Double
        let automatic: Bool
    }

    /// Where a day's bolus parts sit above its basal: manual (with bolus of unknown kind), then automatic. Each
    /// starts a gap of the card's colour above the part below it, so no two parts touch. A part taller than two gaps
    /// gives the gap from its own height; a shorter one moves up by a gap instead, so it stays visible.
    static func bolusParts(_ day: LoopHistoryMath.DayTotal, gap: Double) -> [BolusPart] {
        var parts: [BolusPart] = []
        var below = day.basal
        for (units, automatic) in [(day.split.manualBolus + day.split.unclassifiedBolus, false), (day.split.automaticBolus, true)] where units > 0 {
            let start = below + gap
            let end = units > gap * 2 ? below + units : start + units
            parts.append(BolusPart(start: start, end: end, automatic: automatic))
            below = end
        }
        return parts
    }

    /// 1, 2 or 5 times a power of ten, at or above `raw`.
    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let nice: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10
        return nice * magnitude
    }

    var body: some View {
        if totals.allSatisfy({ $0.total == 0 }) {
            ChartPlaceholder(message: NSLocalizedString("No insulin recorded in this period", comment: "Trends Insulin per day chart placeholder when no insulin was delivered in the period"), height: height)
        } else {
            chart.frame(height: height)
        }
    }

    private var unitWidth: Calendar.Component { weekly ? .weekOfYear : .day }

    private var chart: some View {
        Chart {
            ForEach(totals) { day in
                BarMark(x: .value("Day", day.day, unit: unitWidth), yStart: .value("Base", 0), yEnd: .value("Basal", day.basal), width: .ratio(0.7))
                    .foregroundStyle(P.basal)
                BarMark(x: .value("Day", day.day, unit: unitWidth), yStart: .value("Basal", max(0, day.basal - yMax * 0.006)), yEnd: .value("Edge", day.basal), width: .ratio(0.7))
                    .foregroundStyle(P.basalEdge)
                ForEach(Self.bolusParts(day, gap: yMax * 0.015), id: \.automatic) { part in
                    BarMark(x: .value("Day", day.day, unit: unitWidth), yStart: .value("Bolus start", part.start), yEnd: .value("Bolus end", part.end), width: .ratio(0.7))
                        .foregroundStyle(part.automatic ? AnyShapeStyle(Hatch.paint(P.bolus, scheme: scheme)) : AnyShapeStyle(P.bolus))
                }
            }
            // The average's value is the Total row under the chart.
            RuleMark(y: .value("Average", average))
                .foregroundStyle(P.ink)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(date))
                            .multilineTextAlignment(.center)
                    }
                }
                .font(LoopDesign.Typeface.caption)
                .foregroundStyle(P.inkMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(P.grid)
                AxisValueLabel().font(LoopDesign.Typeface.caption).foregroundStyle(P.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: weekly
            ? NSLocalizedString("Insulin per day, weekly average, average %1$@", comment: "VoiceOver label for the Trends Insulin per day chart when bars are weekly averages. (1: average insulin per day, e.g. 32.1 U)")
            : NSLocalizedString("Insulin per day, average %1$@", comment: "VoiceOver label for the Trends Insulin per day chart. (1: average insulin per day, e.g. 32.1 U)"),
            LoopFormat.totalUnits(average)))
    }

    private var axisDates: [Date] {
        if weekly {
            let stride = max(1, Int(ceil(Double(totals.count) / 6)))
            return totals.enumerated().compactMap { index, total in index % stride == 0 ? total.day : nil }
        }
        if totals.count > 14 {
            return totals.map(\.day).filter { Calendar.current.component(.weekday, from: $0) == 2 }
        }
        return totals.map(\.day)
    }

    private func axisLabel(_ date: Date) -> String {
        if weekly {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        let weekday = String(date.formatted(.dateTime.weekday(.narrow)))
        if totals.count <= 14 {
            let first = totals.first?.day == date, last = totals.last?.day == date
            let isMonday = Calendar.current.component(.weekday, from: date) == 2
            return first || last || isMonday ? "\(weekday)\n\(date.formatted(.dateTime.day()))" : weekday
        }
        // 30 days: label every Monday only.
        return Calendar.current.component(.weekday, from: date) == 2 ? date.formatted(.dateTime.day().month(.abbreviated)) : ""
    }
}

// MARK: - LoopModeBar

struct LoopModeBarView: View {
    let spans: [LoopModeSpan]
    @Environment(\.dynamicTypeSize) private var typeSize

    private var total: TimeInterval { spans.reduce(0) { $0 + $1.duration } }

    static func color(_ mode: LoopModeSpan.Mode) -> Color {
        switch mode {
        case .closed: return P.statusAutomated
        case .limited: return P.statusWarning
        case .open: return P.inkMuted
        }
    }

    static func name(_ mode: LoopModeSpan.Mode) -> String {
        switch mode {
        case .closed: return NSLocalizedString("Closed loop", comment: "Trends Loop status: time Loop was running in closed loop")
        case .limited: return NSLocalizedString("Limited", comment: "Trends Loop status: time closed loop was on but Loop wasn't completing runs")
        case .open: return NSLocalizedString("Open loop / manual", comment: "Trends Loop status: time closed loop was switched off")
        }
    }

    private let modes: [LoopModeSpan.Mode] = [.closed, .limited, .open]

    var body: some View {
        if total <= 0 {
            ChartPlaceholder(message: NSLocalizedString("No loop runs recorded in this period", comment: "Trends Loop status placeholder when there is no Loop run history for the period"), height: 60)
        } else {
            VStack(spacing: LoopDesign.Space.s3) {
                bar.frame(height: 10)
                ForEach(modes, id: \.self) { mode in
                    row(mode)
                }
            }
        }
    }

    private func fraction(_ mode: LoopModeSpan.Mode) -> Double {
        LoopHistoryMath.duration(of: mode, in: spans) / total
    }

    private var bar: some View {
        GeometryReader { geometry in
            let minimum: CGFloat = 4
            let widths = modes.map { fraction($0) > 0 ? max(minimum, fraction($0) * geometry.size.width) : 0 }
            let excess = widths.reduce(0, +) - geometry.size.width
            HStack(spacing: 1) {
                ForEach(Array(modes.enumerated()), id: \.offset) { index, mode in
                    if widths[index] > 0 {
                        Rectangle()
                            .fill(Self.color(mode))
                            .frame(width: max(0, index == 0 ? widths[index] - excess - 2 : widths[index]))
                    }
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityHidden(true)
    }

    private func row(_ mode: LoopModeSpan.Mode) -> some View {
        let duration = LoopHistoryMath.duration(of: mode, in: spans)
        let name = HStack(spacing: LoopDesign.Space.s2) {
            Circle().fill(Self.color(mode)).frame(width: 8, height: 8)
            Text(Self.name(mode))
                .font(LoopDesign.Typeface.subhead)
                .foregroundStyle(P.ink)
        }
        let time = Text(verbatim: "· \(LoopFormat.duration(duration))")
            .font(LoopDesign.Typeface.footnote)
            .foregroundStyle(P.inkMuted)
        let percent = Text(percentText(fraction(mode) * 100, decimals: 1))
            .font(LoopDesign.Typeface.statValueSmall)
            .foregroundStyle(P.ink)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    name
                    HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s2) {
                        percent
                        time
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: LoopDesign.Space.s2) {
                    name
                    time
                    Spacer()
                    percent
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
