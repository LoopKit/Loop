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
        if let stats = s.stats {
            tiles.append(StatTile(label: "Average", value: unit.format(stats.meanMgdl), unit: unit.unitName,
                                  detail: "SD \(unit.format(stats.sdMgdl)) · CV \(Int((stats.cv * 100).rounded()))%"))
            let enough = s.cgmActive * s.interval.duration / 86400 >= 10
            tiles.append(StatTile(label: "GMI", value: String(format: "%.1f", stats.gmiPercent), unit: "%",
                                  detail: enough ? "\(Int(stats.gmiMmolMol.rounded())) mmol/mol" : "Needs 10 days of CGM"))
        } else {
            tiles.append(StatTile(label: "Average", value: "–", unit: unit.unitName, detail: "No CGM data"))
            tiles.append(StatTile(label: "GMI", value: "–", unit: "%", detail: nil))
        }
        tiles.append(StatTile(label: "Insulin per day", value: String(format: "%.1f", s.insulinPerDay), unit: "U",
                              detail: "\(Int((s.basalShare * 100).rounded()))% basal" + daysNote(s)))
        tiles.append(StatTile(label: "Carbs per day", value: String(format: "%.0f", s.carbGrams / s.days), unit: "g",
                              detail: String(format: "%.1f entries", Double(s.carbEntries) / s.days)))
        tiles.append(StatTile(label: "Boluses per day", value: String(format: "%.1f", Double(s.manualBoluses) / s.days), unit: nil,
                              detail: String(format: "+ %.1f automatic", Double(s.automaticBoluses) / s.days)))
        let covered = s.loopSpans.reduce(0) { $0 + $1.duration }
        if covered > 0 {
            let closed = LoopHistoryMath.duration(of: .closed, in: s.loopSpans)
            tiles.append(StatTile(label: "Loop active", value: "\(Int((closed / covered * 100).rounded()))", unit: "%",
                                  detail: "\(LoopFormat.duration(closed)) of \(LoopFormat.duration(covered))"))
        } else {
            tiles.append(StatTile(label: "Loop active", value: "–", unit: "%", detail: "No loop runs kept"))
        }
        return tiles
    }

    /// " · 5 of 14 days" when only part of the period is averaged: days without data, or today while it runs.
    private func daysNote(_ s: Summary) -> String {
        let insulinDays = LoopHistoryMath.averagingDays(s.totals).count
        return insulinDays < s.totals.count ? " · \(insulinDays) of \(s.totals.count) day\(s.totals.count == 1 ? "" : "s")" : ""
    }

    // MARK: Export

    func exportCSV(_ s: Summary) throws -> URL {
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Loop trends \(Self.fileStamp(s.interval)).csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportPDF(_ s: Summary) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Loop trends \(Self.fileStamp(s.interval)).pdf")
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
            .navigationTitle("Trends")
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
        .alert("Couldn't export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let s = model.summary {
            summaryCard(s)
            LoopCard {
                CardHeader(title: "Time in range") {
                    Text("\(Int((s.cgmActive * 100).rounded()))% CGM active")
                }
                if s.glucose.isEmpty {
                    ChartPlaceholder(message: "No CGM data in this period")
                } else {
                    TimeInRangeView(fractions: s.timeInRange, unit: s.unit)
                }
                Text("Aim: over 70% in range, under 4% low.")
                    .font(LoopDesign.Typeface.footnote)
                    .foregroundStyle(P.inkMuted)
            }
            LoopCard {
                CardHeader(title: "Daily pattern") { Text(s.unit.unitName) }
                TrendsAGPChart(slots: s.agp, readings: s.glucose, days: s.agpDays, unit: s.unit, targetRange: s.targetRange)
                ChartLegend(items: [
                    LegendItem(swatch: .solid(P.glucose), label: "Median"),
                    LegendItem(swatch: .solid(P.agpInner), label: "25–75%"),
                    LegendItem(swatch: .solid(P.agpOuter), label: "5–95%"),
                ])
            }
            LoopCard {
                CardHeader(title: "Insulin per day") {
                    Text(s.totals.count > 30 ? "per day, weekly average" : "basal and bolus")
                }
                InsulinDailyTotalsView(totals: s.totals.count > 30 ? LoopHistoryMath.weekly(s.totals) : s.totals,
                                       weekly: s.totals.count > 30, average: s.insulinPerDay) { day in
                    path.append(.day(day))
                }
                ChartLegend(items: insulinLegend(s))
            }
            LoopCard {
                CardHeader(title: "Loop status") {
                    Button("Gaps") { path.append(.gaps) }
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
                ChartPlaceholder(message: "Couldn't load Trends: \(error)")
                Button("Retry") { model.reload() }.foregroundStyle(P.accentInk)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    private func summaryCard(_ s: TrendsModel.Summary) -> some View {
        LoopCard {
            CardHeader(title: "Summary") {
                Menu("Export") {
                    Button("PDF report") { export { try model.exportPDF(s) } }
                    Button("CSV, one row per day") { export { try model.exportCSV(s) } }
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
        return [
            LegendItem(swatch: .solid(P.insulin), label: String(format: "Bolus %.1f U (%d%%)", s.bolusUnits / days, bolusShare)),
            LegendItem(swatch: .basal, label: String(format: "Basal %.1f U (%d%%)", s.basalUnits / days, total > 0 ? 100 - bolusShare : 0)),
            LegendItem(swatch: .dash(P.ink), label: String(format: "Average %.1f U", s.insulinPerDay)),
        ]
    }

    private func coverageNote(_ s: TrendsModel.Summary) -> String? {
        guard let start = s.loopSpans.first?.start else {
            return "Loop status is recorded from when the new interface was first opened."
        }
        guard start > s.interval.start else { return nil }
        return "Covers \(LoopFormat.range(start, s.interval.end)): Loop keeps 7 days of runs, and closed or open loop is recorded from when the new interface was first opened."
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
                Text("Loop trends").font(.title2.bold())
                Text(LoopFormat.range(summary.interval.start, summary.interval.end.addingTimeInterval(-1)))
                    .font(.subheadline)
                    .foregroundStyle(P.inkMuted)
            }
            StatGridView(tiles: tiles)
            HStack(alignment: .top, spacing: LoopDesign.Space.s4) {
                VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                    Text("Time in range").font(.headline)
                    TimeInRangeView(fractions: summary.timeInRange, unit: summary.unit)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                Text("Daily pattern").font(.headline)
                TrendsAGPChart(slots: summary.agp, readings: summary.glucose, days: summary.agpDays, unit: summary.unit,
                             targetRange: summary.targetRange, height: 160)
            }
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                Text("Insulin per day").font(.headline)
                InsulinDailyTotalsView(totals: summary.totals.count > 30 ? LoopHistoryMath.weekly(summary.totals) : summary.totals,
                                       weekly: summary.totals.count > 30, average: summary.insulinPerDay, height: 140)
            }
            VStack(alignment: .leading, spacing: LoopDesign.Space.s2) {
                Text("Loop status").font(.headline)
                LoopModeBarView(spans: summary.loopSpans)
            }
        }
        .padding(LoopDesign.Space.s2)
        .background(Color.white)
    }
}
