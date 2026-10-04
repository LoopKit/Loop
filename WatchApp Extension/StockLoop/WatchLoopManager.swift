//
//  WatchLoopManager.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  The wrist's Loop during a loan: LoopDataManager and DeviceDataManager in one. `dataAccessQueue`
//  owns the cycle's state and main never syncs onto it; main-readable values are lock-mirrored.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import WatchConnectivity
import WatchKit
import os.log

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
    let alertRecordsLock = NSLock()

    let settingsProvider: WatchSettingsProvider

    /// The stack's only override history; a second instance would dose unscaled.
    let overrideHistory: TemporaryScheduleOverrideHistory

    private let grantedMaximumBolusLock = NSLock()
    private var _grantedMaximumBolus: Double?

    /// `settings.maximumBolus`, readable from main for the bolus picker.
    var grantedMaximumBolus: Double? {
        grantedMaximumBolusLock.lock()
        defer { grantedMaximumBolusLock.unlock() }
        return _grantedMaximumBolus
    }

    /// Replaced wholesale at grant; the didSet keeps the mirror and provider in step.
    var settings: LoopSettings {
        didSet {
            grantedMaximumBolusLock.lock()
            _grantedMaximumBolus = settings.maximumBolus
            grantedMaximumBolusLock.unlock()

            settingsProvider.update(with: settings)

        }
    }

    private var _scheduleOverride: TemporaryScheduleOverride?

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
                    String(format: "%.0f-%.0f", $0.lowerBound.doubleValue(for: .milligramsPerDeciliter),
                           $0.upperBound.doubleValue(for: .milligramsPerDeciliter))
                } ?? "unchanged"
                SportLog.event("override", String(format: "APPLIED %@ · insulin needs %.0f%% (basal x%.2f, ISF x%.2f, CR x%.2f) · target %@ · ends %@",
                                                  o.context.presetNameForLog,
                                                  o.settings.effectiveInsulinNeedsScaleFactor * 100,
                                                  o.settings.basalRateMultiplier ?? 1.0,
                                                  o.settings.insulinSensitivityMultiplier ?? 1.0,
                                                  o.settings.carbRatioMultiplier ?? 1.0,
                                                  target,
                                                  o.duration.isInfinite ? "indefinite" : ISO8601DateFormatter().string(from: o.scheduledInterval.end)))
            } else if oldValue != nil {
                SportLog.event("override", "CLEARED — schedules resolve unscaled again")
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
        // As stock `DeviceDataManager.setupPump`.
        didSet { doseStore.device = pumpManager?.status.device }
    }

    /// Fired by `loop()` only on a cycle that LANDED, which is what renews the phone's hold. A
    /// cycle that computed but could not reach the pod must not renew it.
    var onCycleLanded: (() -> Void)?

    /// Fired when the wrist opens the loop (closed to open), where stock ends a pre-meal preset.
    var onLoopOpened: (() -> Void)?

    // Glucose that arrives mid-rebuild runs the cycle once the pump manager is back.
    let awaitedPumpLock = NSLock()
    var awaitingPumpManager = false
    var readingArrivedWithoutPump = false

    func beginAwaitingPumpManager() {
        awaitedPumpLock.lock(); awaitingPumpManager = true; readingArrivedWithoutPump = false; awaitedPumpLock.unlock()
    }

    /// Consumes the flag: it answers true ONCE, so two callers cannot each run a catch-up cycle.
    func endAwaitingPumpManager() -> Bool {
        awaitedPumpLock.lock(); defer { awaitedPumpLock.unlock() }
        let waited = readingArrivedWithoutPump
        awaitingPumpManager = false
        readingArrivedWithoutPump = false
        return waited
    }
    /// Shared by the CGM and the pump managers, which log from several queues at once during a
    /// radio storm — the throttle has to be thread-safe on its own account.
    let deviceLogThrottle = DeviceLogThrottle()

    // Manual-bolus UI state. All of it is read from MAIN while the dose is in flight — which is
    // precisely when `dataAccessQueue` is busy — so it lives behind its own lock.
    private let manualBolusLock = NSLock()
    private var _manualBolusInFlight = false

    /// Stamped at confirm, so the glance can narrate the wait for the pod.
    var manualBolusStartedAt: Date? {
        manualBolusLock.lock(); defer { manualBolusLock.unlock() }
        return _manualBolusInFlight ? _manualBolusStartedAt : nil
    }
    private var _manualBolusStartedAt: Date?

    private var _manualBolusPendingUnits: Double?
    /// Gated on the in-flight flag, so the amount vanishes with the wait rather than lingering on
    /// screen after the dose has been accepted or refused.
    var manualBolusPendingUnits: Double? {
        manualBolusLock.lock(); defer { manualBolusLock.unlock() }
        return _manualBolusInFlight ? _manualBolusPendingUnits : nil
    }
    func setManualBolusInFlight(_ inFlight: Bool, units: Double? = nil) {
        manualBolusLock.lock()
        _manualBolusInFlight = inFlight
        _manualBolusStartedAt = inFlight ? self.now() : nil
        _manualBolusPendingUnits = inFlight ? units : nil
        manualBolusLock.unlock()
    }

    private var _bolusDelivery: (units: Double, reporter: DoseProgressReporter)?

    /// The pump manager's progress reporter for the bolus the pod is delivering; nil once it
    /// reports complete, never "delivered".
    var manualBolusDelivery: (units: Double, reporter: DoseProgressReporter)? {
        manualBolusLock.lock(); defer { manualBolusLock.unlock() }
        guard let d = _bolusDelivery, !d.reporter.progress.isComplete else { return nil }
        return d
    }

    /// As stock's status screen does: a new bolus in progress gets a fresh reporter from the pump
    /// manager. Posts on MAIN, since the observer mutates published UI state.
    func bolusStateDidChange(to bolusState: PumpManagerStatus.BolusState, from oldState: PumpManagerStatus.BolusState, pumpManager: PumpManager) {
        guard case .inProgress(let dose) = bolusState else { return }
        if case .inProgress(let previous) = oldState, previous.syncIdentifier == dose.syncIdentifier { return }
        let reporter = pumpManager.createBolusProgressReporter(reportingOn: .main)

        manualBolusLock.lock()
        _bolusDelivery = reporter.map { (units: dose.programmedUnits, reporter: $0) }
        manualBolusLock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .manualBolusStateDidChange, object: nil)
        }
    }

    /// The only gate on automatic dosing here; not combined with the phone's `dosingEnabled`.
    /// Queue-owned; `closedLoopEnabledNonBlocking` reads it from elsewhere.
    var _closedLoopEnabled = false

    private let closedLoopMirrorLock = NSLock()
    private var _closedLoopMirror = false
    /// No queue hop; safe from the loan controller's queue.
    var closedLoopEnabledNonBlocking: Bool {
        closedLoopMirrorLock.lock()
        defer { closedLoopMirrorLock.unlock() }
        return _closedLoopMirror
    }

    /// Saves one change to the persisted loop state; the whole value is written at once.
    func updateLoopState(_ change: (inout WatchLoopState) -> Void) {
        loopStateLock.lock()
        defer { loopStateLock.unlock() }
        change(&loopState)
        loopStateStore.wrappedValue = loopState.rawValue
    }
    /// Per session, so the next grant's mode is not mistaken for a transition.
    func resetClosedLoopForSessionEnd() {
        updateLoopState { $0.closedLoopEnabled = false }
        closedLoopMirrorLock.lock()
        _closedLoopMirror = false
        closedLoopMirrorLock.unlock()
        dataAccessQueue.async {
            self._closedLoopEnabled = false
        }
    }

    /// Mirror written synchronously so an immediate hand-back carries the new value. Opening the
    /// loop cancels an automatic temp, as stock, only on a real closed-to-open transition.
    func setClosedLoopEnabled(_ enabled: Bool, reason: String = "by user") {
        updateLoopState { $0.closedLoopEnabled = enabled }

        closedLoopMirrorLock.lock()
        let wasEnabled = _closedLoopMirror
        _closedLoopMirror = enabled
        closedLoopMirrorLock.unlock()

        // As stock: opening the loop ends a pre-meal preset, before the temp is cancelled.
        if wasEnabled, !enabled { onLoopOpened?() }

        dataAccessQueue.async {
            self._closedLoopEnabled = enabled
            SportLog.event("loop", enabled ? "CLOSED \(reason) — the watch will adjust basal" : "OPENED \(reason) — advisory only, no dosing")

            self.publishHUDContext()

            // As stock: a change of loop mode refreshes the display run.
            if wasEnabled != enabled { self.updateDisplayStateForChange() }

            guard wasEnabled, !enabled else { return }
            self.cancelActiveTempBasalOnQueue(reason: "automaticDosingDisabled")
        }
    }

    /// Applied locally first; telling the phone is best-effort.
    func applyWristOverride(_ override: TemporaryScheduleOverride?) {
        if let o = override {
            let target = o.settings.targetRange.map {
                String(format: "%.0f-%.0f", $0.lowerBound.doubleValue(for: .milligramsPerDeciliter),
                       $0.upperBound.doubleValue(for: .milligramsPerDeciliter))
            } ?? "unchanged"
            SportLog.event("override", String(format: "SET-ON-WRIST %@ · insulin needs %.0f%% · target %@ · ends %@ · sync %@",
                                              o.context.presetNameForLog,
                                              o.settings.effectiveInsulinNeedsScaleFactor * 100,
                                              target,
                                              o.duration.isInfinite ? "indefinite" : ISO8601DateFormatter().string(from: o.scheduledInterval.end),
                                              o.syncIdentifier.uuidString))
        } else {
            SportLog.event("override", "SET-ON-WRIST · CLEARED — the loan's schedules resolve unscaled from here")
        }
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

    /// Eventual glucose split by effect. Diagnostic only; see `logPredictionBreakdown`.
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

    /// The immutable snapshot the glance reads on main. Built on `dataAccessQueue` and published
    /// through `mirroredGlanceData`; nothing in it is recomputed by the reader.
    struct GlanceData {
        let glucose: LoopQuantity?
        let glucoseDate: Date?

        /// When each source last delivered. The provenance line and the wedge hint are derived
        /// from the pair, so a fresh reading with a stale `directG7At` is the interesting case.
        let directG7At: Date?
        let phoneRelayAt: Date?
        /// When the current sensor was started, if known. A new sensor is quiet for its warm-up
        /// by design, and without this the silence hint cannot tell that from a parked radio.
        let sensorActivatedAt: Date?
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
    }

    /// What the pod is running, from the pump's delivery state.
    func runningTempBasal() -> DoseEntry? {
        if case .some(.tempBasal(let dose)) = pumpManager?.status.basalDeliveryState { return dose }
        return nil
    }

    let glanceMirrorLock = NSLock()
    var _glanceMirror: GlanceData?
    var _glanceRefreshPending = false

    /// How main reads the wrist's state. The alternative — syncing onto `dataAccessQueue` from a
    /// repeating tile refresh — blocks the UI behind whatever pod work is in progress.
    var mirroredGlanceData: GlanceData? {
        glanceMirrorLock.lock()
        defer { glanceMirrorLock.unlock() }
        return _glanceMirror
    }

    /// Posted after every mirror rebuild. An observer must redraw from `mirroredGlanceData` and
    /// must NOT ask for another rebuild — see `refreshGlanceData` for why that does not coalesce.
    static let glanceMirrorDidUpdate = Notification.Name("com.loopkit.Loop.glanceMirrorDidUpdate")

    /// The CGM delegate queue; direct and phone-relayed glucose ingest serialize here.
    let deviceQueue = DispatchQueue(label: "com.loopkit.Loop.WatchLoopManager.deviceQueue", qos: .utility)

    /// Serial and FIFO: grant settings land before the loan's first prediction.
    let dataAccessQueue = DispatchQueue(label: "com.loopkit.Loop.WatchLoopManager.dataAccessQueue", qos: .utility)

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
    let loopStateLock = NSLock()

    /// The CGM manager's `managerIdentifier` and `state`, and the configuration it was built from,
    /// in a file as stock keeps a CGM manager, replaced whole.
    var cgmManagerState: PersistedProperty<CGMManager.RawStateValue>

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
        self.cgmManagerState = stateDirectory.map { PersistedProperty<CGMManager.RawStateValue>(key: "CGMManagerState", directory: $0) }
            ?? PersistedProperty(key: "CGMManagerState")
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
        self._closedLoopEnabled = loopState.closedLoopEnabled
        self._closedLoopMirror = loopState.closedLoopEnabled
        self.integralRetrospectiveCorrectionEnabled = loopState.integralRetrospectiveCorrectionEnabled

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
                self?.updateDisplayStateForChange()
            }
        }
    }

    private let bgSourceLock = NSLock()
    private var _lastDirectG7At: Date?
    private var _lastPhoneRelayAt: Date?

    // MARK: - Glucose sources

    /// Built from the phone's configuration (or restored); the manager holds its delegate weakly.
    var cgmManager: CGMManager? {
        cgmLock.lock(); defer { cgmLock.unlock() }
        return _cgmManager
    }
    let cgmLock = NSLock()
    var _cgmManager: CGMManager?
    /// The configuration `cgmManager` was built from, saved beside its state.
    var cgmBuiltFrom: [String: Any]?
    static let builtFromKey = "builtFromConfiguration"

    /// Launch seed, so a relaunch does not reset the stranded-sensor clock; never moves it back.
    func seedLastDirectG7At(_ date: Date?) {
        bgSourceLock.lock()
        if let date, date > (_lastDirectG7At ?? .distantPast) { _lastDirectG7At = date }
        bgSourceLock.unlock()
    }

    /// Record WHERE a reading came from, so the wrist can answer "am I standing on my own right
    /// now?". Stamped on arrival by the ingest paths — see `processCGMReadingResult`.
    func noteGlucoseSource(directG7: Bool) {
        bgSourceLock.lock()
        if directG7 { _lastDirectG7At = self.now() } else { _lastPhoneRelayAt = self.now() }
        bgSourceLock.unlock()

        refreshGlanceData()
    }

    /// For glucose that arrived outside the CGM delegate, e.g. the grant seed.
    func notePhoneGlucoseDelivered() {
        noteGlucoseSource(directG7: false)
    }

    /// One-line "who is feeding this watch" for the log at the start of a loan.
    var g7ContentionSummary: String {
        let stamps = lastGlucoseSourceStamps
        func age(_ d: Date?) -> String { d.map { String(format: "%.0fs", now().timeIntervalSince($0)) } ?? "never" }

        return "g7direct=\(age(stamps.direct)) phoneRelay=\(age(stamps.phone))"
    }

    /// A phone relay says nothing about the watch's radio, so the two are kept apart.
    var lastGlucoseSourceStamps: (direct: Date?, phone: Date?) {
        bgSourceLock.lock()
        defer { bgSourceLock.unlock() }
        return (_lastDirectG7At, _lastPhoneRelayAt)
    }

    /// The basal schedule with the override applied; net rates must use this, not the raw schedule.
    var basalRateScheduleApplyingOverrideHistory: BasalRateSchedule? {
        settings.basalRateSchedule.map { overrideHistory.resolvingRecentBasalSchedule($0) }
    }

    /// Applied on `dataAccessQueue`, ahead of the first prediction.
    func setIntegralRetrospectiveCorrection(_ enabled: Bool) {
        updateLoopState { $0.integralRetrospectiveCorrectionEnabled = enabled }
        dataAccessQueue.async {
            self.integralRetrospectiveCorrectionEnabled = enabled
            SportLog.event("loan", "retrospective correction: \(enabled ? "INTEGRAL" : "standard") (from grant)")
        }
    }

    /// Queue-owned.
    var integralRetrospectiveCorrectionEnabled = false

    /// Stock glucose alerts, built from the phone's settings for a loan; nil between loans.
    @MainActor var glucoseAlerts: GlucoseAlertManager?

    // MARK: - Algorithm runs
    // Stock runs the algorithm three ways, each fed differently, and only the display run is
    // kept for screens. Each run's result is stored under its own name so no run can overwrite
    // another's values; the manual-bolus run stores nothing. `dataAccessQueue`-owned.

    /// Stock's `displayState`: the display run (`updateDisplayState`). The glance's IOB, eventual
    /// and COB, the stock pages' context and the complication read it; nothing doses from it.
    var displayState = AlgorithmDisplayState()

    /// The automatic loop's last run (input and output). Stock keeps this run local to `loop()`;
    /// the watch keeps it for the diagnostics page, the prediction breakdown and `[predict]`.
    var loopRunState = AlgorithmDisplayState()

    var lastPredictionBreakdown: PredictionBreakdown?

    /// The pending command and WHEN it was decided. The date is not decoration — the enact path
    /// refuses a recommendation older than five minutes.
    var recommendedAutomaticDose: (recommendation: AutomaticDoseRecommendation, enactTempBasal: Bool, date: Date)?

    /// The display's copy, kept because a successful enact clears `recommendedAutomaticDose` —
    /// without it the glance would blank the recommended rate on exactly the cycles that dosed.
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
        SportLog.event("loop", String(format: "loop recency SEEDED from %@ — last cycle %.0fs ago", source, self.now().timeIntervalSince(date)))
    }
    /// Last cycle's outcome, for display and the debug row. Cleared at the start of each cycle,
    /// so nil means "the cycle in progress has not failed yet", not "all is well".
    var lastLoopError: Error?

    /// Shared by BOTH glucose sources, so the 4.2-minute gate applies across them: a direct
    /// reading and the phone's relay of the same reading must not each fire a cycle. Each source
    /// claims it from its own background task, so it is read and written under one lock.
    private let cgmLoopTriggerLock = NSLock()
    private var lastCGMLoopTrigger: Date = .distantPast

    /// Stock's 4.2-minute gate, checked and claimed in one step: true means this caller runs the cycle.
    func claimCGMLoopTrigger(at now: Date) -> Bool {
        cgmLoopTriggerLock.lock()
        defer { cgmLoopTriggerLock.unlock() }
        guard now.timeIntervalSince(lastCGMLoopTrigger) > .minutes(4.2) else { return false }
        lastCGMLoopTrigger = now
        return true
    }

    /// The last phone-relayed sample taken, latched so the several copies that can arrive within
    /// milliseconds of each other are not each re-examined against an uncommitted store.
    var lastPhoneFallbackSyncId: String?

    /// Stock's `DoseEnactor`, unchanged. A `var` so tests can observe it.
    var doseEnactor = DoseEnactor()

    /// Say "idle, no pod" once per idle stretch instead of once per reading.
    var loggedIdleNoPump = false

    /// Stock's `LoopDataManager.lastManualBolusRecommendation`: the display run's last manual
    /// recommendation, so `updateRemoteRecommendation` stores only a change unless forced.
    var lastManualBolusRecommendation: ManualBolusRecommendation?

    /// Stock's `WatchDataManager.contextDosingDecisions`: the watchBolus decision built with each
    /// recommendation the wrist was shown, by the carb entry it assumed; kept five minutes.
    var contextDosingDecisions: [(date: Date, potentialCarbEntry: NewCarbEntry?, decision: StoredDosingDecision)] = []

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
    var lastLoopCompleted: Date?
    /// The override history's events, as LoopKit encodes them; read back only by a resume.
    var overrideEvents: Data?

    init() {}

    init?(rawValue: [String: Any]) {
        closedLoopEnabled = rawValue["closedLoopEnabled"] as? Bool ?? false
        integralRetrospectiveCorrectionEnabled = rawValue["integralRetrospectiveCorrectionEnabled"] as? Bool ?? false
        lastLoopCompleted = rawValue["lastLoopCompleted"] as? Date
        overrideEvents = rawValue["overrideEvents"] as? Data
    }

    var rawValue: [String: Any] {
        var raw: [String: Any] = ["closedLoopEnabled": closedLoopEnabled,
                                  "integralRetrospectiveCorrectionEnabled": integralRetrospectiveCorrectionEnabled]
        raw["lastLoopCompleted"] = lastLoopCompleted
        raw["overrideEvents"] = overrideEvents
        return raw
    }
}

/// A labelled copy of stock's `AlgorithmDisplayState` (`Loop/Managers/LoopDataManager.swift`,
/// phone-only): one algorithm run's input and output.
struct AlgorithmDisplayState {
    var input: StoredDataAlgorithmInput?
    var output: AlgorithmOutput<StoredCarbEntry>?

    var activeInsulin: InsulinValue? {
        guard let input, let value = output?.activeInsulin else {
            return nil
        }
        return InsulinValue(startDate: input.predictionStart, value: value)
    }

    var activeCarbs: CarbValue? {
        guard let input, let value = output?.activeCarbs else {
            return nil
        }
        return CarbValue(startDate: input.predictionStart, value: value)
    }

    var asTuple: (algoInput: StoredDataAlgorithmInput?, algoOutput: AlgorithmOutput<StoredCarbEntry>?) {
        return (algoInput: input, algoOutput: output)
    }
}
