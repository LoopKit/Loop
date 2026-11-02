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
        /// Set when the message is the device's own status highlight, which the Now screen spells out in a notice.
        var symbol: String? = nil
        /// The device's lifecycle (pod, sensor) is near its end; the pill says so.
        var endingSoon = false
    }

    enum LoopState: Equatable {
        case fresh
        case stale
        case failed
        case never
    }

    @Published private(set) var reading: Reading?
    @Published private(set) var lastLoopCompleted: Date?
    @Published private(set) var closedLoop = false
    /// Closed loop is switched on but Loop has paused it, for example while the CGM has no session or data.
    @Published private(set) var closedLoopPaused = false
    @Published private(set) var iob: Double?
    @Published private(set) var cob: Double?
    @Published private(set) var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    @Published private(set) var programmedBasalRate: Double?
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
            return dose.startDate <= now && now < dose.endDate ? dose.unitsPerHour : programmedBasalRate
        case .active?: return programmedBasalRate
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

        let displayState = await loopDataManager.algorithmDisplayState
        let predicted = (displayState.output?.predictedGlucose ?? []).map(\.loopKit).map {
            GlucosePoint(date: $0.startDate, mgdl: $0.quantity.doubleValue(for: .milligramsPerDeciliter))
        }
        let start = Calendar.current.startOfDay(for: now)
        let window = DateInterval(start: start, end: Calendar.current.date(byAdding: .day, value: 1, to: start)!)
        async let dayFetch = provider.dayHistory(window)
        async let recentFetch = provider.glucose(DateInterval(start: now.addingTimeInterval(-3 * 3600), end: now))
        do {
            let targets = try await provider.glucoseTargetBands(in: window)
            today = try await dayFetch
            todayTargets = targets
            historyError = nil
        } catch {
            historyError = error.localizedDescription
        }
        do {
            let predictionWindow = DateInterval(start: now.addingTimeInterval(-3 * 3600), end: now.addingTimeInterval(3 * 3600))
            predictionTargets = try await provider.glucoseTargetBands(in: predictionWindow)
            recentGlucose = try await recentFetch
            glucoseHistoryError = nil
        } catch {
            recentGlucose = []
            glucoseHistoryError = error.localizedDescription
        }

        prediction = predicted
        iob = loopDataManager.activeInsulin?.value
        cob = loopDataManager.activeCarbs?.quantity.doubleValue(for: .gram)
        lastLoopCompleted = loopDataManager.lastLoopCompleted
        // Closed loop is on but paused while the CGM session or a manual temp basal rules out automation.
        closedLoopPaused = settingsManager.dosingEnabled && deviceManager.closedLoopDisallowedLocalizedDescription != nil
        closedLoop = settingsManager.dosingEnabled && !closedLoopPaused
        targetRange = provider.glucoseTargetRange

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
        // Presets change Loop's plan; without a temp basal the pump still delivers its programmed profile.
        programmedBasalRate = settingsManager.settings.basalRateSchedule?.value(at: now)
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
            // Plugins wrap highlights onto two lines for the classic HUD ("Signal\nLoss").
            let message = highlight.localizedMessage.replacingOccurrences(of: "\n", with: " ")
            return Device(name: name, message: message, state: highlight.state, symbol: highlight.imageName)
        }
        if let progress, progress.progressState == .warning || progress.progressState == .critical {
            return Device(name: name, message: nil, state: progress.progressState == .critical ? .critical : .warning, endingSoon: true)
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
            Text(NSLocalizedString("Now", comment: "Title at the top of the Now screen, showing current glucose and Loop status"))
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
            .accessibilityHint(NSLocalizedString("Shows when Loop last ran", comment: "VoiceOver hint for the Loop status pill and the Loop notice on the Now screen"))
            Button(action: actions.pumpTapped) {
                if let pump = model.pump {
                    StatusPill(text: pillText(pump), dot: pillColor(pump))
                } else {
                    StatusPill(text: NSLocalizedString("Add pump", comment: "Status pill on the Now screen when no pump is set up; tapping it starts pump setup"), dot: P.statusCritical)
                }
            }
            .accessibilityHint(model.pump == nil
                ? NSLocalizedString("Sets up a pump", comment: "VoiceOver hint for the Add pump status pill on the Now screen")
                : NSLocalizedString("Opens pump settings", comment: "VoiceOver hint for the pump status pill and pump notice on the Now screen"))
            Button(action: actions.cgmTapped) {
                if let cgm = model.cgm {
                    StatusPill(text: pillText(cgm), dot: pillColor(cgm))
                } else {
                    StatusPill(text: NSLocalizedString("Add CGM", comment: "Status pill on the Now screen when no CGM is set up; tapping it starts CGM setup"), dot: P.statusCritical)
                }
            }
            .accessibilityHint(model.cgm == nil
                ? NSLocalizedString("Sets up a CGM", comment: "VoiceOver hint for the Add CGM status pill on the Now screen")
                : NSLocalizedString("Opens CGM settings", comment: "VoiceOver hint for the CGM status pill and CGM notice on the Now screen"))
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
                title: String(format: NSLocalizedString("Loop hasn't run for %1$@", comment: "Notice title on the Now screen when Loop hasn't completed recently. (1: duration since Loop last ran, e.g. 16m)"), LoopFormat.ago(last, now: model.now)),
                detail: NSLocalizedString("Insulin isn't being adjusted. Tap for details.", comment: "Notice detail on the Now screen when Loop hasn't completed recently"),
                hint: NSLocalizedString("Shows when Loop last ran", comment: "VoiceOver hint for the Loop status pill and the Loop notice on the Now screen"),
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
                detail: severity == .critical ? NSLocalizedString("Loop may not be giving insulin.", comment: "Notice detail on the Now screen under a critical pump problem reported by the pump") : nil,
                hint: NSLocalizedString("Opens pump settings", comment: "VoiceOver hint for the pump status pill and pump notice on the Now screen"),
                action: actions.pumpTapped))
        }
        if let cgm = model.cgm, let symbol = cgm.symbol, let message = cgm.message {
            let severity = DeviceNotice.Severity(cgm.state)
            items.append(DeviceNotice.Item(
                id: "cgm",
                severity: severity,
                symbol: symbol,
                title: message,
                detail: model.readingIsStale ? NSLocalizedString("Loop can't adjust insulin without readings.", comment: "Notice detail on the Now screen under a CGM problem when there is no recent glucose reading") : nil,
                hint: NSLocalizedString("Opens CGM settings", comment: "VoiceOver hint for the CGM status pill and CGM notice on the Now screen"),
                action: actions.cgmTapped))
        }
        return items.sorted { $0.severity > $1.severity }
    }

    private var loopText: String {
        guard let last = model.lastLoopCompleted else {
            if model.closedLoop {
                return NSLocalizedString("Closed loop · not run yet", comment: "Status pill on the Now screen: closed loop is on but Loop has never completed")
            } else if model.closedLoopPaused {
                return NSLocalizedString("Closed loop paused · not run yet", comment: "Status pill on the Now screen: closed loop is switched on but paused (e.g. no CGM data), and Loop has never completed")
            } else {
                return NSLocalizedString("Open loop · not run yet", comment: "Status pill on the Now screen: closed loop is off and Loop has never completed")
            }
        }
        let ago = LoopFormat.ago(last, now: model.now)
        if model.loopState == .failed {
            return String(format: NSLocalizedString("Loop failed · %1$@", comment: "Status pill on the Now screen: Loop hasn't completed for over 15 minutes. (1: duration since Loop last ran, e.g. 16m)"), ago)
        } else if model.closedLoop {
            return String(format: NSLocalizedString("Closed loop · %1$@", comment: "Status pill on the Now screen: closed loop is on and Loop last ran this long ago. (1: duration, e.g. 3m)"), ago)
        } else if model.closedLoopPaused {
            return String(format: NSLocalizedString("Closed loop paused · %1$@", comment: "Status pill on the Now screen: closed loop is switched on but paused (e.g. no CGM data), and Loop last ran this long ago. (1: duration, e.g. 3m)"), ago)
        } else {
            return String(format: NSLocalizedString("Open loop · %1$@", comment: "Status pill on the Now screen: closed loop is off (Loop recommends only) and Loop last ran this long ago. (1: duration, e.g. 3m)"), ago)
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

    /// A highlight (always a plugin message with a symbol) is spelled out in its notice, so its pill keeps to the device name.
    private func pillText(_ device: NowModel.Device) -> String {
        guard device.symbol == nil else { return device.name }
        if device.endingSoon {
            return String(format: NSLocalizedString("%1$@ · ending soon", comment: "Status pill on the Now screen when a pump pod or CGM sensor is near the end of its life. (1: device name from the pump or CGM plugin, e.g. Omnipod 5)"), device.name)
        }
        return device.name
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
                            Text(NSLocalizedString("No reading", comment: "Shown on the Now screen in place of the glucose value when there is no recent CGM reading"))
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
                        Text(String(format: NSLocalizedString("Target %1$@–%2$@", comment: "Glucose target range on the Now screen hero card. (1: lower bound; 2: upper bound)"), model.unit.format(target.lowerBound), model.unit.format(target.upperBound)))
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
                    ValueTile(label: NSLocalizedString("IOB", comment: "Abbreviation for insulin on board; label of a tile on the Now screen")) {
                        Text(model.iob.map(LoopFormat.doseUnits) ?? "–")
                            .font(LoopDesign.Typeface.statValueSmall)
                            .foregroundStyle(P.insulinInk)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(NSLocalizedString("Opens insulin delivery history", comment: "VoiceOver hint for the IOB tile on the Now screen"))
                Button(action: actions.showCarbs) {
                    ValueTile(label: NSLocalizedString("COB", comment: "Abbreviation for carbs on board; label of a tile on the Now screen")) {
                        Text(model.cob.map(LoopFormat.grams) ?? "–")
                            .font(LoopDesign.Typeface.statValueSmall)
                            .foregroundStyle(P.carbsInk)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(NSLocalizedString("Opens carb absorption", comment: "VoiceOver hint for the COB tile on the Now screen"))
                ValueTile(label: NSLocalizedString("Basal", comment: "Label of a tile showing the current basal rate (Now screen) or the day's basal insulin total (Today so far totals)")) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(model.basalRate.map { LoopFormat.number($0, decimals: 2) } ?? "–")
                                .font(LoopDesign.Typeface.statValueSmall)
                                .foregroundStyle(P.ink)
                            Text(NSLocalizedString("U/h", comment: "Abbreviation for insulin units per hour"))
                                .font(LoopDesign.Typeface.footnote)
                                .foregroundStyle(P.inkMuted)
                        }
                        if model.suspended {
                            Text(NSLocalizedString("Suspended", comment: "Shown in the Basal tile on the Now screen when insulin delivery is suspended"))
                                .font(LoopDesign.Typeface.footnote.weight(.semibold))
                                .foregroundStyle(P.criticalInk)
                        } else if let rate = model.basalRate, let scheduled = model.scheduledBasalRate {
                            Text(String(format: NSLocalizedString("%1$@ vs plan", comment: "Basal tile on the Now screen: how the current basal rate differs from the scheduled rate. (1: signed difference in U/h, e.g. +0.25)"), LoopFormat.signed(rate - scheduled)))
                                .font(LoopDesign.Typeface.footnote)
                                .foregroundStyle(P.inkMuted)
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
            return String(format: NSLocalizedString("Last reading %1$@ ago", comment: "Shown on the Now screen under No reading when the latest CGM reading is too old. (1: duration, e.g. 25m)"), LoopFormat.ago(reading.date, now: model.now))
        }
        guard let delta = reading.delta else { return model.unit.unitName }
        let change = model.unit.isMmol ? LoopFormat.signed(delta / GlucoseUnitStyle.mgdlPerMmol, decimals: 1) : LoopFormat.signed(delta, decimals: 0)
        return String(format: NSLocalizedString("%1$@ · %2$@ in 5 min", comment: "Under the glucose value on the Now screen: the glucose unit and how much glucose changed over 5 minutes. (1: glucose unit, e.g. mmol/L; 2: signed change, e.g. +0.3)"), model.unit.unitName, change)
    }

    /// Low and high get a pill with words; the number itself is never tinted.
    private var rangePill: (String, Color)? {
        guard let reading = model.reading, !model.readingIsStale else { return nil }
        if reading.mgdl < 54 { return (NSLocalizedString("Urgent low", comment: "Pill under the glucose value on the Now screen when glucose is below 54 mg/dL (3.0 mmol/L)"), P.statusCritical) }
        if reading.mgdl < 70 { return (NSLocalizedString("Low", comment: "Pill under the glucose value on the Now screen when glucose is below 70 mg/dL (3.9 mmol/L)"), P.statusCritical) }
        if reading.mgdl > 250 { return (NSLocalizedString("High", comment: "Pill under the glucose value on the Now screen when glucose is above 250 mg/dL (13.9 mmol/L)"), P.statusWarning) }
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
            actionButton(NSLocalizedString("Add carbs", comment: "Button on the Now screen that opens carb entry"), systemImage: "fork.knife", fill: P.carbs, text: P.onFill, action: actions.addCarbs)
                .disabled(!model.dosingAvailable)
                .opacity(model.dosingAvailable ? 1 : 0.4)
            actionButton(NSLocalizedString("Bolus", comment: "Button on the Now screen that opens the bolus screen"), systemImage: "syringe.fill", fill: P.insulin, text: P.onFill, action: actions.bolus)
                .disabled(!model.dosingAvailable)
                .opacity(model.dosingAvailable ? 1 : 0.4)
            // Pre-meal and the other presets share Loop's Presets screen.
            Button(action: actions.presets) {
                actionLabel(presetsTitle, systemImage: "slider.horizontal.3", fill: presetsFill, text: P.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Presets", comment: "Button on the Now screen that opens override presets (and pre-meal); also its VoiceOver label and menu item"))
            .accessibilityValue(presetsActive ? presetsTitle : "")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var presetsFill: Color {
        model.preMealOn || model.overrideName != nil ? P.accent.opacity(0.18) : P.surfaceSunken
    }

    private var presetsActive: Bool {
        model.preMealOn || model.overrideName != nil
    }

    private var presetsTitle: String {
        if model.preMealOn { return NSLocalizedString("Pre-meal on", comment: "Presets button title on the Now screen while the pre-meal target is on") }
        if let name = model.overrideName { return name }
        return NSLocalizedString("Presets", comment: "Button on the Now screen that opens override presets (and pre-meal); also its VoiceOver label and menu item")
    }

    private func actionButton(_ title: String, systemImage: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, systemImage: systemImage, fill: fill, text: text)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, systemImage: String, fill: Color, text: Color) -> some View {
        // Longer languages ("Agregar carbohidratos") wrap onto a second line rather than truncate.
        Text(title)
            .font(LoopDesign.Typeface.subhead.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .foregroundStyle(text)
            .padding(.horizontal, LoopDesign.Space.s1)
            .padding(.vertical, LoopDesign.Space.s1)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
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
                CardHeader(title: NSLocalizedString("Next 3 hours", comment: "Title of the prediction chart card on the Now screen")) {
                    // Loop's eventual glucose is the end of its prediction, which can run past the three hours drawn.
                    if let last = model.prediction.last {
                        Text(String(format: NSLocalizedString("Eventually %1$@ %2$@", comment: "Prediction card on the Now screen: Loop's eventual predicted glucose. (1: glucose value; 2: glucose unit, e.g. mmol/L)"), model.unit.format(last.mgdl), model.unit.unitName))
                    }
                }
                if readings.isEmpty && model.prediction.isEmpty {
                    ChartPlaceholder(message: model.glucoseHistoryError == nil
                                     ? NSLocalizedString("No CGM data in the last 3 hours", comment: "Empty prediction chart on the Now screen")
                                     : NSLocalizedString("Couldn't load recent CGM readings", comment: "Prediction chart on the Now screen when recent glucose couldn't be read"))
                } else {
                    PredictionChartView(readings: readings, prediction: model.prediction, unit: model.unit,
                                        targetBands: model.predictionTargets, now: model.now)
                }
                ChartLegend(items: [
                    LegendItem(swatch: .dot(P.glucose), label: NSLocalizedString("Readings", comment: "Chart legend on the Now screen: dots are CGM glucose readings")),
                    LegendItem(swatch: .dash(P.glucose), label: NSLocalizedString("Loop prediction", comment: "Chart legend on the Now screen: dashed line is Loop's predicted glucose")),
                ])
                if let error = model.glucoseHistoryError {
                    Text(String(format: NSLocalizedString("Recent readings unavailable: %1$@", comment: "Error under the prediction chart on the Now screen. (1: system error description)"), error))
                        .font(LoopDesign.Typeface.footnote)
                        .foregroundStyle(P.criticalInk)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(NSLocalizedString("Opens Loop's prediction breakdown", comment: "VoiceOver hint for the prediction card on the Now screen"))
    }

    private var todayCard: some View {
        Button(action: actions.showToday) {
            if let error = model.historyError {
                LoopCard {
                    CardHeader(title: DayTimelineCard.todayTitle)
                    ChartPlaceholder(message: String(format: NSLocalizedString("Couldn't load today's history: %1$@", comment: "Shown on the Now screen's Today so far card when history couldn't be read. (1: system error description)"), error))
                }
            } else {
                DayTimelineCard(title: DayTimelineCard.todayTitle, history: model.today, unit: model.unit, targetBands: model.todayTargets,
                                now: model.now, height: 230)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(NSLocalizedString("Opens the full day", comment: "VoiceOver hint for the Today so far card on the Now screen"))
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
