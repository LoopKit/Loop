//
//  TrendsScreen.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit

private typealias P = LoopDesign.Palette

/// The period review: everything on the screen follows one RangeSelector period.
@MainActor
final class TrendsModel: ObservableObject {

    struct Summary {
        var interval: DateInterval
        var unit: GlucoseUnitStyle
        /// CGM readings only: typed-in fingersticks are left out of every figure, as on Statistics.
        var glucose: [GlucosePoint] = []
        /// Days from the first reading, when that is short of the period; nil when the readings span it.
        var cgmCoveredDays: Int?
        var stats: LoopHistoryMath.GlucoseStats?
        var cgmActive: Double = 0
        var timeInRange: [LoopHistoryMath.RangeBand: Double] = [:]
        var agp: [LoopHistoryMath.AGPSlot] = []
        var agpDays = 0
        var totals: [LoopHistoryMath.DayTotal] = []
        /// Carbs and bolus counts cover only the days per-day figures divide by (see `dataDays`).
        var carbGrams = 0.0
        var carbEntries = 0
        var carbsByDay: [Date: Double] = [:]
        var manualBoluses = 0
        var automaticBoluses = 0
        var loopSpans: [LoopModeSpan] = []
        var targetRange: ClosedRange<Double>?
        /// The whole calendar day, for a one-day period: drawn as one timeline.
        var day: DayHistory?
        var dayTargets: [TargetBand] = []
        /// What the basal schedule delivers over the same days the split averages.
        var scheduledBasal: Double?
        /// The median insulin by this time of day over the last 14 days, when the period ends now.
        var typicalByNow: (typical: TypicalInsulinDelivery, at: Date)?

        /// The days per-day figures divide by: insulin's averaging days, or complete days with CGM data when there is
        /// no insulin (today only when no complete day has any), never the period length.
        var dataDays = 0
        var days: Double { Double(max(1, dataDays)) }
        var basalUnits: Double { LoopHistoryMath.averagingDays(totals).reduce(0) { $0 + $1.basal } }
        var bolusUnits: Double { LoopHistoryMath.averagingDays(totals).reduce(0) { $0 + $1.bolus } }
        var insulinPerDay: Double { LoopHistoryMath.averageDailyInsulin(totals) }
        var basalShare: Double { basalUnits + bolusUnits > 0 ? basalUnits / (basalUnits + bolusUnits) : 0 }
        /// Per day over the averaged days; a single day in progress when that is all there is.
        var split: InsulinSplit { InsulinSplit.average(LoopHistoryMath.averagingDays(totals).map(\.split)) }
        /// The split is today's total so far rather than an average of complete days.
        var splitIsPartial: Bool { LoopHistoryMath.averagingDays(totals).allSatisfy { !$0.isComplete } }
    }

    @Published var period: TrendsPeriod = .twoWeeks
    @Published var endDay = Date()
    @Published private(set) var summary: Summary?
    @Published private(set) var loading = false
    @Published private(set) var loadError: String?

    let provider: LoopHistoryProvider
    private var loadTask: Task<Void, Never>?

    init(provider: LoopHistoryProvider) {
        self.provider = provider
    }

    var interval: DateInterval { period.interval(endingOn: endDay) }

    func reload() {
        loadTask?.cancel()
        let interval = self.interval
        let oneDay = period == .day
        loading = true
        summary = nil
        loadError = nil
        loadTask = Task {
            do {
                let result = try await Self.load(provider: provider, interval: interval, oneDay: oneDay)
                guard !Task.isCancelled else { return }
                self.summary = result
            } catch {
                guard !Task.isCancelled else { return }
                self.loadError = error.localizedDescription
            }
            self.loading = false
        }
    }

