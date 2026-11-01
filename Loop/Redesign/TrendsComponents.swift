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
            HStack(spacing: 2) {
                ForEach(TrendsPeriod.allCases) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { period = option }
                    } label: {
                        Text(option.label)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(P.ink)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background {
                                if option == period {
                                    Capsule().fill(P.controlThumb).shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityName)
                    .accessibilityAddTraits(option == period ? .isSelected : [])
                }
            }
            .padding(2)
            .background(P.surfaceSunken, in: Capsule())

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
                Text(detail)
                    .font(LoopDesign.Typeface.footnote)
                    .foregroundStyle(P.inkMuted)
                    .lineLimit(2)
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

struct TimeInRangeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Fractions per band, 0–1.
    let fractions: [LoopHistoryMath.RangeBand: Double]
    let unit: GlucoseUnitStyle

    private var percentages: [LoopHistoryMath.RangeBand: Int] { LoopHistoryMath.roundedPercentages(fractions) }

    static func color(_ band: LoopHistoryMath.RangeBand) -> Color {
        switch band {
        case .veryHigh: return P.rangeVeryHigh
        case .high: return P.rangeHigh
        case .inRange: return P.rangeIn
        case .low: return P.rangeLow
        case .veryLow: return P.rangeVeryLow
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: LoopDesign.Space.s4) {
            bar
                .frame(width: 14)
            VStack(spacing: LoopDesign.Space.s2) {
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
        let hours = fraction * 24
        let thresholds = Text(band.localizedThresholds(unit))
            .font(LoopDesign.Typeface.footnote)
            .foregroundStyle(P.inkMuted)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s2) {
                Text(percentText(Double(percentages[band] ?? 0)))
                    .font(LoopDesign.Typeface.statValueSmall)
                    .foregroundStyle(P.ink)
                    .frame(minWidth: typeSize.isAccessibilitySize ? nil : 52, alignment: .trailing)
                Text(band.localizedName)
                    .font(LoopDesign.Typeface.subhead)
                    .foregroundStyle(P.ink)
                if !typeSize.isAccessibilitySize {
                    thresholds
                }
                Spacer(minLength: LoopDesign.Space.s1)
                Text(String(format: NSLocalizedString("%1$@ h", comment: "Time in range row: average hours a day spent in the band, abbreviated. (1: hours with one decimal)"),
                            LoopFormat.number(hours, decimals: 1)))
                    .font(LoopDesign.Typeface.footnote.monospacedDigit())
                    .foregroundStyle(P.inkMuted)
            }
            if typeSize.isAccessibilitySize {
                thresholds
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: NSLocalizedString("%1$@, %2$@ %3$@: %4$@ percent, %5$@ hours a day", comment: "VoiceOver label for a Time in range row. (1: band name, e.g. In range, 2: glucose thresholds, e.g. 3.9–10.0, 3: glucose unit, 4: percentage number, 5: average hours a day with one decimal)"),
                                   band.localizedName, band.localizedThresholds(unit), unit.unitName,
                                   LoopFormat.number(Double(percentages[band] ?? 0), decimals: 0), LoopFormat.number(hours, decimals: 1)))
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

/// The basal and bolus card body: the bar, units and shares, how the bolus divides, and the total.
struct InsulinSplitView: View {
    let split: InsulinSplit
    /// Today so far, rather than a whole day or a per-day average.
    var partial = false
    /// What the basal schedule delivers over the same time, shown under the basal row.
    var scheduledBasal: Double?
    /// Today against a usual day, e.g. "Usually 28.4 U by 19:46", under the total.
    var usual: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s3) {
            InsulinSplitBar(split: split)
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                row(.basal, NSLocalizedString("Basal", comment: "Basal and bolus row: insulin delivered as basal"), split.basal, split.basalPercent)
                if let scheduledBasal {
                    part(.dash(LoopDesign.Palette.basalScheduled), String(format: NSLocalizedString("Scheduled %1$@", comment: "Basal and bolus: what the basal schedule delivers over the same time, under the basal row. (1: units, e.g. 18.0 U)"), LoopFormat.totalUnits(scheduledBasal)))
                        .font(LoopDesign.Typeface.footnote.monospacedDigit())
                        .foregroundStyle(LoopDesign.Palette.inkMuted)
                        .padding(.leading, 10 + LoopDesign.Space.s2)
                }
                row(.solid(LoopDesign.Palette.bolus), NSLocalizedString("Bolus", comment: "Basal and bolus row: insulin delivered as bolus, manual and automatic"), split.bolus, split.bolusPercent)
                if split.isClassified && split.bolus > 0 {
                    FlowLayout(spacing: LoopDesign.Space.s3, lineSpacing: 2) {
                        part(.solid(LoopDesign.Palette.bolus), String(format: NSLocalizedString("Manual %1$@", comment: "Basal and bolus: bolus the person gave. (1: units, e.g. 16.2 U)"), LoopFormat.totalUnits(split.manualBolus)))
                        part(.hatch(LoopDesign.Palette.bolus), String(format: NSLocalizedString("Automatic %1$@", comment: "Basal and bolus: bolus Loop gave automatically. (1: units, e.g. 5.4 U)"), LoopFormat.totalUnits(split.automaticBolus)))
                    }
                    .font(LoopDesign.Typeface.footnote.monospacedDigit())
                    .foregroundStyle(LoopDesign.Palette.inkMuted)
                    .padding(.leading, 10 + LoopDesign.Space.s2)
                }
                Divider().padding(.vertical, 2)
                HStack(alignment: .firstTextBaseline) {
                    Text(partial
                         ? NSLocalizedString("Total so far", comment: "Basal and bolus total row for today, which isn't over yet")
                         : NSLocalizedString("Total", comment: "Basal and bolus total row: basal plus bolus"))
                        .font(LoopDesign.Typeface.subhead.weight(.semibold))
                        .foregroundStyle(LoopDesign.Palette.ink)
                    Spacer()
                    Text(LoopFormat.totalUnits(split.total))
                        .font(LoopDesign.Typeface.statValueSmall)
                        .foregroundStyle(LoopDesign.Palette.insulinInk)
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
        .accessibilityLabel(Self.accessibilityLabel(split, partial: partial, scheduledBasal: scheduledBasal, usual: usual))
    }

    private func row(_ swatch: LegendItem.Swatch, _ label: String, _ units: Double, _ percent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LoopDesign.Space.s2) {
            LegendSwatch(swatch: swatch).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(label)
                .font(LoopDesign.Typeface.subhead)
                .foregroundStyle(LoopDesign.Palette.ink)
            Spacer()
            Text(LoopFormat.totalUnits(units))
                .font(LoopDesign.Typeface.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(LoopDesign.Palette.ink)
            Text(verbatim: "\(percent)%")
                .font(LoopDesign.Typeface.footnote.monospacedDigit())
                .foregroundStyle(LoopDesign.Palette.inkMuted)
                .frame(minWidth: 38, alignment: .trailing)
        }
    }

    private func part(_ swatch: LegendItem.Swatch, _ text: String) -> some View {
        HStack(spacing: LoopDesign.Space.s1) {
            LegendSwatch(swatch: swatch)
            Text(text)
        }
    }

    static func accessibilityLabel(_ split: InsulinSplit, partial: Bool, scheduledBasal: Double? = nil, usual: String? = nil) -> String {
        var parts = [
            String(format: NSLocalizedString("Basal %1$@, %2$@ percent", comment: "VoiceOver: basal units and share. (1: units, 2: percentage number)"), LoopFormat.totalUnits(split.basal), "\(split.basalPercent)"),
            String(format: NSLocalizedString("Bolus %1$@, %2$@ percent", comment: "VoiceOver: bolus units and share. (1: units, 2: percentage number)"), LoopFormat.totalUnits(split.bolus), "\(split.bolusPercent)"),
        ]
        if split.isClassified && split.bolus > 0 {
            parts.append(String(format: NSLocalizedString("%1$@ manual, %2$@ automatic", comment: "VoiceOver: how the bolus divides. (1: manual units, 2: automatic units)"),
                                LoopFormat.totalUnits(split.manualBolus), LoopFormat.totalUnits(split.automaticBolus)))
        }
        parts.append(String(format: partial
                            ? NSLocalizedString("Total so far %1$@", comment: "VoiceOver: today's total insulin so far. (1: units)")
                            : NSLocalizedString("Total %1$@", comment: "VoiceOver: total insulin. (1: units)"),
                            LoopFormat.totalUnits(split.total)))
        if let scheduledBasal {
            parts.insert(String(format: NSLocalizedString("Scheduled %1$@", comment: "Basal and bolus: what the basal schedule delivers over the same time, under the basal row. (1: units, e.g. 18.0 U)"), LoopFormat.totalUnits(scheduledBasal)), at: 1)
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
    var onSelectDay: ((Date) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    private var yMax: Double {
        let top = max(totals.map(\.total).max() ?? 0, average)
        return max(10, IOBCOBChartView.niceStep(top / 4) * 5)
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
                // A thin gap under each bolus part, so it never touches the part below it
                let gap = yMax * 0.01
                let manualTop = day.basal + day.split.manualBolus + day.split.unclassifiedBolus
                BarMark(x: .value("Day", day.day, unit: unitWidth), yStart: .value("Basal", day.basal + (manualTop - day.basal > gap * 2 ? gap : 0)), yEnd: .value("Bolus", manualTop), width: .ratio(0.7))
                    .foregroundStyle(P.bolus)
                if day.split.automaticBolus > 0 {
                    BarMark(x: .value("Day", day.day, unit: unitWidth), yStart: .value("Bolus", manualTop + (day.total - manualTop > gap * 2 ? gap : 0)), yEnd: .value("Total", day.total), width: .ratio(0.7))
                        .foregroundStyle(Hatch.paint(P.bolus, scheme: scheme))
                }
            }
            RuleMark(y: .value("Average", average))
                .foregroundStyle(P.ink)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text(LoopFormat.number(average, decimals: 1))
                        .font(LoopDesign.Typeface.caption.weight(.semibold))
                        .foregroundStyle(P.ink)
                }
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let onSelectDay, !weekly, let frame = proxy.plotFrame else { return }
                        let x = location.x - geometry[frame].origin.x
                        if let date: Date = proxy.value(atX: x),
                           let day = totals.min(by: { abs($0.day.addingTimeInterval(43200).timeIntervalSince(date)) < abs($1.day.addingTimeInterval(43200).timeIntervalSince(date)) }) {
                            onSelectDay(day.day)
                        }
                    }
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
        return HStack(spacing: LoopDesign.Space.s2) {
            Circle().fill(Self.color(mode)).frame(width: 8, height: 8)
            Text(Self.name(mode))
                .font(LoopDesign.Typeface.subhead)
                .foregroundStyle(P.ink)
            Text("· \(LoopFormat.duration(duration))")
                .font(LoopDesign.Typeface.footnote)
                .foregroundStyle(P.inkMuted)
            Spacer()
            Text(percentText(fraction(mode) * 100, decimals: 1))
                .font(LoopDesign.Typeface.statValueSmall)
                .foregroundStyle(P.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LoopGapsList: View {
    let spans: [LoopModeSpan]

    private var gaps: [LoopModeSpan] {
        spans.filter { $0.mode != .closed }.sorted { $0.start > $1.start }
    }

    var body: some View {
        List {
            if gaps.isEmpty {
                Text(NSLocalizedString("No gaps: Loop ran closed loop all through this period.", comment: "Trends Gaps list when Loop was in closed loop for the whole period"))
                    .foregroundStyle(P.inkMuted)
            }
            ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
                HStack(alignment: .top, spacing: LoopDesign.Space.s3) {
                    Circle().fill(LoopModeBarView.color(gap.mode)).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gap.cause ?? LoopModeBarView.name(gap.mode))
                            .font(LoopDesign.Typeface.body)
                        Text("\(gap.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) · \(LoopFormat.duration(gap.duration))")
                            .font(LoopDesign.Typeface.footnote)
                            .foregroundStyle(P.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle(NSLocalizedString("Gaps", comment: "Trends Loop status button and screen title: list of times Loop wasn't in closed loop"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
