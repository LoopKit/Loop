//
//  WatchLoopManager.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  The wrist's Loop during a loan: the host of the loop cycle both apps run (`LoopCycle`), and
//  DeviceDataManager's part over the lent pod. Main-actor, as the phone's `LoopDataManager`; cycle
//  work runs one operation at a time on its lane (`onLane`).
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchConnectivity
import WatchKit
import os.log

@MainActor
final class WatchLoopManager {
    /// The WATCH's own stores, opened by `StockLoopStack` — not a view onto the phone's.
    let doseStore: DoseStore
    let glucoseStore: GlucoseStore
    let carbStore: CarbStore

    /// Stock's dosing decisions, kept by the watch while it holds the pod; nil in suites that
    /// do not look at them.
    let dosingDecisionStore: DosingDecisionStore?

    /// Stock's alert history, recorded while the watch holds the pod; nil in suites that do not
    /// look at it.
    let alertStore: AlertStore?

    /// Stock's device log, written while the watch holds the pod; nil in suites that do not look
    /// at it.
    let deviceLog: PersistentDeviceLog?

    /// Stock `AlertManager` awaits each record before the next; the wrist's alert calls are
    /// synchronous, so their records are chained in call order.
    var alertRecords: Task<Void, Never>?

    let settingsProvider: WatchSettingsProvider

    /// The stack's only override history; a second instance would dose unscaled.
    let overrideHistory: TemporaryScheduleOverrideHistory

    /// `settings.maximumBolus`, for the bolus picker.
    var grantedMaximumBolus: Double? { settings.maximumBolus }

    /// Replaced wholesale at grant; the didSet keeps the provider in step.
    var settings: LoopSettings {
        didSet {
            settingsProvider.update(with: settings)
        }
    }

    private var _scheduleOverride: TemporaryScheduleOverride? {
        didSet { onScheduleOverrideChanged?() }
    }

    /// Fired when the active override changes: during a loan the screens show this one.
    var onScheduleOverrideChanged: (() -> Void)?

    /// Records into `overrideHistory`, which is what reaches the algorithm.
    var scheduleOverride: TemporaryScheduleOverride? {
        get { _scheduleOverride }
        set {
            let oldValue = _scheduleOverride
            guard newValue != oldValue else { return }
            _scheduleOverride = newValue
            overrideHistory.recordOverride(newValue)

            if let o = newValue {
                let target = o.settings.targetRange.map {
                    String(format: "%.0f-%.0f mg/dL", $0.lowerBound.doubleValue(for: .milligramsPerDeciliter),
                           $0.upperBound.doubleValue(for: .milligramsPerDeciliter))
                } ?? "unchanged"
                SportLog.event("override", String(format: "override %@ in effect: insulin needs %.0f%%, target %@, ends %@",
                                                  o.context.presetNameForLog,
                                                  o.settings.effectiveInsulinNeedsScaleFactor * 100,
                                                  target,
                                                  o.duration.isInfinite ? "never" : ISO8601DateFormatter().string(from: o.scheduledInterval.end)))
            } else if oldValue != nil {
                SportLog.event("override", "override ended; schedules apply unscaled")
            }

            // As stock: an override change refreshes the display run.
            updateDisplayStateForChange()
        }
    }

    /// Copy of stock `LoopDataManager.insulinModel(for:)`; the default arm reads the rapid-acting model directly.
    func insulinModel(for type: InsulinType?) -> InsulinModel {
        switch type {
        case .fiasp: return ExponentialInsulinModelPreset.fiasp
        case .lyumjev: return ExponentialInsulinModelPreset.lyumjev
        case .afrezza: return ExponentialInsulinModelPreset.afrezza
        default: return settings.defaultRapidActingModel ?? ExponentialInsulinModelPreset.rapidActingAdult
        }
    }

    /// The loaned pod, or nil. This IS the loan flag for the loop's purposes: every path that
    /// asks "do we hold the pod?" asks it here, and it is set at takeover and cleared at teardown.
    var pumpManager: PumpManager? {
        didSet {
            // As stock `DeviceDataManager.setupPump`.
            doseStore.device = pumpManager?.status.device
            // The screens stop showing this watch's state with the pod.
            if pumpManager == nil {
                ExtensionDelegate.sharedIfAvailable()?.loopManager.wristState = nil
            }
        }
    }

