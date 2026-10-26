//
//  NowScreen.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI
import LoopCore
import LoopAlgorithm

private typealias P = LoopDesign.Palette

/// What the Now screen shows. StatusTableViewController owns it and asks it to refresh whenever Loop's data changes.
@MainActor
final class NowModel: ObservableObject {

    struct Reading: Equatable {
        let mgdl: Double
        let date: Date
        let trend: GlucoseTrend?
        /// Change since the previous reading, per 5 minutes.
        let delta: Double?
    }

    struct Device: Equatable {
        let name: String
        let message: String?
        let state: DeviceStatusHighlightState?
    }

    enum LoopState: Equatable {
        case fresh
        case stale
        case failed
        case never
    }

    @Published private(set) var reading: Reading?
    @Published private(set) var lastLoopCompleted: Date?
    @Published private(set) var lastLoopFailed = false
    @Published private(set) var closedLoop = false
    @Published private(set) var iob: Double?
    @Published private(set) var cob: Double?
    @Published private(set) var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    @Published private(set) var scheduledBasalRate: Double?
    @Published private(set) var suspended = false
    @Published private(set) var targetRange: ClosedRange<Double>?
    @Published private(set) var predictionTargets: [TargetBand] = []
    @Published private(set) var todayTargets: [TargetBand] = []
    @Published private(set) var prediction: [GlucosePoint] = []
    @Published private(set) var recentGlucose: [GlucosePoint] = []
    @Published private(set) var historyError: String?
    @Published private(set) var glucoseHistoryError: String?
    @Published private(set) var today: DayHistory
    @Published private(set) var pump: Device?
    @Published private(set) var cgm: Device?
    @Published private(set) var dosingAvailable = true
    @Published private(set) var preMealOn = false
    @Published private(set) var overrideName: String?
    @Published private(set) var unit: GlucoseUnitStyle
    @Published var now = Date()
    /// Set by StatusTableViewController, which owns the onboarding state.
    var isOnboardingComplete: () -> Bool = { true }

    let provider: LoopHistoryProvider
    private let deviceManager: DeviceDataManager
    private let loopDataManager: LoopDataManager
    private let settingsManager: SettingsManager
    private let temporaryPresetsManager: TemporaryPresetsManager
    private var refreshTask: Task<Void, Never>?
    private var pendingRefresh = false

    init(deviceManager: DeviceDataManager, loopDataManager: LoopDataManager, settingsManager: SettingsManager, temporaryPresetsManager: TemporaryPresetsManager) {
        self.deviceManager = deviceManager
        self.loopDataManager = loopDataManager
        self.settingsManager = settingsManager
        self.temporaryPresetsManager = temporaryPresetsManager
        self.provider = LoopHistoryProvider(deviceManager: deviceManager, loopDataManager: loopDataManager, settingsManager: settingsManager, temporaryPresetsManager: temporaryPresetsManager)
        self.unit = provider.unitStyle
        let start = Calendar.current.startOfDay(for: Date())
        self.today = DayHistory(window: DateInterval(start: start, duration: 86400))
    }

    var basalRate: Double? {
        switch basalDeliveryState {
        case .tempBasal(let dose)?:
            return dose.startDate <= now && now < dose.endDate ? dose.unitsPerHour : scheduledBasalRate
        case .active?: return scheduledBasalRate
        case .suspended?, .suspending?: return 0
        default: return nil
        }
    }

    var loopState: LoopState {
        guard let lastLoopCompleted else { return .never }
        let age = now.timeIntervalSince(lastLoopCompleted)
        if age <= 5 * 60 + 30 { return .fresh }
        if age <= 15 * 60 { return .stale }
        return .failed
    }

    var readingIsStale: Bool {
        guard let reading else { return true }
        return now.timeIntervalSince(reading.date) > LoopAlgorithm.inputDataRecencyInterval
    }

    /// Refreshes everything; calls made while a refresh runs are coalesced into one more.
    func refresh() {
        guard refreshTask == nil else {
            pendingRefresh = true
            return
        }
        refreshTask = Task { [weak self] in
            await self?.load()
            guard let self else { return }
            self.refreshTask = nil
            if self.pendingRefresh {
                self.pendingRefresh = false
                self.refresh()
            }
        }
    }

