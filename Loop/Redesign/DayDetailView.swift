//
//  DayDetailView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

private typealias P = LoopDesign.Palette

/// One full day on InsulinTimeline with IOB and COB under it, stepping a day at a time.
struct DayDetailView: View {
    let provider: LoopHistoryProvider

    @State private var day: Date
    @State private var history: DayHistory?
    @State private var targetBands: [TargetBand] = []
    @State private var now = Date()
    @State private var loadError: String?

    init(provider: LoopHistoryProvider, day: Date) {
        self.provider = provider
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    private var window: DateInterval {
        DateInterval(start: day, end: Calendar.current.date(byAdding: .day, value: 1, to: day)!)
    }

    private var isToday: Bool { Calendar.current.isDate(day, inSameDayAs: now) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LoopDesign.Space.s6) {
                dayStepper
                if let history {
                    LoopCard {
                        CardHeader(title: NSLocalizedString("Insulin", comment: "Title of the day page card showing insulin, carbs and glucose on one timeline")) {
                            HStack(spacing: 4) {
                                Text(LoopFormat.totalUnits(history.totalUnits)).foregroundStyle(P.insulinInk)
                                Text("·")
                                Text(LoopFormat.grams(history.carbGrams)).foregroundStyle(P.carbsInk)
                            }
                        }
                        InsulinTimelineView(history: history, unit: provider.unitStyle, targetBands: targetBands,
                                            now: now, height: 300)
                        ChartLegend(items: DayTotalsTiles.legend)
                        if history.source == .health {
                            Text(NSLocalizedString("From Apple Health: Loop keeps 7 days, so this day has no temp basal or schedule detail.", comment: "Day page note when the day is older than Loop's 7-day history and was read from Apple Health"))
                                .font(LoopDesign.Typeface.footnote)
                                .foregroundStyle(P.inkMuted)
                        }
                        if #available(iOS 18.0, *) {
                            Text(NSLocalizedString("Touch and hold a chart to see exact values.", comment: "Hint under the day page charts explaining how to scrub them"))
                                .font(LoopDesign.Typeface.footnote)
                                .foregroundStyle(P.inkMuted)
                        }
                    }
                    LoopCard {
                        CardHeader(title: NSLocalizedString("Basal and bolus", comment: "Trends card title: insulin split into basal and bolus"))
                        InsulinSplitView(split: history.insulinSplit, partial: isToday)
                        ValueTile(label: NSLocalizedString("Carbs", comment: "Label of a tile showing the day's total carbohydrate")) {
                            Text(LoopFormat.grams(history.carbGrams))
                                .font(LoopDesign.Typeface.statValueSmall)
                                .foregroundStyle(P.carbsInk)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    LoopCard {
                        CardHeader(title: NSLocalizedString("Active insulin and carbs", comment: "Title of the day page card charting insulin and carbs on board"))
                        if history.iob.isEmpty && history.cob.isEmpty {
                            ChartPlaceholder(message: history.source == .health
                                             ? NSLocalizedString("Loop only works out active insulin and carbs for the days it keeps", comment: "Day page placeholder for active insulin and carbs on a day older than Loop's 7-day history")
                                             : NSLocalizedString("No active insulin or carbs on this day", comment: "Day page placeholder when there was no insulin or carbs on board all day"))
                        } else {
                            IOBCOBChartView(iob: history.iob, cob: history.cob, window: window, now: now)
                        }
                        ChartLegend(items: [
                            LegendItem(swatch: .solid(P.insulin), label: NSLocalizedString("IOB (U, left)", comment: "Chart legend: insulin on board in units, on the left axis")),
                            LegendItem(swatch: .solid(P.carbs), label: NSLocalizedString("COB (g, right)", comment: "Chart legend: carbs on board in grams, on the right axis")),
                            LegendItem(swatch: .dash(P.inkMuted), label: NSLocalizedString("Projected", comment: "Chart legend: dashed lines show Loop's projection of insulin and carbs on board")),
                        ])
                    }
                } else if let loadError {
                    ChartPlaceholder(message: String(format: NSLocalizedString("Couldn't load this day: %1$@", comment: "Day page error when the day's history can't be read. (1: system error description)"), loadError))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(LoopDesign.Space.s4)
        }
        .background(P.surface)
        .navigationTitle(isToday ? NSLocalizedString("Today", comment: "Day page title when showing today") : LoopFormat.weekdayDay(day))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: day) {
            now = Date()
            let requestedWindow = window
            history = nil
            loadError = nil
            do {
                async let historyFetch = provider.dayHistory(requestedWindow)
                async let targetsFetch = provider.glucoseTargetBands(in: requestedWindow)
                let (result, targets) = try await (historyFetch, targetsFetch)
                guard !Task.isCancelled, window == requestedWindow else { return }
                history = result
                targetBands = targets
            } catch {
                guard !Task.isCancelled, window == requestedWindow else { return }
                loadError = error.localizedDescription
            }
        }
    }

    private var dayStepper: some View {
        HStack {
            Button {
                day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel(NSLocalizedString("Previous day", comment: "Accessibility label for the day page button that steps back a day"))
            Spacer()
            Text(LoopFormat.day(day))
                .font(LoopDesign.Typeface.headline)
                .foregroundStyle(P.ink)
            Spacer()
            Button {
                day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(isToday)
            .accessibilityLabel(NSLocalizedString("Next day", comment: "Accessibility label for the day page button that steps forward a day"))
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(P.accentInk)
    }
}