    /// The dosing loop both apps run (`LoopCycle.swift`); this manager is its host on the watch.
    private(set) lazy var cycle = LoopCycle(doseStore: doseStore, carbStore: carbStore, glucoseStore: glucoseStore,
                                            dosingDecisionStore: dosingDecisionStore, settingsProvider: settingsProvider,
                                            host: self, now: { [weak self] in self?.now() ?? Date() })

    /// Fired by `loop()` only on a cycle that LANDED, which is what renews the phone's hold. A
    /// cycle that computed but could not reach the pod must not renew it.
    var onCycleLanded: (() -> Void)?

    /// Fired when the wrist opens the loop (closed to open), where stock ends a pre-meal preset.
    var onLoopOpened: (() -> Void)?

    /// The manual bolus being sent, stamped at confirm, so the glance can narrate the wait for the pod.
    private var manualBolusInFlight: (startedAt: Date, units: Double?)?

    var manualBolusStartedAt: Date? { manualBolusInFlight?.startedAt }

    /// Gone with the wait, so the amount does not linger on screen after the dose has been accepted
    /// or refused.
    var manualBolusPendingUnits: Double? { manualBolusInFlight?.units }

    func setManualBolusInFlight(_ inFlight: Bool, units: Double? = nil) {
        manualBolusInFlight = inFlight ? (startedAt: now(), units: units) : nil
    }

    private var bolusDelivery: (units: Double, reporter: DoseProgressReporter)?

    /// The pump manager's progress reporter for the bolus the pod is delivering; nil once it
    /// reports complete, never "delivered".
    var manualBolusDelivery: (units: Double, reporter: DoseProgressReporter)? {
        guard let d = bolusDelivery, !d.reporter.progress.isComplete else { return nil }
        return d
    }

    /// As stock's status screen does: a new bolus in progress gets a fresh reporter from the pump
    /// manager.
    func bolusStateDidChange(to bolusState: PumpManagerStatus.BolusState, from oldState: PumpManagerStatus.BolusState, pumpManager: PumpManager) {
        guard case .inProgress(let dose) = bolusState else { return }
        if case .inProgress(let previous) = oldState, previous.syncIdentifier == dose.syncIdentifier { return }
        let reporter = pumpManager.createBolusProgressReporter(reportingOn: .main)
        bolusDelivery = reporter.map { (units: dose.programmedUnits, reporter: $0) }
        NotificationCenter.default.post(name: .manualBolusStateDidChange, object: nil)
    }

    /// The wrist's loop switch as last set: what a hand-back carries and what the pod is told.
    private(set) var closedLoopEnabled = false

    /// The only gate on automatic dosing here; not combined with the phone's `dosingEnabled`. The
    /// switch as cycle work sees it: a change applies on the lane, after any cycle already running.
    private(set) var appliedClosedLoopEnabled = false

    /// Saves one change to the persisted loop state; the whole value is written at once.
    func updateLoopState(_ change: (inout WatchLoopState) -> Void) {
        change(&loopState)
        loopStateStore.wrappedValue = loopState.rawValue
    }
    /// Per session, so the next grant's mode is not mistaken for a transition.
    func resetClosedLoopForSessionEnd() {
        updateLoopState { $0.closedLoopEnabled = false }
        closedLoopEnabled = false
        onLane {
            self.appliedClosedLoopEnabled = false
        }
    }

    /// Set at once, so an immediate hand-back carries the new value. Opening the loop cancels an
    /// automatic temp, as stock, only on a real closed-to-open transition.
    func setClosedLoopEnabled(_ enabled: Bool, reason: String = "by the user") {
        updateLoopState { $0.closedLoopEnabled = enabled }

        let wasEnabled = closedLoopEnabled
        closedLoopEnabled = enabled

        // As stock: opening the loop ends a pre-meal preset, before the temp is cancelled.
        if wasEnabled, !enabled { onLoopOpened?() }

        onLane {
            self.appliedClosedLoopEnabled = enabled
            SportLog.event("loop", enabled ? "loop closed \(reason)" : "loop opened \(reason); no automatic dosing")

            await self.publishHUDContext()

            // As stock: a change of loop mode refreshes the display run.
            if wasEnabled != enabled { self.updateDisplayStateForChange() }

            guard wasEnabled, !enabled else { return }
            await self.cancelActiveTempBasal(reason: .automaticDosingDisabled)
        }
    }

