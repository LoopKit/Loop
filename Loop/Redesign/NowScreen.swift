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
        /// Set when the message is the device's own status highlight, which the Now screen spells out in a notice.
        var symbol: String? = nil
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
    /// Closed loop is switched on but Loop has paused it, for example while the CGM has no session or data.
    @Published private(set) var closedLoopPaused = false
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
    @Published private(set) var preMealAvailable = false
    @Published private(set) var dosingAvailable = true
    @Published private(set) var preMealOn = false
    @Published private(set) var overrideName: String?
    @Published private(set) var unit: GlucoseUnitStyle
    @Published var now = Date()
    /// Set by StatusTableViewController, which owns the onboarding state.
    var isOnboardingComplete: () -> Bool = { true }

    let provider: LoopHistoryProvider
    private let deviceManager: DeviceDataManager
    private let automaticDosingStatus: AutomaticDosingStatus
    private var refreshTask: Task<Void, Never>?
    private var pendingRefresh = false

    init(deviceManager: DeviceDataManager, automaticDosingStatus: AutomaticDosingStatus) {
        self.deviceManager = deviceManager
        self.automaticDosingStatus = automaticDosingStatus
        self.provider = LoopHistoryProvider(deviceManager: deviceManager)
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
        return now.timeIntervalSince(reading.date) > LoopCoreConstants.inputDataRecencyInterval
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

        let loopManager = deviceManager.loopManager!
        let state: (predicted: [GlucosePoint], iob: Double?, cob: Double?, failed: Bool) = await withCheckedContinuation { continuation in
            loopManager.getLoopState { _, state in
                let predicted = (state.predictedGlucoseIncludingPendingInsulin ?? []).map {
                    GlucosePoint(date: $0.startDate, mgdl: $0.quantity.doubleValue(for: .milligramsPerDeciliter))
                }
                continuation.resume(returning: (predicted, state.insulinOnBoard?.value, state.carbsOnBoard?.quantity.doubleValue(for: .gram()), state.error != nil))
            }
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

        prediction = state.predicted
        iob = state.iob
        cob = state.cob
        lastLoopFailed = state.failed
        lastLoopCompleted = loopManager.lastLoopCompleted
        closedLoop = automaticDosingStatus.automaticDosingEnabled
        closedLoopPaused = loopManager.dosingEnabled && !automaticDosingStatus.isAutomaticDosingAllowed
        targetRange = provider.glucoseTargetRange
        predictionTargets = provider.glucoseTargetBands(in: DateInterval(start: now.addingTimeInterval(-3 * 3600), end: now.addingTimeInterval(3 * 3600)))
        todayTargets = provider.glucoseTargetBands(in: window)

        if let latest = deviceManager.glucoseStore.latestGlucose {
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

        let scheduled = loopManager.basalRateScheduleApplyingOverrideHistory?.value(at: now)
        scheduledBasalRate = scheduled
        basalDeliveryState = loopManager.basalDeliveryState
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

        let settings = loopManager.settings
        // The same rules as the classic toolbar.
        preMealAvailable = isOnboardingComplete()
            && (automaticDosingStatus.automaticDosingEnabled || !FeatureFlags.simpleBolusCalculatorEnabled)
            && settings.preMealTargetRange != nil
        dosingAvailable = isOnboardingComplete() || deviceManager.pumpManager?.isOnboarded == true
        preMealOn = settings.preMealTargetEnabled()
        if let override = settings.scheduleOverride, override.isActive() {
            switch override.context {
            case .preset(let preset): overrideName = preset.name
            case .custom: overrideName = "Custom preset"
            case .legacyWorkout: overrideName = "Workout"
            case .preMeal: overrideName = nil
            }
        } else {
            overrideName = nil
        }
    }

    private func device(name: String, highlight: DeviceStatusHighlight?, progress: DeviceLifecycleProgress?) -> Device {
        if let highlight {
            // Plugins wrap highlights onto two lines for the classic HUD ("Signal\nLoss").
            let message = highlight.localizedMessage.replacingOccurrences(of: "\n", with: " ")
            return Device(name: name, message: message, state: highlight.state, symbol: highlight.imageName)
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
    var togglePreMeal: () -> Void = {}
    var customPresets: () -> Void = {}
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
            if !noticeItems.isEmpty {
                notices
            }
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

    // Status pills replace Loop's HUD icons with words. They wrap rather than scroll, so a device is never off-screen.
    private var statusRow: some View {
        FlowRow(spacing: LoopDesign.Space.s2) {
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
        .buttonStyle(.plain)
    }

    // A device problem or a stalled loop gets a notice in words under the pills, most serious first.
    private var notices: some View {
        let items = noticeItems
        return VStack(spacing: LoopDesign.Space.s2) {
            ForEach(items) { item in
                Button(action: item.action) {
                    DeviceNotice(item: item)
                }
                .buttonStyle(.plain)
                .accessibilityHint(item.hint)
            }
        }
    }

    private var noticeItems: [DeviceNotice.Item] {
        var items: [DeviceNotice.Item] = []
        if model.loopState == .failed, let last = model.lastLoopCompleted {
            items.append(DeviceNotice.Item(
                id: "loop",
                severity: .critical,
                symbol: "exclamationmark.arrow.circlepath",
                title: "Loop hasn't run for \(LoopFormat.ago(last, now: model.now))",
                detail: "Insulin isn't being adjusted. Tap for details.",
                hint: "Shows when Loop last ran",
                action: actions.loopStatusTapped))
        }
        // While suspended, Loop's own status row says so and offers Resume, so only a critical pump problem adds a notice.
        if let pump = model.pump, let symbol = pump.symbol, let message = pump.message,
           !model.suspended || pump.state == .critical {
            let severity = DeviceNotice.Severity(pump.state)
            items.append(DeviceNotice.Item(
                id: "pump",
                severity: severity,
                symbol: symbol,
                title: message,
                detail: severity == .critical ? "Loop may not be giving insulin." : nil,
                hint: "Opens pump settings",
                action: actions.pumpTapped))
        }
        if let cgm = model.cgm, let symbol = cgm.symbol, let message = cgm.message {
            let severity = DeviceNotice.Severity(cgm.state)
            items.append(DeviceNotice.Item(
                id: "cgm",
                severity: severity,
                symbol: symbol,
                title: message,
                detail: model.readingIsStale ? "Loop can't adjust insulin without readings." : nil,
                hint: "Opens CGM settings",
                action: actions.cgmTapped))
        }
        return items.sorted { $0.severity > $1.severity }
    }

    private var loopText: String {
        let mode = model.closedLoop ? "Closed loop" : model.closedLoopPaused ? "Closed loop paused" : "Open loop"
        guard let last = model.lastLoopCompleted else { return "\(mode) · not run yet" }
        switch model.loopState {
        case .failed: return "Loop failed · \(LoopFormat.ago(last, now: model.now))"
        default: return "\(mode) · \(LoopFormat.ago(last, now: model.now))"
        }
    }

    /// Green only while closed loop is running; open loop that ran on time is neutral.
    private var loopColor: Color {
        switch model.loopState {
        case .fresh: return model.closedLoop ? P.statusAutomated : model.closedLoopPaused ? P.statusWarning : P.inkMuted
        case .stale: return P.statusWarning
        case .failed, .never: return P.statusCritical
        }
    }

    /// A highlight is spelled out in its notice, so its pill keeps to the device name.
    private func pillText(_ device: NowModel.Device) -> String {
        guard let message = device.message, device.symbol == nil else { return device.name }
        return "\(device.name) · \(message)"
    }

    private func pillColor(_ device: NowModel.Device) -> Color? {
        switch device.state {
        case .critical?: return P.statusCritical
        case .warning?: return P.statusWarning
        default: return device.symbol == nil ? nil : P.inkMuted
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
            if model.preMealAvailable {
                presetsMenu
            } else {
                // Only one choice, so open it directly, as the classic Workout button does.
                Button(action: actions.customPresets) {
                    actionLabel(presetsTitle, systemImage: "slider.horizontal.3", fill: presetsFill, text: P.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Presets")
                .accessibilityValue(presetsTitle == "Presets" ? "" : presetsTitle)
            }
        }
    }

    private var presetsFill: Color {
        model.preMealOn || model.overrideName != nil ? P.accent.opacity(0.18) : P.surfaceSunken
    }

    private var presetsMenu: some View {
        Menu {
            if model.preMealAvailable {
                Button(action: actions.togglePreMeal) {
                    Label(model.preMealOn ? "Turn off pre-meal" : "Pre-meal", systemImage: "fork.knife.circle")
                }
            }
            Button(action: actions.customPresets) {
                if let name = model.overrideName {
                    Label("Turn off \(name)", systemImage: "slider.horizontal.3")
                } else {
                    Label("Presets", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            actionLabel(presetsTitle, systemImage: "slider.horizontal.3", fill: presetsFill, text: P.ink)
        }
        .accessibilityLabel("Presets")
        .accessibilityValue(presetsTitle == "Presets" ? "" : presetsTitle)
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

// MARK: - Notices

/// One problem in words: what the device or Loop reports, what it means, and where to go.
struct DeviceNotice: View {
    enum Severity: Int, Comparable {
        case info, warning, critical

        init(_ state: DeviceStatusHighlightState?) {
            switch state {
            case .critical?: self = .critical
            case .warning?: self = .warning
            default: self = .info
            }
        }

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Item: Identifiable {
        let id: String
        let severity: Severity
        let symbol: String
        let title: String
        let detail: String?
        let hint: String
        let action: () -> Void
    }

    let item: Item

    private var tint: Color {
        switch item.severity {
        case .critical: return P.statusCritical
        case .warning: return P.statusWarning
        case .info: return P.inkMuted
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: LoopDesign.Space.s3) {
            Image(systemName: item.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(item.severity == .critical ? P.criticalInk : tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(LoopDesign.Typeface.headline)
                    .foregroundStyle(item.severity == .critical ? P.criticalInk : P.ink)
                if let detail = item.detail {
                    Text(detail)
                        .font(LoopDesign.Typeface.subhead)
                        .foregroundStyle(P.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(P.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(LoopDesign.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(item.severity == .info ? 0.12 : 0.16), in: RoundedRectangle(cornerRadius: LoopDesign.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LoopDesign.Radius.lg, style: .continuous)
                .strokeBorder(tint.opacity(item.severity == .info ? 0 : 0.45), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Lays its children out left to right and starts a new line when the next one won't fit.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if !row.indices.isEmpty && row.width + spacing + itemWidth > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + itemWidth
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