    private static func load(provider: LoopHistoryProvider, interval: DateInterval, oneDay: Bool) async throws -> Summary {
        var summary = Summary(interval: interval, unit: provider.unitStyle)
        summary.targetRange = provider.glucoseTargetRange

        // A single day is read to midnight, as Today so far is, so the scheduled basal still to come is drawn.
        let fetchWindow = oneDay ? DateInterval(start: interval.start, end: Calendar.current.date(byAdding: .day, value: 1, to: interval.start)!) : interval
        async let historyFetch = provider.dayHistory(fetchWindow, includeOnBoard: false)
        async let runsFetch = provider.loopRuns()
        var history = try await historyFetch
        let (runs, coverageStart) = try await runsFetch
        if oneDay {
            summary.day = history
            summary.dayTargets = try await provider.glucoseTargetBands(in: fetchWindow)
            history = history.clipped(to: interval)
        }

        let cgm = history.glucose.filter { !$0.userEntered }
        summary.glucose = cgm
        summary.stats = LoopHistoryMath.glucoseStats(cgm)
        summary.cgmActive = LoopHistoryMath.cgmActiveFraction(cgm, over: interval)
        summary.timeInRange = LoopHistoryMath.timeInRange(cgm)
        summary.agp = LoopHistoryMath.agp(cgm)
        summary.agpDays = LoopHistoryMath.daysWithReadings(cgm)
        summary.cgmCoveredDays = LoopHistoryMath.cgmCoveredDays(cgm, in: interval,
                                                                periodDays: LoopHistoryMath.days(in: interval).count)

        let calendar = Calendar.current
        summary.totals = LoopHistoryMath.days(in: interval).map { day in
            let basal = history.basal.compactMap { $0.clamped(to: day) }.reduce(0) { $0 + $1.units }
            let boluses = history.boluses.filter { $0.date >= day.start && $0.date < day.end }
            return LoopHistoryMath.DayTotal(day: day.start, split: InsulinSplit(basal: basal, boluses: boluses),
                                            isComplete: calendar.date(byAdding: .day, value: 1, to: day.start) == day.end)
        }
        let glucoseDays = Set(history.glucose.map { calendar.startOfDay(for: $0.date) })
        // Carbs and bolus counts share insulin's days, so a period with years of CGM data but a few days of Loop
        // isn't spread thin. Without insulin, fall back to days with CGM data.
        let withData = summary.totals.filter { $0.total > 0 || glucoseDays.contains($0.day) }
        let insulinDays = LoopHistoryMath.averagingDays(summary.totals)
        let averaged = !insulinDays.isEmpty ? insulinDays
            : withData.contains(where: \.isComplete) ? withData.filter(\.isComplete) : withData
        let averagedDays = Set(averaged.map(\.day))
        let inAveragedDays: (Date) -> Bool = { averagedDays.contains(calendar.startOfDay(for: $0)) }
        summary.dataDays = averaged.count
        summary.carbsByDay = Dictionary(grouping: history.carbs) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.grams } }
        let carbs = history.carbs.filter { inAveragedDays($0.date) }
        summary.carbGrams = carbs.reduce(0) { $0 + $1.grams }
        summary.carbEntries = carbs.count
        let boluses = history.boluses.filter { inAveragedDays($0.date) }
        summary.manualBoluses = boluses.filter { !$0.automatic }.count
        summary.automaticBoluses = boluses.filter(\.automatic).count

        // Days the stored profile history doesn't reach (older ones, read from Health) use today's schedule.
        let spans = Dictionary(uniqueKeysWithValues: LoopHistoryMath.days(in: interval).map { ($0.start, $0) })
        let perDay = provider.scheduledBasalPerDay
        let scheduled = insulinDays.compactMap { day -> Double? in
            guard let span = spans[day.day] else { return nil }
            return LoopHistoryMath.scheduledUnits(history.scheduledBasal, over: span) ?? perDay.map { $0 * span.duration / 86400 }
        }
        if !scheduled.isEmpty, scheduled.count == insulinDays.count {
            summary.scheduledBasal = scheduled.reduce(0, +) / Double(scheduled.count)
        }
        if interval.end.timeIntervalSinceNow > -300 {
            summary.typicalByNow = await provider.typicalInsulinByNow()
        }

        summary.loopSpans = LoopHistoryMath.loopModeSpans(interval: interval, runs: runs, modeChanges: LoopModeHistory.shared.changes,
                                                          coverageStart: coverageStart)
        return summary
    }

    // MARK: Tiles

    func tiles(_ s: Summary) -> [StatTile] {
        let unit = s.unit
        var tiles: [StatTile] = []
        let averageLabel = NSLocalizedString("Average", comment: "Trends summary tile: mean glucose over the period")
        let gmiLabel = NSLocalizedString("GMI", comment: "Trends summary tile: abbreviation for Glucose Management Indicator, an estimate of HbA1c from CGM data")
        let loopActiveLabel = NSLocalizedString("Loop active", comment: "Trends summary tile: share of the period Loop spent in closed loop")
        if let stats = s.stats {
            tiles.append(StatTile(label: averageLabel, value: unit.format(stats.meanMgdl), unit: unit.unitName,
                                  detail: String(format: NSLocalizedString("SD %1$@ · CV %2$@%%", comment: "Trends Average tile detail: standard deviation and coefficient of variation of glucose. (1: standard deviation in the glucose unit, 2: coefficient of variation as a percentage number)"),
                                                 unit.format(stats.sdMgdl), LoopFormat.number(stats.cv * 100, decimals: 0))))
            let enough = s.cgmActive * s.interval.duration / 86400 >= 10
            tiles.append(StatTile(label: gmiLabel, value: LoopFormat.number(stats.gmiPercent, decimals: 1), unit: "%",
                                  detail: enough
                                    ? String(format: NSLocalizedString("%1$@ mmol/mol", comment: "Trends GMI tile detail: the GMI in IFCC units. (1: value)"),
                                             LoopFormat.number(stats.gmiMmolMol, decimals: 0))
                                    : NSLocalizedString("Needs 10 days of CGM", comment: "Trends GMI tile detail when fewer than 10 days of CGM data are available")))
        } else {
            tiles.append(StatTile(label: averageLabel, value: "–", unit: unit.unitName,
                                  detail: NSLocalizedString("No CGM data", comment: "Trends Average tile detail when the period has no glucose readings")))
            tiles.append(StatTile(label: gmiLabel, value: "–", unit: "%", detail: nil))
        }
        let basalPercent = LoopFormat.number(s.basalShare * 100, decimals: 0)
        let insulinDetail: String
        if let note = daysNote(s) {
            insulinDetail = String(format: NSLocalizedString("%1$@%% basal · %2$@", comment: "Trends Insulin per day tile detail when only some days are averaged. (1: basal share as a percentage number, 2: days averaged, e.g. 5 of 14 days)"),
                                   basalPercent, note)
        } else {
            insulinDetail = String(format: NSLocalizedString("%1$@%% basal", comment: "Trends Insulin per day tile detail: share of insulin delivered as basal. (1: percentage number)"),
                                   basalPercent)
        }
        // One day's figures are that day's own, so its tiles drop "per day" and show whole counts.
        let oneDay = s.day != nil
        let countDecimals = oneDay ? 0 : 1
        tiles.append(StatTile(label: oneDay
                                ? NSLocalizedString("Insulin", comment: "Trends summary tile for a one-day period: the day's total insulin")
                                : NSLocalizedString("Insulin per day", comment: "Trends tile and card title: average total insulin per day"),
                              value: LoopFormat.number(s.insulinPerDay, decimals: 1),
                              unit: NSLocalizedString("U", comment: "Abbreviation for insulin units"),
                              detail: insulinDetail, valueColor: P.insulinInk))
        tiles.append(StatTile(label: oneDay
                                ? NSLocalizedString("Carbs", comment: "Trends summary tile for a one-day period: the day's total carbohydrate")
                                : NSLocalizedString("Carbs per day", comment: "Trends summary tile: average grams of carbohydrate entered per day"),
                              value: LoopFormat.number(s.carbGrams / s.days, decimals: 0),
                              unit: NSLocalizedString("g", comment: "Abbreviation for grams"),
                              detail: oneDay
                                ? String(format: NSLocalizedString("%lld entries", comment: "Trends Carbs tile detail for a one-day period: how many carb entries were made that day. (1: number)"), s.carbEntries)
                                : String(format: NSLocalizedString("%1$@ entries", comment: "Trends Carbs per day tile detail: average number of carb entries per day, a fractional value such as 2.5, so not pluralised. (1: number with one decimal)"),
                                         LoopFormat.number(Double(s.carbEntries) / s.days, decimals: 1)),
                              valueColor: P.carbsInk))
        tiles.append(StatTile(label: oneDay
                                ? NSLocalizedString("Boluses", comment: "Trends summary tile for a one-day period: how many manual boluses were given that day")
                                : NSLocalizedString("Boluses per day", comment: "Trends summary tile: average number of manual boluses per day"),
                              value: LoopFormat.number(Double(s.manualBoluses) / s.days, decimals: countDecimals), unit: nil,
                              detail: String(format: NSLocalizedString("+ %1$@ automatic", comment: "Trends Boluses per day tile detail: average number of automatic boluses per day on top of the manual ones, a fractional value such as 4.2. (1: number with one decimal)"),
                                             LoopFormat.number(Double(s.automaticBoluses) / s.days, decimals: countDecimals))))
        let covered = s.loopSpans.reduce(0) { $0 + $1.duration }
        if covered > 0 {
            let closed = LoopHistoryMath.duration(of: .closed, in: s.loopSpans)
            tiles.append(StatTile(label: loopActiveLabel, value: LoopFormat.number(closed / covered * 100, decimals: 0), unit: "%",
                                  detail: String(format: NSLocalizedString("%1$@ of %2$@", comment: "Trends Loop active tile detail: time in closed loop out of the time Loop status is known. (1: duration in closed loop, e.g. 6d 4h, 2: duration covered, e.g. 7d)"),
                                                 LoopFormat.duration(closed), LoopFormat.duration(covered))))
        } else {
            tiles.append(StatTile(label: loopActiveLabel, value: "–", unit: "%",
                                  detail: NSLocalizedString("No loop runs kept", comment: "Trends Loop active tile detail when no Loop run history is available for the period")))
        }
        return tiles
    }

    /// "5 of 14 days" when only part of the period is averaged: days without data, or today while it runs.
    private func daysNote(_ s: Summary) -> String? {
        let insulinDays = LoopHistoryMath.averagingDays(s.totals).count
        guard insulinDays < s.totals.count else { return nil }
        let total = String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: "A number of days, e.g. a Trends period or how many days are averaged. (1: number of days)"), s.totals.count)
        return String(format: NSLocalizedString("%1$@ of %2$@", comment: "Trends: how many days of the period are averaged. (1: days averaged, a number; 2: days in the period, e.g. 14 days)"), LoopFormat.number(Double(insulinDays), decimals: 0), total)
    }

    // MARK: Export

    static func exportCSV(_ s: Summary) throws -> URL {
        // The CSV header and values are deliberately not localised: fixed English columns and '.' decimals for data interchange.
        var lines = ["date,mean_glucose_\(s.unit.isMmol ? "mmol_l" : "mg_dl"),readings,time_in_range_pct,basal_u,bolus_u,total_u,carbs_g,manual_bolus_u,auto_bolus_u"]
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: s.glucose) { calendar.startOfDay(for: $0.date) }
        for total in s.totals {
            let readings = byDay[total.day] ?? []
            let mean = readings.isEmpty ? "" : String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"),
                                                      s.unit.isMmol ? 1 : 0, s.unit.value(readings.reduce(0) { $0 + $1.mgdl } / Double(readings.count)))
            let tir = readings.isEmpty ? "" : String(format: "%.0f", (LoopHistoryMath.timeInRange(readings)[.inRange] ?? 0) * 100)
            let date = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().format(total.day)
            let carbs = String(format: "%.0f", s.carbsByDay[total.day] ?? 0)
            // Left blank when some of the day's bolus doesn't say whether it was manual or automatic.
            let bolusSplit = total.split.isClassified ? String(format: "%.2f,%.2f", total.split.manualBolus, total.split.automaticBolus) : ","
            lines.append("\(date),\(mean),\(readings.count),\(tir),\(String(format: "%.2f,%.2f,%.2f", total.basal, total.bolus, total.total)),\(carbs),\(bolusSplit)")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.fileName(s.interval) + ".csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportPDF(_ s: Summary) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.fileName(s.interval) + ".pdf")
        let report = TrendsReport(summary: s, tiles: tiles(s))
            .frame(width: 560)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: report)
        renderer.proposedSize = ProposedViewSize(width: 560, height: nil)
        var thrown: Error?
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 612, height: max(792, size.height + 52))
            guard let consumer = CGDataConsumer(url: url as CFURL), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
                thrown = CocoaError(.fileWriteUnknown)
                return
            }
            context.beginPDFPage(nil)
            context.translateBy(x: 26, y: box.height - size.height - 26)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        if let thrown { throw thrown }
        return url
    }

    private static func fileName(_ interval: DateInterval) -> String {
        String(format: NSLocalizedString("Loop trends %1$@", comment: "File name of an exported Trends report or CSV, without the extension. (1: date range of the period)"),
               fileStamp(interval))
    }

    private static func fileStamp(_ interval: DateInterval) -> String {
        LoopFormat.range(interval.start, interval.end.addingTimeInterval(-1)).replacingOccurrences(of: " – ", with: " to ")
    }
}