    /// Applied locally first; telling the phone is best-effort.
    func applyWristOverride(_ override: TemporaryScheduleOverride?) {
        scheduleOverride = override
    }

    /// Replaces this watch's override history with the phone's, each at its own start, as stock
    /// loads its history at launch. The active one becomes `scheduleOverride`.
    func adoptOverrideHistory(_ overrides: [TemporaryScheduleOverride]) {
        overrideHistory.recentEvents = []
        for override in overrides.sorted(by: { $0.startDate < $1.startDate }) {
            overrideHistory.recordOverride(override, at: override.startDate)
        }
        _scheduleOverride = overrideHistory.activeOverride(at: now())
        temporaryScheduleOverrideHistoryDidUpdate(overrideHistory)
    }

    /// On a resume: the history saved before the relaunch, and the override active in it.
    func restoreOverrideHistory() {
        guard let data = loopState.overrideEvents,
              let events = try? PropertyListDecoder().decode([OverrideEvent].self, from: data) else { return }
        overrideHistory.recentEvents = events
        _scheduleOverride = overrideHistory.activeOverride(at: now())
    }

    /// Eventual glucose split by effect. Diagnostic only; see `updatePredictionBreakdown`.
    struct PredictionBreakdown {
        /// The latest STORED glucose, which is the row's left-hand side rather than the
        /// prediction's own starting point.
        let startMgdl: Double

        let eventualMgdl: Double
        let insulinMgdl: Double
        let carbMgdl: Double
        let momentumMgdl: Double
        let retrospectiveMgdl: Double

        /// Whole mg/dL for display. The last line folds -0 into 0: a row of small effects
        /// otherwise renders "-0" beside "+0" and reads as a sign error.
        static func round0(_ v: Double) -> Double {
            guard v.isFinite else { return 0 }
            let x = v.rounded()
            return x == 0 ? 0 : x
        }
    }

    /// The immutable snapshot the glance reads, published as `glanceData`; nothing in it is
    /// recomputed by the reader.
    struct GlanceData {
        let glucose: LoopQuantity?
        let glucoseDate: Date?

        /// When each source last delivered. The provenance line is derived from the pair, so a fresh
        /// reading with a stale `directG7At` is the interesting case.
        let directG7At: Date?
        let phoneRelayAt: Date?
        let trend: GlucoseTrend?
        /// The display run's (stock's `displayState`), as is `iob`; the glance shows these.
        let eventual: LoopQuantity?
        let iob: Double?

        /// The automatic loop's last run; the diagnostics page shows these.
        let dosingEventual: LoopQuantity?
        let dosingIOB: Double?
        let dosingCOB: Double?

        let tempRate: Double?
        let lastLoopCompleted: Date?
        let suspendThreshold: LoopQuantity?
        let closedLoopEnabled: Bool

        let recommendedTempRate: Double?
        let lastLoopErrorText: String?

        let predictionBreakdown: PredictionBreakdown?

        let retrospectiveCorrectionIsIntegral: Bool
        let retrospectiveDiscrepancyCount: Int

        let overrideLabel: String?
        var overrideSymbol: String? = nil
    }

    /// The glance's snapshot, rebuilt on the lane after the cycle work before it (`refreshGlanceData`).
    var glanceData: GlanceData?
    var glanceRefreshPending = false

    /// Posted after every rebuild. An observer must redraw from `glanceData` and must NOT ask for
    /// another rebuild — see `refreshGlanceData` for why that does not coalesce.
    static let glanceDataDidUpdate = Notification.Name("com.loopkit.Loop.glanceDataDidUpdate")

    /// The lane's last operation; see `onLane`.
    private var laneTail: Task<Void, Never>?

    /// Cycle work, one operation at a time in call order: each waits for the one before, through its
    /// awaits on the stores and the pod. The phone's operations interleave at their awaits; the watch
    /// keeps the order it has been tested with. In call order, so a grant's settings land before the
    /// loan's first prediction.
    func onLane(_ work: @escaping @MainActor () async -> Void) {
        let previous = laneTail
        laneTail = Task {
            await previous?.value
            await work()
        }
    }

    /// Returns once the lane has run everything asked of it, including work asked for meanwhile.
    func laneSettled() async {
        while let tail = laneTail {
            await tail.value
            if laneTail == tail { return }
        }
    }

    let log = OSLog(category: "WatchLoopManager")

    /// Clock and defaults are injectable so the suite can drive a cycle without waiting on either.
    var now: () -> Date = { Date() }

