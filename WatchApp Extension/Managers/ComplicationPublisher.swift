//
//  ComplicationPublisher.swift
//  WatchApp Extension
//
//  Feeds the Loop Complications widget extension. On every context update the watch app formats what
//  the complications show (with the same formatters and localized strings the ClockKit templates
//  used), renders the glucose graph with ComplicationChartManager, writes both to the shared app
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
    private static let chartManager = ComplicationChartManager()

    /// Called on main at each context update.
    @MainActor static func publish(from loopManager: LoopDataManager) {
        guard let context = loopManager.activeContext else { return }
        Task { @MainActor in
            chartManager.data = await loopManager.generateChartData()
            let graphRendered = renderGraph()
            store(snapshot(from: context, graphRenderedAt: graphRendered ? Date() : nil), now: Date())
        }
    }

    /// The strings each complication shows, formatted as the ClockKit templates formatted them.
    static func snapshot(from context: WatchContext, graphRenderedAt: Date?) -> ComplicationSnapshot {
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
            graphRenderedAt: graphRenderedAt
        )
    }

    /// The graph at the size the ClockKit template used; the widget scales it to its slot.
    @MainActor private static func renderGraph() -> Bool {
        guard let url = ComplicationSnapshot.graphURL else { return false }
        let size: CGSize = WKInterfaceDevice.current().screenBounds.width > 180
            ? CGSize(width: 171, height: 54)    // 44 mm and larger
            : CGSize(width: 150, height: 47)    // 40 mm
        guard let image = chartManager.renderChartImage(size: size, scale: WKInterfaceDevice.current().screenScale),
              let png = image.pngData() else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return (try? png.write(to: url, options: .atomic)) != nil
    }

    @MainActor private static func store(_ snapshot: ComplicationSnapshot, now: Date) {
        let decision = throttle.offer(snapshot, now: now)
        if decision.save { snapshot.save() }
        // Only these kinds: WidgetKit budgets reloads per widget, and other widgets keep their own.
        if decision.reload { LoopComplicationKind.all.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) } }
    }
}