    private func load() async {
        let now = Date()
        self.now = now
        unit = provider.unitStyle

        let displayState = await loopDataManager.algorithmDisplayState
        let predicted = (displayState.output?.predictedGlucose ?? []).map {
            GlucosePoint(date: $0.startDate, mgdl: $0.quantity.doubleValue(for: .milligramsPerDeciliter))
        }
        var failed = false
        if let output = displayState.output, case .failure = output.recommendationResult {
            failed = true
        }

        let start = Calendar.current.startOfDay(for: now)
        let window = DateInterval(start: start, end: Calendar.current.date(byAdding: .day, value: 1, to: start)!)
        async let dayFetch = provider.dayHistory(window)
        async let recentFetch = provider.glucose(DateInterval(start: now.addingTimeInterval(-3 * 3600), end: now))
        do {
            today = try await dayFetch
            historyError = nil
        } catch {
            historyError = error.localizedDescription
        }
        do {
            recentGlucose = try await recentFetch
            glucoseHistoryError = nil
        } catch {
            recentGlucose = []
            glucoseHistoryError = error.localizedDescription
        }

        prediction = predicted
        iob = loopDataManager.activeInsulin?.value
        cob = loopDataManager.activeCarbs?.quantity.doubleValue(for: .gram)
        lastLoopFailed = failed
        lastLoopCompleted = loopDataManager.lastLoopCompleted
        closedLoop = settingsManager.dosingEnabled
        targetRange = provider.glucoseTargetRange
        predictionTargets = provider.glucoseTargetBands(in: DateInterval(start: now.addingTimeInterval(-3 * 3600), end: now.addingTimeInterval(3 * 3600)))
        todayTargets = provider.glucoseTargetBands(in: window)

        if let latest = loopDataManager.latestGlucose {
            let mgdl = latest.quantity.doubleValue(for: .milligramsPerDeciliter)
            let previous = recentGlucose.last { $0.date < latest.startDate.addingTimeInterval(-60) }
            var delta: Double? = nil
            if let previous, latest.startDate.timeIntervalSince(previous.date) <= 15 * 60 {
                delta = (mgdl - previous.mgdl) / latest.startDate.timeIntervalSince(previous.date) * 300
            }
            // The CGM's own trend, as the classic HUD shows it.
            reading = Reading(mgdl: mgdl, date: latest.startDate, trend: deviceManager.glucoseDisplay(for: latest)?.trendType, delta: delta)
        } else {
            reading = nil
        }

        let scheduled = temporaryPresetsManager.basalRateScheduleApplyingOverrideHistory?.value(at: now)
        scheduledBasalRate = scheduled
        basalDeliveryState = deviceManager.pumpManagerStatus?.basalDeliveryState
        switch basalDeliveryState {
        case .suspended?, .suspending?: suspended = true
        default: suspended = false
        }

        pump = deviceManager.pumpManager.map { manager in
            device(name: manager.localizedTitle, highlight: deviceManager.pumpStatusHighlight, progress: deviceManager.pumpLifecycleProgress)
        }
        cgm = deviceManager.cgmManager.map { manager in
            device(name: manager.localizedTitle, highlight: deviceManager.cgmStatusHighlight, progress: deviceManager.cgmLifecycleProgress)
        }

        dosingAvailable = isOnboardingComplete() || deviceManager.pumpManager?.isOnboarded == true
        preMealOn = temporaryPresetsManager.isPreMealTargetActive()
        overrideName = preMealOn ? nil : temporaryPresetsManager.activePreset?.name
    }

    private func device(name: String, highlight: DeviceStatusHighlight?, progress: DeviceLifecycleProgress?) -> Device {
        if let highlight {
            return Device(name: name, message: highlight.localizedMessage, state: highlight.state)
        }
        if let progress, progress.progressState == .warning || progress.progressState == .critical {
            return Device(name: name, message: "ending soon", state: progress.progressState == .critical ? .critical : .warning)
        }
        return Device(name: name, message: nil, state: nil)
    }
}

/// The buttons on the Now screen, wired to StatusTableViewController's existing flows.
struct NowActions {
    var addCarbs: () -> Void = {}
    var bolus: () -> Void = {}
    var presets: () -> Void = {}
    var showPrediction: () -> Void = {}
    var showToday: () -> Void = {}
    var showInsulin: () -> Void = {}
    var showCarbs: () -> Void = {}
    var pumpTapped: () -> Void = {}
    var cgmTapped: () -> Void = {}
    var loopStatusTapped: () -> Void = {}
}