    var defaults: UserDefaults = .standard

    /// Where state files live; nil in the app (Documents).
    let stateDirectory: URL?

    /// Loop mode, correction model and last cycle, persisted as one value; a relaunch mid-loan
    /// must not come back open with a grey ring.
    var loopStateStore: PersistedProperty<[String: Any]>
    private(set) var loopState: WatchLoopState

    /// Restores the last cycle, loop mode and correction model, and subscribes to phone context
    /// (except in the simulator, which has its own ingest).
    init(doseStore: DoseStore, glucoseStore: GlucoseStore, carbStore: CarbStore,
         overrideHistory: TemporaryScheduleOverrideHistory = TemporaryScheduleOverrideHistory(),
         dosingDecisionStore: DosingDecisionStore? = nil,
         alertStore: AlertStore? = nil,
         deviceLog: PersistentDeviceLog? = nil,
         settings: LoopSettings = LoopSettings(),
         defaults: UserDefaults = .standard, stateDirectory: URL? = nil) {
        self.defaults = defaults
        self.stateDirectory = stateDirectory
        let stateStore = stateDirectory.map { PersistedProperty<[String: Any]>(key: "WatchLoopState", directory: $0) }
            ?? PersistedProperty(key: "WatchLoopState")
        let loopState = stateStore.wrappedValue.flatMap(WatchLoopState.init(rawValue:)) ?? WatchLoopState()
        self.loopStateStore = stateStore
        self.loopState = loopState
        self.doseStore = doseStore
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.dosingDecisionStore = dosingDecisionStore
        self.alertStore = alertStore
        self.deviceLog = deviceLog
        self.settingsProvider = WatchSettingsProvider(settings: settings)
        self.overrideHistory = overrideHistory
        self.settings = settings
        self.lastLoopCompleted = loopState.lastLoopCompleted
        self.closedLoopEnabled = loopState.closedLoopEnabled
        self.appliedClosedLoopEnabled = loopState.closedLoopEnabled
        self.integralRetrospectiveCorrectionEnabled = loopState.integralRetrospectiveCorrectionEnabled
        self.glucoseBasedApplicationFactorEnabled = loopState.glucoseBasedApplicationFactorEnabled
        self.guardAndRunwayEnabled = loopState.guardAndRunwayEnabled
        self.volatilityBaseline = loopState.volatilityBaseline

        // The store asks us for the scheduled basal it nets doses against; see the
        // `DoseStoreDelegate` conformance.
        doseStore.delegate = self
        overrideHistory.delegate = self

        // As stock: required for the device status in stored dosing decisions.
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true

        // Stock `LoopDataManager`'s observers: a change in any of its stores refreshes the display run.
        let storeChanges: [(Notification.Name, AnyObject)] = [
            (CarbStore.carbEntriesDidChange, carbStore),
            (GlucoseStore.glucoseSamplesDidChange, glucoseStore),
            (DoseStore.valuesDidChange, doseStore),
        ]
        for (name, store) in storeChanges {
            NotificationCenter.default.addObserver(forName: name, object: store, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.updateDisplayStateForChange() }
            }
        }
    }

    private var lastDirectG7At: Date?
    private var lastPhoneRelayAt: Date?

    // MARK: - Glucose sources

    /// The watch's CGM, which stock's `WatchCGMHost` builds and owns; held here for the dosing records.
    private(set) var cgmManager: CGMManager?

    /// `WatchCGMHost`'s manager, on each of its readings and when the stack starts. A new manager
    /// seeds the stranded-sensor clock from its last link, so a relaunch does not reset it.
    func noteCGMManager(_ manager: CGMManager?) {
        let changed = manager !== cgmManager
        cgmManager = manager
        if changed { seedLastDirectG7At(manager?.cgmManagerStatus.lastCommunicationDate) }
    }

    /// Launch seed, so a relaunch does not reset the stranded-sensor clock; never moves it back.
    func seedLastDirectG7At(_ date: Date?) {
        if let date, date > (lastDirectG7At ?? .distantPast) { lastDirectG7At = date }
    }

    /// Record WHERE a reading came from, so the wrist can answer "am I standing on my own right
    /// now?". Stamped on arrival by the ingest paths — see `processCGMReadingResult`.
    func noteGlucoseSource(directG7: Bool) {
        if directG7 { lastDirectG7At = self.now() } else { lastPhoneRelayAt = self.now() }

        refreshGlanceData()
    }

    /// A phone relay says nothing about the watch's radio, so the two are kept apart.
    var lastGlucoseSourceStamps: (direct: Date?, phone: Date?) {
        (lastDirectG7At, lastPhoneRelayAt)
    }

    /// The basal schedule with the override applied; net rates must use this, not the raw schedule.
    var basalRateScheduleApplyingOverrideHistory: BasalRateSchedule? {
        settings.basalRateSchedule.map { overrideHistory.resolvingRecentBasalSchedule($0) }
    }

    /// The phone's Algorithm Experiments. Applied on the lane, ahead of the first prediction.
    func setAlgorithmExperiments(integralRetrospectiveCorrection: Bool, glucoseBasedApplicationFactor: Bool,
                                 guardAndRunway: Bool, volatilityBaseline: Double?) {
        updateLoopState {
            $0.integralRetrospectiveCorrectionEnabled = integralRetrospectiveCorrection
            $0.glucoseBasedApplicationFactorEnabled = glucoseBasedApplicationFactor
            $0.guardAndRunwayEnabled = guardAndRunway
            $0.volatilityBaseline = volatilityBaseline
        }
        onLane {
            self.integralRetrospectiveCorrectionEnabled = integralRetrospectiveCorrection
            self.glucoseBasedApplicationFactorEnabled = glucoseBasedApplicationFactor
            self.guardAndRunwayEnabled = guardAndRunway
            self.volatilityBaseline = volatilityBaseline
        }
    }

    /// As applied on the lane.
    var integralRetrospectiveCorrectionEnabled = false
    var glucoseBasedApplicationFactorEnabled = false
    var guardAndRunwayEnabled = false
    var volatilityBaseline: Double?

    /// Stock glucose alerts, built from the phone's settings for a loan; nil between loans.
    var glucoseAlerts: GlucoseAlertManager?

    // MARK: - Algorithm runs
    // Stock runs the algorithm three ways, each fed differently, and only the display run is
    // kept for screens. Each run's result is stored under its own name so no run can overwrite
    // another's values; the manual-bolus run stores nothing. Written by cycle work on the lane.

    /// Stock's `displayState`: the display run (`updateDisplayState`). The glance's IOB, eventual
    /// and COB, the stock pages' context and the complication read it; nothing doses from it.
    var displayState = AlgorithmDisplayState()

    /// The automatic loop's last run (input and output). Stock keeps this run local to `loop()`;
    /// the watch keeps it for the diagnostics page, the prediction breakdown and `[predict]`.
    var loopRunState = AlgorithmDisplayState()

    var lastPredictionBreakdown: PredictionBreakdown?

    /// The last cycle's recommendation, for the glance; cleared when a cycle starts, so a cycle
    /// whose compute failed shows none rather than the one before.
    var lastRecommendation: AutomaticDoseRecommendation?

    /// When a cycle last completed — the freshness ring's only input. Persisted on every write:
    /// a relaunch mid-loan that came back with no value opened the ring grey for a cycle.
    var lastLoopCompleted: Date? {
        didSet { updateLoopState { $0.lastLoopCompleted = lastLoopCompleted } }
    }

    /// Adopts the phone's completion time at grant; only ever moves forward.
    func seedLastLoopCompleted(_ date: Date, source: String) {
        guard (lastLoopCompleted ?? .distantPast) < date else { return }
        lastLoopCompleted = date
        SportLog.event("loop", String(format: "last loop completion taken from %@, %.0f s ago", source, self.now().timeIntervalSince(date)))
    }
    /// Last cycle's outcome, for display and the debug row. Cleared at the start of each cycle,
    /// so nil means "the cycle in progress has not failed yet", not "all is well".
    var lastLoopError: Error?

    /// Shared by BOTH glucose sources, so the 4.2-minute gate applies across them: a direct
    /// reading and the phone's relay of the same reading must not each fire a cycle.
    private var lastCGMLoopTrigger: Date = .distantPast

    /// Stock's 4.2-minute gate, checked and claimed in one step: true means this caller runs the cycle.
    func claimCGMLoopTrigger(at now: Date) -> Bool {
        guard now.timeIntervalSince(lastCGMLoopTrigger) > .minutes(4.2) else { return false }
        lastCGMLoopTrigger = now
        return true
    }

    /// Stock's `DoseEnactor`, unchanged. A `var` so tests can observe it.
    var doseEnactor = DoseEnactor()

    /// Say "idle, no pod" once per idle stretch instead of once per reading.
    var loggedIdleNoPump = false

    /// Stock's `WatchDataManager.contextDosingDecisions`: the watchBolus decision built with each
    /// recommendation the wrist was shown, by the carb entry it assumed; kept five minutes.
    var contextDosingDecisions: [(date: Date, potentialCarbEntry: NewCarbEntry?, decision: BolusDosingDecision)] = []

    /// The pod command for a manual bolus, as stock `DeviceDataManager.enactBolus` sends it; a
    /// `var` so the suite can see the decision id it carries.
    var enactBolusCommand: (PumpManager, _ decisionId: UUID?, _ units: Double, BolusActivationType,
                            @escaping (PumpManagerError?) -> Void) -> Void = { pumpManager, decisionId, units, activationType, completion in
        pumpManager.enactBolus(decisionId: decisionId, units: units, activationType: activationType, completion: completion)
    }

    /// Stock's cancel of an automatic bolus before a manual one; a `var` so the suite can see it.
    var cancelBolusCommand: (PumpManager) async -> Void = { pumpManager in
        let _ = try? await pumpManager.cancelBolus()
    }

}

