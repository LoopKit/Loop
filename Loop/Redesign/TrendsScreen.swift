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
        /// CGM readings only: typed-in fingersticks are left out of every figure.
        var glucose: [GlucosePoint] = []
        /// Days from the first reading, when that is short of the period; nil when the readings span it.
        var cgmCoveredDays: Int?
        var stats: LoopHistoryMath.GlucoseStats?
        var cgmActive: Double = 0
        /// Hours a day with CGM readings, which the time in range shares are of.
        var cgmHoursPerDay: Double = 0
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
        /// Boluses whose record doesn't say whether they were automatic or given by the person, such as some in Apple Health.
        var unknownBoluses = 0
        var loopSpans: [LoopModeSpan] = []
        var targetRange: ClosedRange<Double>?
        /// The whole calendar day, for a one-day period: drawn as one timeline.
        var day: DayHistory?
        var dayTargets: [TargetBand] = []
        /// What the basal schedule delivers per day, over the averaged days Loop has its schedule for.
        var scheduledBasal: Double?
        /// The averaged days `scheduledBasal` covers: Apple Health doesn't record the schedule for older days.
        var scheduledDays = 0
        /// Some of the insulin comes from Apple Health, before Loop's own dose records begin.
        var readsHealthInsulin = false
        /// The median insulin by this time of day over the last 14 days, when the period ends now.
        var typicalByNow: (typical: TypicalInsulinDelivery, at: Date)?

        /// The days per-day figures divide by: insulin's averaging days, or complete days with CGM data when there is
        /// no insulin (today only when no complete day has any), never the period length.
        var dataDays = 0
        var days: Double { Double(max(1, dataDays)) }
        var insulinPerDay: Double { LoopHistoryMath.averageDailyInsulin(totals) }
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
        async let historyFetch = provider.dayHistory(fetchWindow)
        async let runsFetch = provider.loopRuns()
        async let modeFetch = provider.loopModeChanges(in: interval)
        async let manualTempFetch = provider.manualTempBasals(in: interval)
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
        summary.cgmHoursPerDay = LoopHistoryMath.cgmHoursPerDay(cgmActive: summary.cgmActive, over: interval,
                                                                periodDays: LoopHistoryMath.days(in: interval).count)
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
        summary.manualBoluses = boluses.filter { $0.automaticKnown && !$0.automatic }.count
        summary.automaticBoluses = boluses.filter { $0.automaticKnown && $0.automatic }.count
        summary.unknownBoluses = boluses.filter { !$0.automaticKnown }.count

        // Only days Loop has its schedule for: older days come from Health, which doesn't record it.
        let spans = Dictionary(uniqueKeysWithValues: LoopHistoryMath.days(in: interval).map { ($0.start, $0) })
        let scheduled = insulinDays.compactMap { day in spans[day.day].flatMap { LoopHistoryMath.scheduledUnits(history.scheduledBasal, over: $0) } }
        if !scheduled.isEmpty {
            summary.scheduledBasal = scheduled.reduce(0, +) / Double(scheduled.count)
            summary.scheduledDays = scheduled.count
        }
        summary.readsHealthInsulin = interval.start < history.localInsulinStart
        if interval.end.timeIntervalSinceNow > -300 {
            summary.typicalByNow = await provider.typicalInsulinByNow()
        }

        summary.loopSpans = LoopHistoryMath.loopModeSpans(interval: interval, runs: runs, modeChanges: try await modeFetch,
                                                          coverageStart: coverageStart, manualTempBasals: try await manualTempFetch)
        return summary
    }

    // MARK: Tiles

    func tiles(_ s: Summary) -> [StatTile] {
        let unit = s.unit
        var tiles: [StatTile] = []
        let averageLabel = NSLocalizedString("Average", comment: "Trends summary tile: mean glucose over the period")
        let gmiLabel = NSLocalizedString("GMI", comment: "Trends summary tile: abbreviation for Glucose Management Indicator, an estimate of HbA1c from CGM data")
        let gmiCaveat = LoopHistoryMath.gmiIsRepresentative(periodDays: s.totals.count, cgmActive: s.cgmActive) ? nil
            : String(format: NSLocalizedString("Best over 14 days with %1$@ CGM data", comment: "Trends GMI tile caption when the period is shorter than 14 days or CGM readings cover less than 70% of it: the consensus for when GMI is representative. (1: share of CGM data, e.g. 70%)"),
                     ConsensusTarget.percent(70))
        if let stats = s.stats {
            tiles.append(StatTile(label: averageLabel, value: unit.format(stats.meanMgdl), unit: unit.unitName,
                                  detail: String(format: NSLocalizedString("SD %1$@ · CV %2$@%%", comment: "Trends Average tile detail: standard deviation and coefficient of variation of glucose. (1: standard deviation in the glucose unit, 2: coefficient of variation as a percentage number)"),
                                                 unit.format(stats.sdMgdl), LoopFormat.number(stats.cv * 100, decimals: 0)),
                                  aim: averageAim(unit)))
            // Always shown, as Statistics did. The consensus says how representative it is: 14 days, 70% CGM data.
            tiles.append(StatTile(label: gmiLabel, value: LoopFormat.number(stats.gmiPercent, decimals: 1), unit: "%",
                                  detail: String(format: NSLocalizedString("%1$@ mmol/mol", comment: "Trends GMI tile detail: the GMI in IFCC units. (1: value)"),
                                                 LoopFormat.number(stats.gmiMmolMol, decimals: 0)),
                                  aim: ConsensusTarget.aim(ConsensusTarget.under(7)),
                                  caveat: gmiCaveat))
        } else {
            tiles.append(StatTile(label: averageLabel, value: "–", unit: unit.unitName,
                                  detail: NSLocalizedString("No CGM data", comment: "Trends Average tile detail when the period has no glucose readings")))
            tiles.append(StatTile(label: gmiLabel, value: "–", unit: "%",
                                  detail: String(format: NSLocalizedString("%1$@ mmol/mol", comment: "Trends GMI tile detail: the GMI in IFCC units. (1: value)"), "–"),
                                  caveat: gmiCaveat))
        }
        // One day's figures are that day's own, so its tiles drop "per day" and show whole counts.
        let oneDay = s.day != nil
        let countDecimals = oneDay ? 0 : 1
        tiles.append(StatTile(label: oneDay
                                ? NSLocalizedString("Carbs", comment: "Trends summary tile for a one-day period: the day's total carbohydrate")
                                : NSLocalizedString("Carbs per day", comment: "Trends summary tile: average grams of carbohydrate entered per day"),
                              value: LoopFormat.number(s.carbGrams / s.days, decimals: 0),
                              unit: NSLocalizedString("g", comment: "Abbreviation for grams"),
                              detail: oneDay
                                ? String(format: NSLocalizedString("%lld entries", comment: "Trends Carbs tile detail for a one-day period: how many carb entries were made that day. (1: number)"), s.carbEntries)
                                : String(format: NSLocalizedString("%1$@ entries", comment: "Trends Carbs per day tile detail: average number of carb entries per day, a fractional value such as 2.5, so not pluralised. (1: number with one decimal)"),
                                         LoopFormat.number(Double(s.carbEntries) / s.days, decimals: 1))))
        tiles.append(StatTile(label: oneDay
                                ? NSLocalizedString("Boluses", comment: "Trends summary tile for a one-day period: how many boluses were given that day, other than Loop's automatic ones")
                                : NSLocalizedString("Boluses per day", comment: "Trends summary tile: average number of boluses per day, other than Loop's automatic ones"),
                              // Every bolus not known to be automatic, so one of unknown kind still counts.
                              value: LoopFormat.number(Double(s.manualBoluses + s.unknownBoluses) / s.days, decimals: countDecimals), unit: nil,
                              detail: s.unknownBoluses > 0
                                ? String(format: NSLocalizedString("%1$@ of unknown kind\n+ %2$@ automatic", comment: "Trends Boluses per day tile detail when some boluses don't say whether they were manual or automatic, such as some in Apple Health, on two lines: how many of the figure above are of unknown kind, then the automatic boluses on top. (1: boluses of unknown kind per day; 2: automatic boluses per day; both fractional, such as 4.2)"),
                                         LoopFormat.number(Double(s.unknownBoluses) / s.days, decimals: countDecimals),
                                         LoopFormat.number(Double(s.automaticBoluses) / s.days, decimals: countDecimals))
                                : String(format: NSLocalizedString("+ %1$@ automatic", comment: "Trends Boluses per day tile detail: average number of automatic boluses per day on top of the manual ones, a fractional value such as 4.2. (1: number with one decimal)"),
                                         LoopFormat.number(Double(s.automaticBoluses) / s.days, decimals: countDecimals))))
        return tiles
    }

    /// "aim < 8.6, CV ≤ 36%": the consensus targets for mean glucose (154 mg/dL) and its variability.
    private func averageAim(_ unit: GlucoseUnitStyle) -> String {
        String(format: NSLocalizedString("aim %1$@, CV %2$@", comment: "Trends Average tile: the consensus targets for average glucose and its coefficient of variation, in lower case. (1: glucose target, e.g. < 8.6; 2: CV target, e.g. ≤ 36%)"),
               "< " + (unit.isMmol ? LoopFormat.number(8.6, decimals: 1) : "154"), ConsensusTarget.atMost(36))
    }

    /// "5 of 14 days" when only part of the period is averaged: days without data, or today while it runs.
    func daysNote(_ s: Summary) -> String? {
        let insulinDays = LoopHistoryMath.averagingDays(s.totals).count
        guard insulinDays < s.totals.count else { return nil }
        let total = String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: "A number of days, e.g. a Trends period or how many days are averaged. (1: number of days)"), s.totals.count)
        return String(format: NSLocalizedString("%1$@ of %2$@", comment: "Trends: how many days of the period are averaged. (1: days averaged, a number; 2: days in the period, e.g. 14 days)"), LoopFormat.number(Double(insulinDays), decimals: 0), total)
    }
}

