//
//  ComplicationPublisher.swift
//  WatchApp Extension
//
//  Feeds the Loop Complications widget extension. On every context update the watch app formats what
//  the complications show (with the same formatters and localized strings the ClockKit templates
//  used), gathers the glucose graph's data for the widget to draw, writes both to the shared app
//  group, and asks WidgetKit to reload (ComplicationReloadThrottle decides when).
//

import Foundation
import LoopAlgorithm
import LoopCore
import LoopKit
import WatchKit
import WidgetKit

enum ComplicationPublisher {

    private static var throttle = ComplicationReloadThrottle<ComplicationSnapshot>()

    /// Called on main at each context update.
    @MainActor static func publish(from loopManager: LoopDataManager) {
        guard let context = loopManager.displayContext else { return }
        Task { @MainActor in
            let now = Date()
            let graph = await loopManager.generateChartData().map { self.graph(from: $0, now: now) }
            store(snapshot(from: context, graph: graph), now: now)
        }
    }

    /// The graph's data as stock's ClockKit chart drew it, kept an extra hour ahead for later timeline entries.
    static func graph(from data: GlucoseChartData, now: Date) -> ComplicationGraph {
        let unit = data.unit ?? .milligramsPerDeciliter
        let span = ComplicationGraph.halfSpan
        let visible = DateInterval(start: now - span, end: now + span)
        let kept = DateInterval(start: now - span, end: now + span + .hours(1))
        let range = data.chartableGlucoseRange(from: visible)
        let formatter = NumberFormatter.glucoseFormatter(for: unit)

        let targetRanges = data.correctionRange?.quantityBetween(start: kept.start, end: kept.end).map {
            ComplicationGraph.Band(start: $0.startDate, end: $0.endDate,
                                   min: $0.value.lowerBound.doubleValue(for: unit), max: $0.value.upperBound.doubleValue(for: unit))
        } ?? []
        let override = data.activeScheduleOverride.flatMap(TemporaryScheduleOverrideHashable.init).map {
            ComplicationGraph.Band(start: $0.start, end: $0.end,
                                   min: $0.min.doubleValue(for: unit), max: $0.max.doubleValue(for: unit))
        }
        let historical = (data.historicalGlucose ?? []).filter { kept.contains($0.startDate) }.map {
            ComplicationGraph.Point(date: $0.startDate, value: $0.quantity.doubleValue(for: unit), isManual: $0.isManualGlucose)
        }
        let predicted = (data.predictedGlucose ?? []).filter { kept.contains($0.startDate) }.map {
            ComplicationGraph.Point(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
        }
        let glucoseMin = range.lowerBound.doubleValue(for: unit)
        let glucoseMax = range.upperBound.doubleValue(for: unit)
        return ComplicationGraph(glucoseMin: glucoseMin, glucoseMax: glucoseMax,
                                 minLabel: formatter.string(from: glucoseMin) ?? "", maxLabel: formatter.string(from: glucoseMax) ?? "",
                                 targetRanges: targetRanges, override: override, historical: historical, predicted: predicted)
    }

    /// The strings each complication shows, formatted as the ClockKit templates formatted them.
    static func snapshot(from context: WatchContext, graph: ComplicationGraph?) -> ComplicationSnapshot {
        let unit = context.displayGlucoseUnit ?? .milligramsPerDeciliter
        let formatter = NumberFormatter.glucoseFormatter(for: unit)
        let staleGlucose = NSLocalizedString("---", comment: "No glucose value representation (3 dashes for mg/dL; no spaces as this will get truncated in the watch complication)")

        let glucoseText: String? = context.glucoseCondition?.localizedDescription
            ?? context.glucose.flatMap { formatter.string(from: $0.doubleValue(for: unit)) }
        let trendSymbol = context.glucoseTrend?.symbol
        let eventualText = context.eventualGlucose.flatMap { formatter.string(from: $0.doubleValue(for: unit)) }

        var inlineText: String?
        var inlineStaleText: String?
        if let glucoseDate = context.glucoseDate {
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            // 106↗108 8:47 PM
            let format = NSLocalizedString("UtilitarianLargeFlat", tableName: "ckcomplication", comment: "Utilitarian large flat format string (1: Glucose & Trend symbol) (2: Eventual Glucose) (3: Time)")
            let time = timeFormatter.string(from: glucoseDate)
            inlineText = String(format: format, "\(glucoseText ?? staleGlucose)\(trendSymbol ?? " ")", eventualText ?? "", time)
            inlineStaleText = String(format: format, staleGlucose, eventualText ?? "", time)
        }

        let loopDate = context.loopLastRunDate
        return ComplicationSnapshot(
            glucoseText: glucoseText,
            trendSymbol: trendSymbol,
            staleGlucoseText: staleGlucose,
            glucoseStaleAt: context.glucoseDate.map { $0.addingTimeInterval(LoopAlgorithm.inputDataRecencyInterval) },
            eventualText: eventualText,
            inlineText: inlineText,
            inlineStaleText: inlineStaleText,
            loopDate: loopDate,
            freshUntil: loopDate.flatMap { date in LoopCompletionFreshness.fresh.maxAge.map { date.addingTimeInterval($0) } },
            agingUntil: loopDate.flatMap { date in LoopCompletionFreshness.aging.maxAge.map { date.addingTimeInterval($0) } },
            graph: graph
        )
    }

    @MainActor private static func store(_ snapshot: ComplicationSnapshot, now: Date) {
        let decision = throttle.offer(snapshot, now: now)
        if decision.save { snapshot.save() }
        // Only these kinds: WidgetKit budgets reloads per widget, and other widgets keep their own.
        if decision.reload { LoopComplicationKind.all.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) } }
    }
}