// MARK: - Header: title, status, hero, actions

struct NowHeaderView: View {
    @ObservedObject var model: NowModel
    let actions: NowActions

    var body: some View {
        VStack(alignment: .leading, spacing: LoopDesign.Space.s3) {
            Text("Now")
                .font(LoopDesign.Typeface.title)
                .foregroundStyle(P.ink)
                .accessibilityAddTraits(.isHeader)
            statusRow
            hero
            actionRow
        }
        .padding(.horizontal, LoopDesign.Space.s4)
        .padding(.top, LoopDesign.Space.s2)
        .padding(.bottom, LoopDesign.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(P.surface)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { model.now = $0 }
    }

    // Status pills replace Loop's HUD icons with words.
    private var statusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LoopDesign.Space.s2) {
                Button(action: actions.loopStatusTapped) {
                    StatusPill(text: loopText, dot: loopColor)
                }
                .accessibilityHint("Shows when Loop last ran")
                Button(action: actions.pumpTapped) {
                    if let pump = model.pump {
                        StatusPill(text: pillText(pump), dot: pillColor(pump))
                    } else {
                        StatusPill(text: "Add pump", dot: P.statusCritical)
                    }
                }
                .accessibilityHint(model.pump == nil ? "Sets up a pump" : "Opens pump settings")
                Button(action: actions.cgmTapped) {
                    if let cgm = model.cgm {
                        StatusPill(text: pillText(cgm), dot: pillColor(cgm))
                    } else {
                        StatusPill(text: "Add CGM", dot: P.statusCritical)
                    }
                }
                .accessibilityHint(model.cgm == nil ? "Sets up a CGM" : "Opens CGM settings")
            }
        }
        .buttonStyle(.plain)
    }

    private var loopText: String {
        let mode = model.closedLoop ? "Closed loop" : "Open loop"
        guard let last = model.lastLoopCompleted else { return "\(mode) · not run yet" }
        switch model.loopState {
        case .failed: return "Loop failed · \(LoopFormat.ago(last, now: model.now))"
        default: return "\(mode) · \(LoopFormat.ago(last, now: model.now))"
        }
    }

    /// Green only while closed loop is running; open loop that ran on time is neutral.
    private var loopColor: Color {
        switch model.loopState {
        case .fresh: return model.closedLoop ? P.statusAutomated : P.inkMuted
        case .stale: return P.statusWarning
        case .failed, .never: return P.statusCritical
        }
    }

    private func pillText(_ device: NowModel.Device) -> String {
        guard let message = device.message else { return device.name }
        return "\(device.name) · \(message)"
    }

    private func pillColor(_ device: NowModel.Device) -> Color? {
        switch device.state {
        case .critical?: return P.statusCritical
        case .warning?: return P.statusWarning
        default: return nil
        }
    }

    private var hero: some View {
        LoopCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: LoopDesign.Space.s2) {
                        if let reading = model.reading, !model.readingIsStale {
                            Text(model.unit.format(reading.mgdl))
                                .font(LoopDesign.Typeface.glucoseHero)
                                .foregroundStyle(P.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            if let trend = reading.trend {
                                Image(systemName: Self.symbol(for: trend))
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(P.glucose)
                                    .accessibilityLabel(trend.localizedDescription)
                            }
                        } else {
                            Text("No reading")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(P.inkMuted)
                        }
                    }
                    Text(readingDetail)
                        .font(LoopDesign.Typeface.subhead)
                        .foregroundStyle(P.inkMuted)
                    if let rangePill {
                        StatusPill(text: rangePill.0, dot: rangePill.1)
                            .padding(.top, LoopDesign.Space.s1)
                    }
                }
                Spacer(minLength: LoopDesign.Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    if let reading = model.reading {
                        Text(LoopFormat.time(reading.date))
                    }
                    if let target = model.targetRange {
                        Text("Target \(model.unit.format(target.lowerBound))–\(model.unit.format(target.upperBound))")
                    }
                }
                .font(LoopDesign.Typeface.footnote)
                .foregroundStyle(P.inkMuted)
                .padding(.top, LoopDesign.Space.s4)
            }
            .accessibilityElement(children: .combine)

            AdaptiveRow {
                // As on the classic charts: insulin opens Loop's delivery history, carbs its absorption screen.
                Button(action: actions.showInsulin) {
                    ValueTile(label: "IOB") {
                        Text(model.iob.map(LoopFormat.doseUnits) ?? "–")
                            .font(LoopDesign.Typeface.statValueSmall)
                            .foregroundStyle(P.insulinInk)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens insulin delivery history")
                Button(action: actions.showCarbs) {
                    ValueTile(label: "COB") {
                        Text(model.cob.map(LoopFormat.grams) ?? "–")
                            .font(LoopDesign.Typeface.statValueSmall)
                            .foregroundStyle(P.carbsInk)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens carb absorption")
                ValueTile(label: "Basal") {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(model.basalRate.map { String(format: "%.2f", $0) } ?? "–")
                                .font(LoopDesign.Typeface.statValueSmall)
                                .foregroundStyle(P.ink)
                            Text("U/h")
                                .font(LoopDesign.Typeface.footnote)
                                .foregroundStyle(P.inkMuted)
                        }
                        if model.suspended {
                            Text("Suspended")
                                .font(LoopDesign.Typeface.footnote.weight(.semibold))
                                .foregroundStyle(P.criticalInk)
                        } else if let rate = model.basalRate, let scheduled = model.scheduledBasalRate {
                            Text("\(LoopFormat.signed(rate - scheduled)) vs plan")
                                .font(LoopDesign.Typeface.footnote)
                                .foregroundStyle(P.insulinInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(model.readingIsStale && model.reading != nil ? 0.7 : 1)
    }

    private var readingDetail: String {
        guard let reading = model.reading else { return model.unit.unitName }
        if model.readingIsStale {
            return "Last reading \(LoopFormat.ago(reading.date, now: model.now)) ago"
        }
        guard let delta = reading.delta else { return model.unit.unitName }
        let change = model.unit.isMmol ? LoopFormat.signed(delta / GlucoseUnitStyle.mgdlPerMmol, decimals: 1) : LoopFormat.signed(delta, decimals: 0)
        return "\(model.unit.unitName) · \(change) in 5 min"
    }

    /// Low and high get a pill with words; the number itself is never tinted.
    private var rangePill: (String, Color)? {
        guard let reading = model.reading, !model.readingIsStale else { return nil }
        if reading.mgdl < 54 { return ("Urgent low", P.statusCritical) }
        if reading.mgdl < 70 { return ("Low", P.statusCritical) }
        if reading.mgdl > 250 { return ("High", P.statusWarning) }
        return nil
    }

    static func symbol(for trend: GlucoseTrend) -> String {
        switch trend {
        case .upUpUp: return "arrow.up.to.line"
        case .upUp: return "chevron.up.2"
        case .up: return "arrow.up"
        case .flat: return "arrow.right"
        case .down: return "arrow.down"
        case .downDown: return "chevron.down.2"
        case .downDownDown: return "arrow.down.to.line"
        }
    }

    private var actionRow: some View {
        AdaptiveRow {
            actionButton("Add carbs", systemImage: "fork.knife", fill: P.carbs, text: P.onFill, action: actions.addCarbs)
                .disabled(!model.dosingAvailable)
                .opacity(model.dosingAvailable ? 1 : 0.4)
            actionButton("Bolus", systemImage: "syringe.fill", fill: P.insulin, text: P.onFill, action: actions.bolus)
                .disabled(!model.dosingAvailable)
                .opacity(model.dosingAvailable ? 1 : 0.4)
            // Pre-meal and the other presets share Loop's Presets screen.
            Button(action: actions.presets) {
                actionLabel(presetsTitle, systemImage: "slider.horizontal.3", fill: presetsFill, text: P.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Presets")
            .accessibilityValue(presetsTitle == "Presets" ? "" : presetsTitle)
        }
    }

    private var presetsFill: Color {
        model.preMealOn || model.overrideName != nil ? P.accent.opacity(0.18) : P.surfaceSunken
    }

    private var presetsTitle: String {
        if model.preMealOn { return "Pre-meal on" }
        if let name = model.overrideName { return name }
        return "Presets"
    }

    private func actionButton(_ title: String, systemImage: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, systemImage: systemImage, fill: fill, text: text)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, systemImage: String, fill: Color, text: Color) -> some View {
        Text(title)
            .font(LoopDesign.Typeface.subhead.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(fill, in: RoundedRectangle(cornerRadius: LoopDesign.Radius.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: LoopDesign.Radius.md))
    }
}

// MARK: - Charts: next 3 hours and today so far

struct NowChartsView: View {
    @ObservedObject var model: NowModel
    let actions: NowActions

    var body: some View {
        VStack(spacing: LoopDesign.Space.s4) {
            predictionCard
            todayCard
        }
        .padding(.horizontal, LoopDesign.Space.s4)
        .padding(.top, LoopDesign.Space.s2)
        .padding(.bottom, LoopDesign.Space.s6)
        .frame(maxWidth: .infinity)
        .background(P.surface)
    }

    private var readings: [GlucosePoint] {
        model.recentGlucose.filter { $0.date >= model.now.addingTimeInterval(-3 * 3600) }
    }

    private var predictionCard: some View {
        Button(action: actions.showPrediction) {
            LoopCard {
                CardHeader(title: "Next 3 hours") {
                    // Loop's eventual glucose is the end of its prediction, which can run past the three hours drawn.
                    if let last = model.prediction.last {
                        Text("Eventually \(model.unit.format(last.mgdl)) \(model.unit.unitName)")
                    }
                }
                if readings.isEmpty && model.prediction.isEmpty {
                    ChartPlaceholder(message: model.glucoseHistoryError == nil ? "No CGM data in the last 3 hours" : "Couldn't load recent CGM readings")
                } else {
                    PredictionChartView(readings: readings, prediction: model.prediction, unit: model.unit,
                                        targetBands: model.predictionTargets, now: model.now)
                }
                ChartLegend(items: [
                    LegendItem(swatch: .dot(P.glucose), label: "Readings"),
                    LegendItem(swatch: .dash(P.glucose), label: "Loop prediction"),
                ])
                if let error = model.glucoseHistoryError {
                    Text("Recent readings unavailable: \(error)")
                        .font(LoopDesign.Typeface.footnote)
                        .foregroundStyle(P.criticalInk)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Loop's prediction breakdown")
    }

    private var todayCard: some View {
        Button(action: actions.showToday) {
            LoopCard {
                CardHeader(title: "Today so far") {
                    if model.historyError == nil {
                        HStack(spacing: 4) {
                            Text(LoopFormat.totalUnits(model.today.totalUnits)).foregroundStyle(P.insulinInk)
                            Text("·")
                            Text(LoopFormat.grams(model.today.carbGrams)).foregroundStyle(P.carbsInk)
                        }
                    }
                }
                if let error = model.historyError {
                    ChartPlaceholder(message: "Couldn't load today's history: \(error)")
                } else {
                    InsulinTimelineView(history: model.today, unit: model.unit, targetBands: model.todayTargets, now: model.now, height: 230)
                    DayTotalsTiles(history: model.today)
                    ChartLegend(items: DayTotalsTiles.legend)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full day")
    }
}

/// Bolus, basal and carb totals under a timeline.
struct DayTotalsTiles: View {
    let history: DayHistory

    static let legend: [LegendItem] = [
        LegendItem(swatch: .solid(P.insulin), label: "Bolus"),
        LegendItem(swatch: .outline(P.insulin), label: "Automatic"),
        LegendItem(swatch: .basal, label: "Basal given"),
        LegendItem(swatch: .dash(P.basalScheduled), label: "Scheduled"),
    ]

    var body: some View {
        AdaptiveRow {
            ValueTile(label: "Bolus") {
                Text(LoopFormat.totalUnits(history.bolusUnits))
                    .font(LoopDesign.Typeface.statValueSmall)
                    .foregroundStyle(P.insulinInk)
            }
            ValueTile(label: "Basal") {
                Text(LoopFormat.totalUnits(history.basalUnits))
                    .font(LoopDesign.Typeface.statValueSmall)
                    .foregroundStyle(P.insulinInk)
            }
            ValueTile(label: "Carbs") {
                Text(LoopFormat.grams(history.carbGrams))
                    .font(LoopDesign.Typeface.statValueSmall)
                    .foregroundStyle(P.carbsInk)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
