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
        var glucose: [GlucosePoint] = []
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
        var loopCoverageStart: Date?
        var targetRange: ClosedRange<Double>?

        /// The days per-day figures divide by: insulin's averaging days, or complete days with CGM data when there is
        /// no insulin (today only when no complete day has any), never the period length.
        var dataDays = 0
        var days: Double { Double(max(1, dataDays)) }
        var basalUnits: Double { LoopHistoryMath.averagingDays(totals).reduce(0) { $0 + $1.basal } }
        var bolusUnits: Double { LoopHistoryMath.averagingDays(totals).reduce(0) { $0 + $1.bolus } }
        var insulinPerDay: Double { LoopHistoryMath.averageDailyInsulin(totals) }
        var basalShare: Double { basalUnits + bolusUnits > 0 ? basalUnits / (basalUnits + bolusUnits) : 0 }
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
        loading = true
        summary = nil
        loadError = nil
        loadTask = Task {
            do {
                let result = try await Self.load(provider: provider, interval: interval)
                guard !Task.isCancelled else { return }
                self.summary = result
            } catch {
                guard !Task.isCancelled else { return }
                self.loadError = error.localizedDescription
            }
            self.loading = false
        }
    }

    private static func load(provider: LoopHistoryProvider, interval: DateInterval) async throws -> Summary {
        var summary = Summary(interval: interval, unit: provider.unitStyle)
        summary.targetRange = provider.glucoseTargetRange

        async let historyFetch = provider.dayHistory(interval, includeOnBoard: false)
        async let runsFetch = provider.loopRuns()
        let history = try await historyFetch
        let (runs, coverageStart) = try await runsFetch

        summary.glucose = history.glucose
        summary.stats = LoopHistoryMath.glucoseStats(history.glucose)
        summary.cgmActive = LoopHistoryMath.cgmActiveFraction(history.glucose, over: interval)
        summary.timeInRange = LoopHistoryMath.timeInRange(history.glucose)
        summary.agp = LoopHistoryMath.agp(history.glucose)
        summary.agpDays = LoopHistoryMath.daysWithReadings(history.glucose)

        let calendar = Calendar.current
        summary.totals = LoopHistoryMath.days(in: interval).map { day in
            let basal = history.basal.compactMap { $0.clamped(to: day) }.reduce(0) { $0 + $1.units }
            let bolus = history.boluses.filter { $0.date >= day.start && $0.date < day.end }.reduce(0) { $0 + $1.units }
            return LoopHistoryMath.DayTotal(day: day.start, basal: basal, bolus: bolus,
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

        summary.loopCoverageStart = coverageStart
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
        tiles.append(StatTile(label: NSLocalizedString("Insulin per day", comment: "Trends tile and card title: average total insulin per day"),
                              value: LoopFormat.number(s.insulinPerDay, decimals: 1),
                              unit: NSLocalizedString("U", comment: "Abbreviation for insulin units"),
                              detail: insulinDetail))
        tiles.append(StatTile(label: NSLocalizedString("Carbs per day", comment: "Trends summary tile: average grams of carbohydrate entered per day"),
                              value: LoopFormat.number(s.carbGrams / s.days, decimals: 0),
                              unit: NSLocalizedString("g", comment: "Abbreviation for grams"),
                              detail: String(format: NSLocalizedString("%1$@ entries", comment: "Trends Carbs per day tile detail: average number of carb entries per day, a fractional value such as 2.5, so not pluralised. (1: number with one decimal)"),
                                             LoopFormat.number(Double(s.carbEntries) / s.days, decimals: 1))))
        tiles.append(StatTile(label: NSLocalizedString("Boluses per day", comment: "Trends summary tile: average number of manual boluses per day"),
                              value: LoopFormat.number(Double(s.manualBoluses) / s.days, decimals: 1), unit: nil,
                              detail: String(format: NSLocalizedString("+ %1$@ automatic", comment: "Trends Boluses per day tile detail: average number of automatic boluses per day on top of the manual ones, a fractional value such as 4.2. (1: number with one decimal)"),
                                             LoopFormat.number(Double(s.automaticBoluses) / s.days, decimals: 1))))
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

    func exportCSV(_ s: Summary) throws -> URL {
        // The CSV header and values are deliberately not localised: fixed English columns and '.' decimals for data interchange.
        var lines = ["date,mean_glucose_\(s.unit.isMmol ? "mmol_l" : "mg_dl"),readings,time_in_range_pct,basal_u,bolus_u,total_u,carbs_g"]
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: s.glucose) { calendar.startOfDay(for: $0.date) }
        for total in s.totals {
            let readings = byDay[total.day] ?? []
            let mean = readings.isEmpty ? "" : s.unit.format(readings.reduce(0) { $0 + $1.mgdl } / Double(readings.count))
            let tir = readings.isEmpty ? "" : String(format: "%.0f", (LoopHistoryMath.timeInRange(readings)[.inRange] ?? 0) * 100)
            let date = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().format(total.day)
            let carbs = String(format: "%.0f", s.carbsByDay[total.day] ?? 0)
            lines.append("\(date),\(mean),\(readings.count),\(tir),\(String(format: "%.2f,%.2f,%.2f", total.basal, total.bolus, total.total)),\(carbs)")
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

    enum TrendsRoute: Hashable {
        case day(Date)
        case gaps
    }

    init(provider: LoopHistoryProvider) {
        _model = StateObject(wrappedValue: TrendsModel(provider: provider))
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
                Text(String(format: NSLocalizedString("Aim: over 70%% in range, under 4%% low.", comment: "Trends Time in range card footnote: the consensus targets for time in range and time low")))
                    .font(LoopDesign.Typeface.footnote)
                    .foregroundStyle(P.inkMuted)
            }
            LoopCard {
                CardHeader(title: NSLocalizedString("Daily pattern", comment: "Trends card title: the ambulatory glucose profile, glucose by time of day across the period")) { Text(s.unit.unitName) }
                AGPChartView(slots: s.agp, readings: s.glucose, days: s.agpDays, unit: s.unit, targetRange: s.targetRange)
                ChartLegend(items: [
                    LegendItem(swatch: .solid(P.glucose), label: NSLocalizedString("Median", comment: "Trends Daily pattern legend: the median glucose line")),
                    LegendItem(swatch: .solid(P.agpInner), label: NSLocalizedString("25–75%", comment: "Trends Daily pattern legend: band between the 25th and 75th percentiles of glucose")),
                    LegendItem(swatch: .solid(P.agpOuter), label: NSLocalizedString("5–95%", comment: "Trends Daily pattern legend: band between the 5th and 95th percentiles of glucose")),
                ])
            }
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
            }
            LoopCard {
                CardHeader(title: NSLocalizedString("Loop status", comment: "Trends card title: how long Loop spent in closed loop, limited or open loop")) {
                    Button(NSLocalizedString("Gaps", comment: "Trends Loop status button and screen title: list of times Loop wasn't in closed loop")) { path.append(.gaps) }
                        .foregroundStyle(P.accentInk)
                        .disabled(s.loopSpans.isEmpty)
                }
                LoopModeBarView(spans: s.loopSpans)
                if let note = coverageNote(s) {
                    Text(note)
                        .font(LoopDesign.Typeface.footnote)
                        .foregroundStyle(P.inkMuted)
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

    private func summaryCard(_ s: TrendsModel.Summary) -> some View {
        LoopCard {
            CardHeader(title: NSLocalizedString("Summary", comment: "Trends card title: the summary statistics tiles")) {
                Menu(NSLocalizedString("Export", comment: "Trends menu title: export the period as a PDF report or CSV file")) {
                    Button(NSLocalizedString("PDF report", comment: "Trends export menu item: share a PDF report of the period")) { export { try model.exportPDF(s) } }
                    Button(NSLocalizedString("CSV, one row per day", comment: "Trends export menu item: share a CSV spreadsheet file with one row for each day")) { export { try model.exportCSV(s) } }
                }
                .foregroundStyle(P.accentInk)
            }
            StatGridView(tiles: model.tiles(s))
                .opacity(model.loading ? 0.5 : 1)
        }
    }

    private func export(_ make: () throws -> URL) {
        do {
            exportURL = try make()
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func insulinLegend(_ s: TrendsModel.Summary) -> [LegendItem] {
        let total = s.basalUnits + s.bolusUnits
        let days = Double(max(1, LoopHistoryMath.averagingDays(s.totals).count))
        let bolusShare = total > 0 ? Int((s.bolusUnits / total * 100).rounded()) : 0
        let basalShare = total > 0 ? 100 - bolusShare : 0
        return [
            LegendItem(swatch: .solid(P.insulin),
                       label: String(format: NSLocalizedString("Bolus %1$@ U (%2$@%%)", comment: "Trends Insulin per day legend: average bolus insulin per day and its share of the total. (1: units, 2: percentage number)"),
                                     LoopFormat.number(s.bolusUnits / days, decimals: 1), LoopFormat.number(Double(bolusShare), decimals: 0))),
            LegendItem(swatch: .basal,
                       label: String(format: NSLocalizedString("Basal %1$@ U (%2$@%%)", comment: "Trends Insulin per day legend: average basal insulin per day and its share of the total. (1: units, 2: percentage number)"),
                                     LoopFormat.number(s.basalUnits / days, decimals: 1), LoopFormat.number(Double(basalShare), decimals: 0))),
            LegendItem(swatch: .dash(P.ink),
                       label: String(format: NSLocalizedString("Average %1$@ U", comment: "Trends Insulin per day legend: the dashed line showing average total insulin per day. (1: units)"),
                                     LoopFormat.number(s.insulinPerDay, decimals: 1))),
        ]
    }

    private func coverageNote(_ s: TrendsModel.Summary) -> String? {
        guard let start = s.loopSpans.first?.start else {
            return NSLocalizedString("Loop status is recorded from when the new interface was first opened.", comment: "Trends Loop status footnote when there is no Loop status history yet")
        }
        guard start > s.interval.start else { return nil }
        return String(format: NSLocalizedString("Covers %1$@: Loop keeps 7 days of runs, and closed or open loop is recorded from when the new interface was first opened.", comment: "Trends Loop status footnote when the status covers only part of the period. (1: date range covered)"),
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
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                Text(NSLocalizedString("Daily pattern", comment: "Trends card title: the ambulatory glucose profile, glucose by time of day across the period")).font(.headline)
                AGPChartView(slots: summary.agp, readings: summary.glucose, days: summary.agpDays, unit: summary.unit,
                             targetRange: summary.targetRange, height: 160)
            }
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                Text(NSLocalizedString("Insulin per day", comment: "Trends tile and card title: average total insulin per day")).font(.headline)
                InsulinDailyTotalsView(totals: summary.totals.count > 30 ? LoopHistoryMath.weekly(summary.totals) : summary.totals,
                                       weekly: summary.totals.count > 30, average: summary.insulinPerDay, height: 140)
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
