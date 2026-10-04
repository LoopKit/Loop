//
//  GlanceComplicationPublisher.swift
//  WatchApp Extension
//
//  Feeds the Sport glance complication (Loop Complications, kind "LoopGlance"). Its source is the
//  glance's: during a loan the watch's own loop, through `GlanceViewModel.activeState` over the glance
//  mirror; otherwise the phone's context, which on next-dev carries the watch's own G7 reading. So a
//  complication never disagrees with the Start screen. Published at every wake — each landed cycle
//  during a loan, each context update otherwise — and WidgetKit is asked to redraw only when a shown
//  string changed (ComplicationReloadThrottle).
//

import Foundation
import LoopAlgorithm
import LoopCore
import LoopKit
import WidgetKit

enum GlanceComplicationPublisher {

    private static var throttle = ComplicationReloadThrottle<GlanceComplicationSnapshot>()

    /// Called on main by the extension delegate, which passes itself (`ExtensionDelegate.shared()`
    /// asserts while a test host is still launching).
    @MainActor static func publish(from delegate: ExtensionDelegate) {
        let context = delegate.loopManager.activeContext
        let unit = context?.displayGlucoseUnit ?? .milligramsPerDeciliter

        if let session = delegate.stockLoopSession, session.loanController.isLoanActiveNonBlocking,
           let data = session.stack.loopManager.mirroredGlanceData {
            session.stack.loopManager.glanceCarbsOnBoard { cob in
                Task { @MainActor in
                    store(snapshot(loan: data, cob: cob, unit: unit, now: Date()), source: "watch loop")
                }
            }
            return
        }
        guard let context else { return }
        store(snapshot(phone: context, override: delegate.loopManager.watchInfo.scheduleOverride), source: "phone context")
    }

    /// The watch holds the pod: the glance's own frame, with the reading in the display unit.
    @MainActor static func snapshot(loan data: WatchLoopManager.GlanceData, cob: Double?, unit: LoopUnit, now: Date) -> GlanceComplicationSnapshot {
        let glance = GlanceViewModel.activeState(data: data, cob: cob, now: now)
        let formatter = NumberFormatter.glucoseFormatter(for: unit)
        func text(_ quantity: LoopQuantity?) -> String? { quantity.flatMap { formatter.string(from: $0.doubleValue(for: unit)) } }

        var s = loop(date: data.lastLoopCompleted, closed: data.closedLoopEnabled)
        s.bgText = text(data.glucose)
        s.trendSymbol = data.trend?.symbol
        s.bgStaleAt = data.glucoseDate.map { $0.addingTimeInterval(LoopAlgorithm.inputDataRecencyInterval) }
        switch glance.bgColor {
        case .low: s.bgRange = .low
        case .inRange: s.bgRange = .inRange
        case .high: s.bgRange = .high
        case .dim: s.bgRange = nil
        }
        s.eventualText = text(data.eventual)
        s.iobText = data.iob == nil ? nil : glance.iobText
        s.cobText = cob == nil ? nil : glance.cobText
        s.tempText = data.tempRate == nil ? nil : glance.tempText
        s.overrideLabel = glance.overrideLabel
        s.watchHasPod = true
        return s
    }

    /// The phone loops: its context, formatted as the glance formats.
    static func snapshot(phone context: WatchContext, override: TemporaryScheduleOverride?) -> GlanceComplicationSnapshot {
        let unit = context.displayGlucoseUnit ?? .milligramsPerDeciliter
        let formatter = NumberFormatter.glucoseFormatter(for: unit)

        var s = loop(date: context.loopLastRunDate, closed: context.isClosedLoop ?? true)
        s.bgText = context.glucoseCondition?.localizedDescription
            ?? context.glucose.flatMap { formatter.string(from: $0.doubleValue(for: unit)) }
        s.trendSymbol = context.glucoseTrend?.symbol
        s.bgStaleAt = context.glucoseDate.map { $0.addingTimeInterval(LoopAlgorithm.inputDataRecencyInterval) }
        s.eventualText = context.eventualGlucose.flatMap { formatter.string(from: $0.doubleValue(for: unit)) }
        s.iobText = context.iob.map { String(format: "%.1f", $0) }
        s.cobText = context.cob.map { String(format: "%.0f", $0) }
        s.tempText = context.lastNetTempBasalDose.map { String(format: "%+.2f", $0) }
        s.overrideLabel = WatchLoopManager.overrideLabel(for: override)
        return s
    }

    /// The loop's ring and the moment its values go stale, from one cycle date.
    private static func loop(date: Date?, closed: Bool) -> GlanceComplicationSnapshot {
        var s = GlanceComplicationSnapshot()
        s.loopClosed = closed
        s.loopDate = date
        s.loopValuesStaleAt = date.map { $0.addingTimeInterval(LoopAlgorithm.inputDataRecencyInterval) }
        s.freshUntil = date.flatMap { d in LoopCompletionFreshness.fresh.maxAge.map { d.addingTimeInterval($0) } }
        s.agingUntil = date.flatMap { d in LoopCompletionFreshness.aging.maxAge.map { d.addingTimeInterval($0) } }
        return s
    }

    /// The last publish, for the diagnostics line.
    private static var lastLoggedAt = Date()

    @MainActor private static func store(_ snapshot: GlanceComplicationSnapshot, source: String) {
        let now = Date()
        let decision = throttle.offer(snapshot, now: now)
        if decision.save { snapshot.save() }
        if decision.reload { WidgetCenter.shared.reloadTimelines(ofKind: GlanceComplicationKind.kind) }

        // Confirmation runs C1/C2: requested vs served redraws, and how old the shown values are.
        let served = GlanceComplicationSnapshot.served(after: lastLoggedAt)
        lastLoggedAt = now
        func age(_ date: Date?) -> String { date.map { "\(Int(now.timeIntervalSince($0)))s" } ?? "n/a" }
        let reload = decision.reload ? "requested" : (throttle.reloadOwed ? "owed" : "none")
        let metrics = Set(served.map(\.metric)).sorted().joined(separator: ",")
        let bgAge = snapshot.bgStaleAt.map { $0.addingTimeInterval(-LoopAlgorithm.inputDataRecencyInterval) }
        SportLog.event("complication", "glance publish src=\(source) changed=\(decision.save) reload=\(reload) · served since last: \(served.count) [\(metrics)] · BG age \(age(bgAge)) · loop age \(age(snapshot.loopDate))")
    }
}