/// Log-only naming for an override's preset, so an override line says which preset it was
/// rather than printing an enum case.
extension TemporaryScheduleOverride.Context {
    var presetNameForLog: String {
        switch self {
        case .preMeal: return "pre-meal"
        case .preset(let preset):
            return [preset.symbol?.textGlyph, preset.name].compactMap { $0 }.joined(separator: " ")
        case .activity(let preset):
            return [preset.activityType.symbol.textGlyph, preset.activityType.name].compactMap { $0 }.joined(separator: " ")
        case .custom: return "custom"
        }
    }
}

private extension PresetSymbol {
    /// Emoji only. A non-emoji symbol's raw value is an asset or system-image name, which would
    /// land in the log as a meaningless token rather than a glyph.
    var textGlyph: String? { symbolType == .emoji ? value : nil }
}

extension WatchLoopManager: TemporaryScheduleOverrideHistoryDelegate {
    /// Saved on every change, so a relaunch mid-loan doses under the same overrides.
    func temporaryScheduleOverrideHistoryDidUpdate(_ history: TemporaryScheduleOverrideHistory) {
        let events = try? PropertyListEncoder().encode(history.recentEvents)
        updateLoopState { $0.overrideEvents = events }
    }
}

/// The loop manager's persisted state, saved and restored as one value.
struct WatchLoopState: RawRepresentable {
    var closedLoopEnabled = false
    var integralRetrospectiveCorrectionEnabled = false
    var glucoseBasedApplicationFactorEnabled = false
    var guardAndRunwayEnabled = false
    var volatilityBaseline: Double?
    var lastLoopCompleted: Date?
    /// The override history's events, as LoopKit encodes them; read back only by a resume.
    var overrideEvents: Data?