// MARK: - Screen

struct TrendsView: View {
    @StateObject private var model: TrendsModel

    /// Closes Trends when it is presented on its own; nil where Trends has nowhere to return to.
    private let done: (() -> Void)?

    init(provider: LoopHistoryProvider, done: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: TrendsModel(provider: provider))
        self.done = done
    }

    var body: some View {
        NavigationStack {
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
        }
        .onAppear { model.reload() }
        .onChange(of: model.period) { _, _ in model.reload() }
        .onChange(of: model.endDay) { _, _ in model.reload() }
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
                                LoopFormat.number(s.cgmActive * 100, decimals: 0))
                         + " · " + ConsensusTarget.aim(ConsensusTarget.over(70)))
                }
                if s.glucose.isEmpty {
                    ChartPlaceholder(message: NSLocalizedString("No CGM data in this period", comment: "Trends chart placeholder when the period has no glucose readings"))
                } else {
                    TimeInRangeView(fractions: s.timeInRange, hoursPerDay: s.cgmHoursPerDay, unit: s.unit)
                }
            }
            if s.day == nil {
                patternCard(s)
            }
            insulinCard(s)
            LoopCard {
                CardHeader(title: NSLocalizedString("Loop status", comment: "Trends card title: how long Loop spent in closed loop, limited or open loop"))
                LoopModeBarView(spans: s.loopSpans)
                if let note = coverageNote(s) {
                    Footnote(note)
                }
            }
        } else if let error = model.loadError {
            LoopCard {
                ChartPlaceholder(message: String(format: NSLocalizedString("Couldn't load Trends: %1$@", comment: "Trends error message when the history can't be read. (1: error description)"), error))
                Button(NSLocalizedString("Retry", comment: "Button to try loading Trends again after an error")) { model.reload() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    /// Insulin per day with its basal and bolus split, or one day's insulin under its timeline.
    private func insulinCard(_ s: TrendsModel.Summary) -> some View {
        let weekly = s.totals.count > 30
        return LoopCard {
            if s.day != nil {
                // One day is one bar, so the timeline above stands in for the chart.
                CardHeader(title: NSLocalizedString("Insulin", comment: "Trends card title for a one-day period: the day's insulin, split into basal and bolus")) {
                    Text(s.splitIsPartial
                         ? NSLocalizedString("today so far", comment: "Trends Basal and bolus card subtitle when the figures are today's total so far")
                         : NSLocalizedString("this day", comment: "Trends Basal and bolus card subtitle when the period is one complete day"))
                }
            } else {
                CardHeader(title: NSLocalizedString("Insulin per day", comment: "Trends tile and card title: average total insulin per day")) {
                    if weekly, let note = model.daysNote(s) {
                        Text(String(format: NSLocalizedString("per day, weekly average · %1$@", comment: "Trends Insulin per day card subtitle when each bar is a week's average daily total and only some days of the period are averaged. (1: days averaged, e.g. 4 of 90 days)"), note))
                    } else if weekly {
                        Text(NSLocalizedString("per day, weekly average", comment: "Trends Insulin per day card subtitle when each bar is a week's average daily total"))
                    } else if let note = model.daysNote(s) {
                        Text(String(format: NSLocalizedString("average of %1$@", comment: "Trends Insulin per day card subtitle when only some days of the period are averaged, such as a day still in progress. (1: days averaged, e.g. 13 of 14 days)"), note))
                    } else {
                        Text(NSLocalizedString("average per day", comment: "Trends Basal and bolus card subtitle when the figures are averaged per day over the period"))
                    }
                }
            }
            if s.split.total > 0 {
                if s.day == nil {
                    InsulinDailyTotalsView(totals: weekly ? LoopHistoryMath.weekly(s.totals) : s.totals, weekly: weekly, average: s.insulinPerDay)
                }
                // Under the chart, the rows name its marks, so there is no separate legend.
                let averaged = LoopHistoryMath.averagingDays(s.totals).count
                InsulinSplitView(split: s.split, partial: s.splitIsPartial, scheduledBasal: s.scheduledBasal,
                                 scheduledNote: s.scheduledDays < averaged ? daysOf(s.scheduledDays, averaged) : nil,
                                 usual: s.day != nil && s.splitIsPartial ? usualByNow(s) : nil, showsBar: s.day != nil,
                                 averageLine: s.day == nil)
                if s.day == nil, let today = todaySoFar(s) {
                    Footnote(today)
                }
                // Days read from Apple Health have no schedule, and some boluses there don't say which kind they were.
                if s.readsHealthInsulin, s.scheduledBasal == nil || !s.split.isClassified {
                    Footnote(NSLocalizedString("Older days come from Apple Health, which doesn't record the basal schedule, and some boluses there don't say whether they were manual or automatic.", comment: "Trends Insulin per day footnote when the period reaches back past Loop's own records into Apple Health, so scheduled basal can't be shown, or some boluses there have no record of whether they were manual or automatic"))
                }
            } else {
                ChartPlaceholder(message: NSLocalizedString("No insulin recorded in this period", comment: "Trends Insulin per day chart placeholder when no insulin was delivered in the period"), height: 80)
            }
        }
    }

    /// The same timeline as Today so far: glucose, every bolus and basal change, and carbs, through the day.
    private func dayCard(_ day: DayHistory, targets: [TargetBand], unit: GlucoseUnitStyle) -> some View {
        let isToday = Calendar.current.isDateInToday(day.window.start)
        return DayTimelineCard(title: isToday ? DayTimelineCard.todayTitle : LoopFormat.weekdayDay(day.window.start),
                               history: day, unit: unit, targetBands: targets, height: 260)
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
            CardHeader(title: NSLocalizedString("Summary", comment: "Trends card title: the summary statistics tiles"))
            if let covered = s.cgmCoveredDays {
                Footnote(String(format: NSLocalizedString("CGM data covers %1$@.", comment: "Trends Summary note when glucose readings start partway through the period. (1: days covered, e.g. 5 of 14 days)"),
                                daysOf(covered, s.totals.count)))
            }
            StatGridView(tiles: model.tiles(s))
                .opacity(model.loading ? 0.5 : 1)
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

    /// When Loop's records of its runs and settings start inside the period, say so, and how long it keeps them.
    private func coverageNote(_ s: TrendsModel.Summary) -> String? {
        guard let start = s.loopSpans.first?.start, start > s.interval.start else { return nil }
        let kept = String.localizedStringWithFormat(NSLocalizedString("%lld days", comment: "A number of days, e.g. a Trends period or how many days are averaged. (1: number of days)"),
                                                    model.provider.localHistoryDays)
        return String(format: NSLocalizedString("Covers %1$@, from the start of Loop's records, which it keeps for %2$@.", comment: "Trends Loop status footnote when Loop's records of its runs and settings start partway through the period. (1: date range covered; 2: how long Loop keeps them, e.g. 90 days)"),
                      LoopFormat.range(start, s.interval.end), kept)
    }
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
