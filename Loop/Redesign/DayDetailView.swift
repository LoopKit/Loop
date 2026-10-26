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
                        CardHeader(title: "Insulin") {
                            HStack(spacing: 4) {
                                Text(LoopFormat.totalUnits(history.totalUnits)).foregroundStyle(P.insulinInk)
                                Text("·")
                                Text(LoopFormat.grams(history.carbGrams)).foregroundStyle(P.carbsInk)
                            }
                        }
                        InsulinTimelineView(history: history, unit: provider.unitStyle, targetBands: provider.glucoseTargetBands(in: history.window),
                                            now: now, height: 300)
                        DayTotalsTiles(history: history)
                        ChartLegend(items: DayTotalsTiles.legend)
                        if history.source == .health {
                            Text("From Apple Health: Loop keeps 7 days, so this day has no temp basal or schedule detail.")
                                .font(LoopDesign.Typeface.footnote)
                                .foregroundStyle(P.inkMuted)
                        }
                        if #available(iOS 18.0, *) {
                            Text("Touch and hold a chart to see exact values.")
                                .font(LoopDesign.Typeface.footnote)
                                .foregroundStyle(P.inkMuted)
                        }
                    }
                    LoopCard {
                        CardHeader(title: "Active insulin and carbs")
                        if history.iob.isEmpty && history.cob.isEmpty {
                            ChartPlaceholder(message: history.source == .health
                                             ? "Loop only works out active insulin and carbs for the days it keeps"
                                             : "No active insulin or carbs on this day")
                        } else {
                            IOBCOBChartView(iob: history.iob, cob: history.cob, window: window, now: now)
                        }
                        ChartLegend(items: [
                            LegendItem(swatch: .solid(P.insulin), label: "IOB (U, left)"),
                            LegendItem(swatch: .solid(P.carbs), label: "COB (g, right)"),
                            LegendItem(swatch: .dash(P.inkMuted), label: "Projected"),
                        ])
                    }
                } else if let loadError {
                    ChartPlaceholder(message: "Couldn't load this day: \(loadError)")
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(LoopDesign.Space.s4)
        }
        .background(P.surface)
        .navigationTitle(isToday ? "Today" : LoopFormat.weekdayDay(day))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: day) {
            now = Date()
            let requestedWindow = window
            history = nil
            loadError = nil
            do {
                let result = try await provider.dayHistory(requestedWindow)
                guard !Task.isCancelled, window == requestedWindow else { return }
                history = result
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
            .accessibilityLabel("Previous day")
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
            .accessibilityLabel("Next day")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(P.accentInk)
    }
}