// MARK: - Screen

struct TrendsView: View {
    @StateObject private var model: TrendsModel
    @State private var path: [TrendsRoute] = []
    @State private var exportURL: URL?
    @State private var exportError: String?

    /// Closes Trends when it is presented on its own; nil where Trends has nowhere to return to.
    private let done: (() -> Void)?

    enum TrendsRoute: Hashable {
        case day(Date)
        case gaps
    }

    init(provider: LoopHistoryProvider, done: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: TrendsModel(provider: provider))
        self.done = done
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LoopDesign.Space.s6, pinnedViews: [.sectionHeaders]) {
                    Section {
                        content
                    } header: {
                        RangeSelectorView(period: $model.period, endDay: $model.endDay)
                            .padding(.vertical, LoopDesign.Space.s2)
                            .background(P.surface)
                    }
                }
                .padding(.horizontal, LoopDesign.Space.s4)
                .padding(.bottom, LoopDesign.Space.s6)
            }
            .background(P.surface)
            .navigationTitle(NSLocalizedString("Trends", comment: "Title of the Trends tab"))
            .refreshable { model.reload() }
            .toolbar {
                if let done {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(NSLocalizedString("Done", comment: "Button to close Trends"), action: done)
                    }
                }
            }
            .navigationDestination(for: TrendsRoute.self) { route in
                switch route {
                case .day(let day):
                    DayDetailView(provider: model.provider, day: day)
                case .gaps:
                    LoopGapsList(spans: model.summary?.loopSpans ?? [])
                }
            }
        }
        .onAppear { model.reload() }
        .onChange(of: model.period) { _, _ in model.reload() }
        .onChange(of: model.endDay) { _, _ in model.reload() }
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
        }
        .alert(NSLocalizedString("Couldn't export", comment: "Alert title when exporting the Trends PDF or CSV fails"),
               isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(NSLocalizedString("OK", comment: "Button to dismiss an alert"), role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let s = model.summary {
            summaryCard(s)
            // A single day leads with its timeline.
            if let day = s.day {
                dayCard(day, targets: s.dayTargets, unit: s.unit)
            }
            LoopCard {
                CardHeader(title: NSLocalizedString("Time in range", comment: "Trends card title: share of glucose readings in each range")) {
                    Text(String(format: NSLocalizedString("%1$@%% CGM active", comment: "Trends Time in range card: share of the period with CGM readings. (1: percentage number)"),
                                LoopFormat.number(s.cgmActive * 100, decimals: 0)))
                }
                if s.glucose.isEmpty {
                    ChartPlaceholder(message: NSLocalizedString("No CGM data in this period", comment: "Trends chart placeholder when the period has no glucose readings"))
                } else {
                    TimeInRangeView(fractions: s.timeInRange, unit: s.unit)
                }
                Footnote(String(format: NSLocalizedString("Aim: over 70%% in range; under 25%% above and 4%% below; under 5%% very high and 1%% very low; CGM active over 70%%.", comment: "Trends Time in range card footnote: the consensus targets for time in range, above and below range, very high, very low and CGM wear")))
            }
            if s.day == nil {
                patternCard(s)
            }
            LoopCard {
                CardHeader(title: NSLocalizedString("Basal and bolus", comment: "Trends card title: insulin split into basal and bolus")) {
                    Text(s.splitIsPartial
                         ? NSLocalizedString("today so far", comment: "Trends Basal and bolus card subtitle when the figures are today's total so far")
                         : s.totals.count == 1
                         ? NSLocalizedString("this day", comment: "Trends Basal and bolus card subtitle when the period is one complete day")
                         : NSLocalizedString("average per day", comment: "Trends Basal and bolus card subtitle when the figures are averaged per day over the period"))
                }
                if s.split.total > 0 {
                    InsulinSplitView(split: s.split, partial: s.splitIsPartial, scheduledBasal: s.scheduledBasal,
                                     usual: s.splitIsPartial ? usualByNow(s) : nil)
                } else {
                    ChartPlaceholder(message: NSLocalizedString("No insulin recorded in this period", comment: "Trends Insulin per day chart placeholder when no insulin was delivered in the period"), height: 80)
                }
            }
            // One day is one bar: the timeline and the Basal and bolus card already say it all.
            if s.day == nil {
                LoopCard {
                    CardHeader(title: NSLocalizedString("Insulin per day", comment: "Trends tile and card title: average total insulin per day")) {
                        Text(s.totals.count > 30
                             ? NSLocalizedString("per day, weekly average", comment: "Trends Insulin per day card subtitle when each bar is a week's average daily total")
                             : NSLocalizedString("basal and bolus", comment: "Trends Insulin per day card subtitle when each bar is one day's basal and bolus"))
                    }
                    InsulinDailyTotalsView(totals: s.totals.count > 30 ? LoopHistoryMath.weekly(s.totals) : s.totals,
                                           weekly: s.totals.count > 30, average: s.insulinPerDay) { day in
                        path.append(.day(day))
                    }
                    ChartLegend(items: insulinLegend(s))
                    if let today = todaySoFar(s) {
                        Footnote(today)
                    }
                }
            }
            LoopCard {
                CardHeader(title: NSLocalizedString("Loop status", comment: "Trends card title: how long Loop spent in closed loop, limited or open loop")) {
                    Button(NSLocalizedString("Gaps", comment: "Trends Loop status button and screen title: list of times Loop wasn't in closed loop")) { path.append(.gaps) }
                        .foregroundStyle(P.accentInk)
                        .disabled(s.loopSpans.isEmpty)
                }
                LoopModeBarView(spans: s.loopSpans)
                if let note = coverageNote(s) {
                    Footnote(note)
                }
            }
        } else if let error = model.loadError {
            LoopCard {
                ChartPlaceholder(message: String(format: NSLocalizedString("Couldn't load Trends: %1$@", comment: "Trends error message when the history can't be read. (1: error description)"), error))
                Button(NSLocalizedString("Retry", comment: "Button to try loading Trends again after an error")) { model.reload() }.foregroundStyle(P.accentInk)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    /// The same timeline as Today so far: glucose, every bolus and basal change, and carbs, through the day.
    private func dayCard(_ day: DayHistory, targets: [TargetBand], unit: GlucoseUnitStyle) -> some View {
        let isToday = Calendar.current.isDateInToday(day.window.start)
        return Button {
            path.append(.day(day.window.start))
        } label: {
            DayTimelineCard(title: isToday ? DayTimelineCard.todayTitle : LoopFormat.weekdayDay(day.window.start),
                            history: day, unit: unit, targetBands: targets, height: 260, showsTotals: false)
        }
        .buttonStyle(.plain)
        .accessibilityHint(NSLocalizedString("Opens the full day", comment: "VoiceOver hint for the Today so far card on the Now screen"))
    }

    private func patternCard(_ s: TrendsModel.Summary) -> some View {
        LoopCard {
            CardHeader(title: NSLocalizedString("Daily pattern", comment: "Trends card title: the ambulatory glucose profile, glucose by time of day across the period")) { Text(s.unit.unitName) }
            TrendsAGPChart(slots: s.agp, readings: s.glucose, days: s.agpDays, unit: s.unit, targetRange: s.targetRange)
            ChartLegend(items: [
                LegendItem(swatch: .solid(P.glucose), label: NSLocalizedString("Median", comment: "Trends Daily pattern legend: the median glucose line")),
                LegendItem(swatch: .solid(P.agpInner), label: NSLocalizedString("25–75%", comment: "Trends Daily pattern legend: band between the 25th and 75th percentiles of glucose")),
                LegendItem(swatch: .solid(P.agpOuter), label: NSLocalizedString("5–95%", comment: "Trends Daily pattern legend: band between the 5th and 95th percentiles of glucose")),
            ])
        }
    }

    private func summaryCard(_ s: TrendsModel.Summary) -> some View {
        LoopCard {
            CardHeader(title: NSLocalizedString("Summary", comment: "Trends card title: the summary statistics tiles")) {
                Menu(NSLocalizedString("Export", comment: "Trends menu title: export the period as a PDF report or CSV file")) {
                    Button(NSLocalizedString("PDF report", comment: "Trends export menu item: share a PDF report of the period")) { export { try model.exportPDF(s) } }
                    Button(NSLocalizedString("CSV, one row per day", comment: "Trends export menu item: share a CSV spreadsheet file with one row for each day")) { export { try TrendsModel.exportCSV(s) } }
                }
                .foregroundStyle(P.accentInk)
            }
            if let covered = s.cgmCoveredDays {
                Footnote(String(format: NSLocalizedString("CGM data covers %1$@.", comment: "Trends Summary note when glucose readings start partway through the period. (1: days covered, e.g. 5 of 14 days)"),
                                daysOf(covered, s.totals.count)))
            }
            StatGridView(tiles: model.tiles(s))
                .opacity(model.loading ? 0.5 : 1)
            if s.stats != nil {
                Footnote(String(format: NSLocalizedString("Aim: average under %1$@ %2$@, GMI under 7%%, CV 36%% or less.", comment: "Trends Summary footnote: the consensus targets for average glucose, GMI and glucose variability (CV). (1: glucose value, 2: glucose unit)"),
                                s.unit.isMmol ? LoopFormat.number(8.6, decimals: 1) : "154", s.unit.unitName))
            }
        }
    }

    /// "5 of 14 days".
    private func daysOf(_ count: Int, _ total: Int) -> String {
        let days = String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: "A number of days, e.g. a Trends period or how many days are averaged. (1: number of days)"), total)
        return String(format: NSLocalizedString("%1$@ of %2$@", comment: "Trends: how many days of the period are averaged. (1: days averaged, a number; 2: days in the period, e.g. 14 days)"), LoopFormat.number(Double(count), decimals: 0), days)
    }

    /// "Usually 28.4 U by 19:46": today's insulin against the last 14 days at the same time.
    private func usualByNow(_ s: TrendsModel.Summary) -> String? {
        guard let usual = s.typicalByNow else { return nil }
        return String(format: NSLocalizedString("Usually %1$@ by %2$@", comment: "Trends: the median insulin delivered by this time of day over the last 14 days. (1: units, e.g. 28.4 U, 2: time of day)"),
                      LoopFormat.totalUnits(usual.typical.median), LoopFormat.time(usual.at))
    }

    /// Today's bar is still growing, so say where it stands against a usual day.
    private func todaySoFar(_ s: TrendsModel.Summary) -> String? {
        guard let today = s.totals.last, !today.isComplete, today.total > 0, let usual = s.typicalByNow else { return nil }
        return String(format: NSLocalizedString("Today so far %1$@, usually %2$@ by %3$@.", comment: "Trends Insulin per day footnote: today's insulin so far against the median by this time of day over the last 14 days. (1: today's units, 2: usual units, 3: time of day)"),
                      LoopFormat.totalUnits(today.total), LoopFormat.totalUnits(usual.typical.median), LoopFormat.time(usual.at))
    }

    private func export(_ make: () throws -> URL) {
        do {
            exportURL = try make()
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// The figures are on the Basal and bolus card above, so the legend only names the marks.
    private func insulinLegend(_ s: TrendsModel.Summary) -> [LegendItem] {
        [
            LegendItem(swatch: .basal, label: NSLocalizedString("Basal", comment: "Chart legend: the basal part of each day's insulin")),
            LegendItem(swatch: .solid(P.bolus), label: NSLocalizedString("Bolus", comment: "Chart legend: solid bars are manual boluses")),
            LegendItem(swatch: .hatch(P.bolus), label: NSLocalizedString("Automatic", comment: "Chart legend: hatched bars are automatic boluses given by Loop")),
            LegendItem(swatch: .dash(P.ink),
                       label: String(format: NSLocalizedString("Average %1$@ U", comment: "Trends Insulin per day legend: the dashed line showing average total insulin per day. (1: units)"),
                                     LoopFormat.number(s.insulinPerDay, decimals: 1))),
        ]
    }

    private func coverageNote(_ s: TrendsModel.Summary) -> String? {
        guard let start = s.loopSpans.first?.start else {
            return NSLocalizedString("Loop status is recorded from when this version of Loop first ran.", comment: "Trends Loop status footnote when there is no Loop status history yet")
        }
        guard start > s.interval.start else { return nil }
        return String(format: NSLocalizedString("Covers %1$@: Loop keeps 7 days of runs, and closed or open loop is recorded from when this version of Loop first ran.", comment: "Trends Loop status footnote when the status covers only part of the period. (1: date range covered)"),
                      LoopFormat.range(start, s.interval.end))
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A card's quiet closing line: a target, a caveat or a comparison.
private struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(LoopDesign.Typeface.footnote)
            .foregroundStyle(P.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - PDF report

/// The Trends cards laid out for paper.
private struct TrendsReport: View {
    let summary: TrendsModel.Summary
    let tiles: [StatTile]

    var body: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Loop trends", comment: "Title of the exported Trends PDF report")).font(.title2.bold())
                Text(LoopFormat.range(summary.interval.start, summary.interval.end.addingTimeInterval(-1)))
                    .font(.subheadline)
                    .foregroundStyle(P.inkMuted)
            }
            StatGridView(tiles: tiles)
            HStack(alignment: .top, spacing: LoopDesign.Space.s4) {
                VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                    Text(NSLocalizedString("Time in range", comment: "Trends card title: share of glucose readings in each range")).font(.headline)
                    TimeInRangeView(fractions: summary.timeInRange, unit: summary.unit)
                }
                .frame(maxWidth: .infinity)
            }
            if let day = summary.day {
                VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                    Text(LoopFormat.weekdayDay(day.window.start)).font(.headline)
                    InsulinTimelineView(history: day, unit: summary.unit, targetBands: summary.dayTargets, height: 220)
                    ChartLegend(items: DayTotalsTiles.legend)
                }
            } else {
                VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                    Text(NSLocalizedString("Daily pattern", comment: "Trends card title: the ambulatory glucose profile, glucose by time of day across the period")).font(.headline)
                    TrendsAGPChart(slots: summary.agp, readings: summary.glucose, days: summary.agpDays, unit: summary.unit,
                                 targetRange: summary.targetRange, height: 160)
                }
                VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                    Text(NSLocalizedString("Insulin per day", comment: "Trends tile and card title: average total insulin per day")).font(.headline)
                    InsulinDailyTotalsView(totals: summary.totals.count > 30 ? LoopHistoryMath.weekly(summary.totals) : summary.totals,
                                           weekly: summary.totals.count > 30, average: summary.insulinPerDay, height: 140)
                }
            }
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                Text(NSLocalizedString("Loop status", comment: "Trends card title: how long Loop spent in closed loop, limited or open loop")).font(.headline)
                LoopModeBarView(spans: summary.loopSpans)
            }
        }
        .padding(LoopDesign.Space.s2)
        .background(Color.white)
    }
}