    init() {}

    init?(rawValue: [String: Any]) {
        closedLoopEnabled = rawValue["closedLoopEnabled"] as? Bool ?? false
        integralRetrospectiveCorrectionEnabled = rawValue["integralRetrospectiveCorrectionEnabled"] as? Bool ?? false
        glucoseBasedApplicationFactorEnabled = rawValue["glucoseBasedApplicationFactorEnabled"] as? Bool ?? false
        guardAndRunwayEnabled = rawValue["guardAndRunwayEnabled"] as? Bool ?? false
        volatilityBaseline = rawValue["volatilityBaseline"] as? Double
        lastLoopCompleted = rawValue["lastLoopCompleted"] as? Date
        overrideEvents = rawValue["overrideEvents"] as? Data
    }

    var rawValue: [String: Any] {
        var raw: [String: Any] = ["closedLoopEnabled": closedLoopEnabled,
                                  "integralRetrospectiveCorrectionEnabled": integralRetrospectiveCorrectionEnabled,
                                  "glucoseBasedApplicationFactorEnabled": glucoseBasedApplicationFactorEnabled,
                                  "guardAndRunwayEnabled": guardAndRunwayEnabled]
        raw["volatilityBaseline"] = volatilityBaseline
        raw["lastLoopCompleted"] = lastLoopCompleted
        raw["overrideEvents"] = overrideEvents
        return raw
    }
}
