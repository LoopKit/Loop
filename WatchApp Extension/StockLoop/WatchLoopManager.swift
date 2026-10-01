//
//  WatchLoopManager.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  The wrist's own Loop. While the phone has lent it the pod, this object is what
//  `LoopDataManager` and `DeviceDataManager` together are on the phone: it owns the watch's dose,
//  glucose and carb stores, the therapy snapshot frozen into the loan grant and the override
//  history, and it is the CGM and dose-store delegate. The cycle, the dosing, the glucose ingest,
//  the display surfaces and the log dumps are in the +Cycle, +Dosing, +Glucose, +Display and
//  +Diagnostics extensions; this file holds the type, its state, and the rules about which thread
//  may touch what.
//
//  THREADING. `dataAccessQueue` owns everything the cycle reads and writes, and MAIN MUST NEVER
//  SYNC ONTO IT — it is the same queue the pump work runs on, so a UI poll would block the watch
//  for the length of a bolus or a takeover. Anything main needs is therefore mirrored behind a
//  lock: the closed-loop flag, the glance snapshot, the manual-bolus state, the granted bolus
//  maximum and the glucose-source stamps each have one. The CGM manager's delegate runs on
//  `deviceQueue`, not on main as it does on the phone.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import G7SensorKit
import WatchConnectivity
import os.log

/// The cycle's failure vocabulary. The CYCLE VERDICT line reads these to say WHICH STAGE failed,
/// so the distinction between a compute error and an enact error is load-bearing, not cosmetic.
enum WatchLoopError: Error {
    /// A therapy setting the grant did not carry. Denies dosing; nothing is ever defaulted.
    case configurationError(String)

    /// The prediction could not be produced. A COMPUTE failure — never use it for a pod refusal.
    case missingDataError(String)

    /// The pod refused, or the command failed. Counts as a good compute and a failed enact.
    case enactFailed(String)

    /// Not stock: the recommendation is older than the enact path will act on.
    case recommendationExpired(date: Date)

    case pumpSuspended

    /// No pod on this watch. The ordinary answer between loans, not a fault.
    case pumpManagerUnconnected
}

/// `localizedDescription` for these errors, phrased in the pod's terms rather than the
/// algorithm's — it is what a failed manual bolus reports. The glance and the debug row print
/// `String(describing:)` on the case instead, so editing a string here does not change those.
extension WatchLoopError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .configurationError(let field):
            return String(format: NSLocalizedString("Missing setting: %@", comment: "Watch loop error (1: setting name)"), field)
        case .missingDataError(let what):
            return String(format: NSLocalizedString("Missing data: %@", comment: "Watch loop error (1: data name)"), what)
        case .enactFailed(let why):

            return String(format: NSLocalizedString("The pod did not accept the dose: %@", comment: "Watch loop error (1: pump error)"), why)
        case .recommendationExpired:
            return NSLocalizedString("The recommendation expired before enacting.", comment: "Watch loop error")
        case .pumpSuspended:
            return NSLocalizedString("Insulin delivery is suspended.", comment: "Watch loop error")
        case .pumpManagerUnconnected:
            return NSLocalizedString("No pod connected to the watch.", comment: "Watch loop error")
        }
    }
}

final class WatchLoopManager {
    /// The WATCH's own stores, opened by `StockLoopStack` — not a view onto the phone's.
    let doseStore: DoseStore
    let glucoseStore: GlucoseStore
    let carbStore: CarbStore

    let settingsProvider: WatchSettingsProvider

    /// The one and only override history in this stack, created alongside the stores and handed
    /// in here. An override reaches dosing ONLY through it: assigning `scheduleOverride` records
    /// into it and `fetchAlgorithmInput` reads it back. Give any part of the stack a second
    /// instance and the wrist resolves basal, ISF and carb ratio unscaled while netting
    /// historical temps against the wrong baseline — which presents exactly as an IOB bug.
    let overrideHistory: TemporaryScheduleOverrideHistory

    private let grantedMaximumBolusLock = NSLock()
    private var _grantedMaximumBolus: Double?

    /// The grant's bolus ceiling, readable from MAIN without touching `dataAccessQueue` — the
    /// bolus picker needs it while building a frame. It is the same value `settings.maximumBolus`
    /// holds; the enact path re-checks against that one on the queue.
    var grantedMaximumBolus: Double? {
        grantedMaximumBolusLock.lock()
        defer { grantedMaximumBolusLock.unlock() }
        return _grantedMaximumBolus
    }

    /// The therapy settings frozen into the loan grant. Replaced wholesale when a grant lands;
    /// the didSet is what keeps the main-readable mirror and the `SettingsProvider` in step, so
    /// never bypass it by mutating fields in place.
    var settings: LoopSettings {
        didSet {
            grantedMaximumBolusLock.lock()
            _grantedMaximumBolus = settings.maximumBolus
            grantedMaximumBolusLock.unlock()

            settingsProvider.update(with: settings)

        }
    }

    private var _scheduleOverride: TemporaryScheduleOverride?

    /// The active override. Setting it RECORDS INTO `overrideHistory`, which is what actually
    /// reaches the algorithm — the stored value alone changes nothing. The equality guard keeps a
    /// repeated set from stacking duplicate records in that history.
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

        }
    }

    /// Copy of stock `LoopDataManager.insulinModel(for:)`. One difference: the default arm reads
    /// `LoopSettings.defaultRapidActingModel`, which is already a model, where stock reads the
    /// `StoredSettings` preset — `WatchSettingsProvider` deliberately does not carry that field.
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
    var pumpManager: PumpManager?

    /// Whether the pod will beep on a manual bolus, injected by the session. The success haptic
    /// is played only when the pod is SILENT — with beeps on, the pod says the same thing at the
    /// same instant.
    var podBeepsOnManualBolusProbe: (() -> Bool)?

    /// Fired by `loop()` only on a cycle that LANDED, which is what renews the phone's hold. A
    /// cycle that computed but could not reach the pod must not renew it.
    var onCycleLanded: (() -> Void)?

    // A glucose reading that arrives while the pump manager is being rebuilt (resume, seize)
    // would otherwise be dropped by `checkPumpDataAndLoop`, which returns when there is no pump.
    // Remember that it happened; the rebuild's last act consumes the flag and runs the cycle.
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
    /// No probe means "assume the pod is silent", so the watch buzzes. A missing haptic is a
    /// worse failure than one buzz too many.
    var podBeepsOnManualBolus: Bool { podBeepsOnManualBolusProbe?() ?? false }

    /// Shared by the CGM and the pump managers, which log from several queues at once during a
    /// radio storm — the throttle has to be thread-safe on its own account.
    let deviceLogThrottle = DeviceLogThrottle()

    // Manual-bolus UI state. All of it is read from MAIN while the dose is in flight — which is
    // precisely when `dataAccessQueue` is busy — so it lives behind its own lock.
    private let manualBolusLock = NSLock()
    private var _manualBolusInFlight = false

    /// Stamped when the user CONFIRMS, not when the pod accepts, because that is the wait the
    /// glance is narrating: the flow auto-dismisses in about a second while the dose can take
    /// tens of seconds to land, and a user who reads that silence as a hang taps End — which
    /// cancels the in-flight work and destroys the dose.
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

    private var _manualBolusDelivery: (units: Double, startedAt: Date, endsAt: Date)?

    /// The delivery estimate, which EXPIRES ON ITS OWN CLOCK — past `endsAt` this answers nil
    /// rather than a completed state. Clearing it any other way would depend on a rebuild that
    /// the bolus itself delays, and calling it "delivered" from a clock would claim something
    /// nobody watched happen.
    var manualBolusDelivery: (units: Double, startedAt: Date, endsAt: Date)? {
        manualBolusLock.lock(); defer { manualBolusLock.unlock() }
        guard let d = _manualBolusDelivery, d.endsAt > self.now() else { return nil }
        return d
    }
    /// Posts on MAIN: the enact completion that calls this runs on a background queue, the
    /// observer mutates published UI state, and the glance's own tick is blocked behind the dose.
    func setManualBolusDelivering(units: Double, from startedAt: Date, to endsAt: Date) {
        manualBolusLock.lock()
        _manualBolusDelivery = (units: units, startedAt: startedAt, endsAt: endsAt)
        manualBolusLock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .manualBolusStateDidChange, object: nil)
        }
    }

    var _closedLoopEnabled = false

    /// The wrist's loop mode, and the ONLY gate on automatic dosing here. It is never ANDed with
    /// the phone's `dosingEnabled`: once the pod is lent the watch is sovereign over loop mode,
    /// and combining the two produced a control the user could not turn on whenever the phone
    /// happened to be running open loop. The grant's therapy settings are the only limits.
    ///
    /// This getter SYNCS onto `dataAccessQueue`. Never call it from the loan controller's queue —
    /// use `closedLoopEnabledNonBlocking` there.
    var closedLoopEnabled: Bool {
        RuntimeStateLog.markBlockingIfMain("blocking.closedLoopEnabled")
        defer { RuntimeStateLog.markBlockingIfMain("blocking.closedLoopEnabled.done") }
        return dataAccessQueue.sync { _closedLoopEnabled }
    }

    private let closedLoopMirrorLock = NSLock()
    private var _closedLoopMirror = false
    /// The same flag without the hop. A hand-back offer is built on the loan controller's queue,
    /// and reading `closedLoopEnabled` from there is the deadlock direction: the tap appears to
    /// succeed, the app is killed moments later, and no insulin is delivered.
    var closedLoopEnabledNonBlocking: Bool {
        closedLoopMirrorLock.lock()
        defer { closedLoopMirrorLock.unlock() }
        return _closedLoopMirror
    }

    // Persisted, and reloaded in `init`. Held only in memory, a relaunch mid-loan came back OPEN
    // with a grey ring — and the phone then inherited OPEN at hand-back.
    static let closedLoopDefaultsKey = "WatchLoopManager.closedLoopEnabled"
    static let integralRCDefaultsKey = "WatchLoopManager.integralRetrospectiveCorrection"
    /// Syncs onto `dataAccessQueue`, with the same caveat as `closedLoopEnabled`: not from the
    /// loan controller's queue.
    var isIntegralRetrospectiveCorrectionEnabled: Bool { dataAccessQueue.sync { integralRetrospectiveCorrectionEnabled } }

    /// Loop mode is PER SESSION. Clearing it at the end of a loan is what stops a stale "closed"
    /// from making the next grant — which inherits the phone's mode, often open — look like a
    /// closed-to-open transition, and fire the cancel below at a pod that is mid-takeover.
    func resetClosedLoopForSessionEnd() {
        UserDefaults.standard.set(false, forKey: Self.closedLoopDefaultsKey)
        closedLoopMirrorLock.lock()
        _closedLoopMirror = false
        closedLoopMirrorLock.unlock()
        dataAccessQueue.async {
            self._closedLoopEnabled = false
        }
    }

    /// Change the wrist's loop mode. The defaults write and the mirror update happen
    /// SYNCHRONOUSLY, before the queue hop: a hand-back offer built immediately after the user's
    /// tap must carry the value they just chose, not the one the queue has yet to apply.
    ///
    /// OPENING the loop cancels the running temp. Stock does this too, but only after checking
    /// that an automatic temp is actually running; this sends the cancel unconditionally, and a
    /// failure is logged rather than escalated — a cancel can only ever move toward LESS insulin.
    /// The `wasEnabled, !enabled` guard is what confines it to a REAL transition: without it a
    /// grant that inherits an open loop fires a cancel at a pod in the middle of takeover.
    func setClosedLoopEnabled(_ enabled: Bool, reason: String = "by user") {
        UserDefaults.standard.set(enabled, forKey: Self.closedLoopDefaultsKey)

        closedLoopMirrorLock.lock()
        let wasEnabled = _closedLoopMirror
        _closedLoopMirror = enabled
        closedLoopMirrorLock.unlock()

        dataAccessQueue.async {
            self._closedLoopEnabled = enabled
            SportLog.event("loop", enabled ? "CLOSED \(reason) — the watch will adjust basal" : "OPENED \(reason) — advisory only, no dosing")

            self.publishHUDContext()

            guard wasEnabled, !enabled else { return }
            let recommendation = AutomaticDoseRecommendation(basalAdjustment: .cancel, direction: .decrease)
            self.recommendedAutomaticDose = (recommendation: recommendation, date: self.now())
            if let error = self.enactRecommendedAutomaticDose() {
                SportLog.event("loop", "OPEN: temp cancel FAILED — \(String(describing: error)); the pod keeps its current rate until the temp expires")
            } else {
                SportLog.event("loop", "OPEN: running temp cancelled — pod reverts to the user's schedule")
            }
        }
    }

    /// Apply an override the user set ON THE WRIST, so it reaches dosing and not only the
    /// display. Local first, because this is the device holding the pod; telling the phone is the
    /// caller's business and is best-effort, since the phone may be switched off for the loan.
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
            SportLog.event("override", "SET-ON-WRIST · CLEARED by user — the loan's schedules resolve unscaled from here")
        }
        scheduleOverride = override
    }

    /// The eventual glucose split into the effects behind it, for the log and the debug screen.
    /// DIAGNOSTIC ONLY — nothing doses from these numbers. Built by `logPredictionBreakdown`,
    /// which is where the arithmetic and its limits are described.
    struct PredictionBreakdown {
        /// The latest STORED glucose, which is the row's left-hand side rather than the
        /// prediction's own starting point.
        let startMgdl: Double

        let eventualMgdl: Double
        let insulinMgdl: Double
        let carbMgdl: Double
        let momentumMgdl: Double
        let retrospectiveMgdl: Double

        /// Whatever the named effects do not account for, so the row adds up. NOT zero by
        /// construction: the effects are differenced independently and the momentum blend's taper
        /// is not applied. A large one is the thing worth looking at, not a defect in the split.
        let residualMgdl: Double

        let insulinRawTailMgdl: Double?

        /// Nil at the only site that builds one: the "-ISF x IOB" cross-check was never carried
        /// over. Do not read them as if they were populated.
        let insulinExpectedMgdl: Double?
        let isfMgdlPerU: Double?
        let iobUnits: Double?
        let momentumPointCount: Int
        let computedAt: Date

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
        let eventual: LoopQuantity?
        /// IOB read from the BOOK. `predictionBreakdown.iobUnits` is the algorithm's own figure
        /// from the last run, and the two are allowed to differ — one is current, the other is as
        /// of that run. Do not treat a mismatch as a defect without checking which is which.
        let iob: Double?

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

    /// What the POD says it is running, not what the book records. This is the value
    /// `adjustForCurrentDelivery` compares against and the one the displayed net rate is built
    /// from, so it has to come from the pump's own delivery state.
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

    /// The CGM manager's delegate queue, installed by `StockLoopStack`. Glucose arrives here and
    /// the phone-relay path hops onto it too, so the two sources' ingest guards run one at a
    /// time — the store writes they start are async and can still overlap.
    let deviceQueue = DispatchQueue(label: "com.loopkit.Loop.WatchLoopManager.deviceQueue", qos: .utility)

    /// Serial, and it owns the cycle: prediction state, recommendations, enact, display publish.
    /// FIFO on it is a correctness property, not an implementation detail — it is what guarantees
    /// that settings applied at grant intake are in place before the loan's first prediction runs.
    let dataAccessQueue = DispatchQueue(label: "com.loopkit.Loop.WatchLoopManager.dataAccessQueue", qos: .utility)

    let log = OSLog(category: "WatchLoopManager")

    /// Clock and defaults are injectable so the suite can drive a cycle without waiting on either.
    var now: () -> Date = { Date() }

    var defaults: UserDefaults = .standard

    /// Restores the three pieces of state that must survive a relaunch mid-loan — the last
    /// completed cycle, the loop mode and the retrospective-correction model — and subscribes to
    /// the phone's context updates, which is how the glucose fallback is driven. The simulator
    /// has its own ingest path (`simIngestPhoneGlucose`) and must not also take this one.
    init(doseStore: DoseStore, glucoseStore: GlucoseStore, carbStore: CarbStore,
         overrideHistory: TemporaryScheduleOverrideHistory = TemporaryScheduleOverrideHistory(),
         settings: LoopSettings = LoopSettings()) {
        self.doseStore = doseStore
        self.glucoseStore = glucoseStore
        self.carbStore = carbStore
        self.settingsProvider = WatchSettingsProvider(settings: settings)
        self.overrideHistory = overrideHistory
        self.settings = settings
        self.lastLoopCompleted = UserDefaults.standard.object(forKey: Self.lastLoopCompletedKey) as? Date
        let closed = UserDefaults.standard.bool(forKey: Self.closedLoopDefaultsKey)
        self._closedLoopEnabled = closed
        self._closedLoopMirror = closed
        self.integralRetrospectiveCorrectionEnabled = UserDefaults.standard.bool(forKey: Self.integralRCDefaultsKey)

        // The store asks us for the scheduled basal it nets doses against; see the
        // `DoseStoreDelegate` conformance.
        doseStore.delegate = self
        #if !targetEnvironment(simulator)

        NotificationCenter.default.addObserver(forName: LoopDataManager.didUpdateContextNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.ingestPhoneGlucoseFromContext()
        }
        #endif
    }

    private let bgSourceLock = NSLock()
    private var _lastDirectG7At: Date?
    private var _lastPhoneRelayAt: Date?

    /// How long the direct G7 may have been silent before Start says so.
    static let startGateSilenceLimit: TimeInterval = .minutes(15)

    /// What the Start tap is told about the watch's own sensor link. EVERY verdict WARNS and NONE
    /// of them blocks — the caller logs and proceeds.
    ///
    /// Blocking would be backwards: direct G7 readings only arrive while the app has runtime, so
    /// the quarter-hour before a Start tap is precisely the era in which the evidence cannot
    /// exist. The loan is what grants the runtime whose absence the gate would be reading as a
    /// fault. `noSensorEverEnrolled` warns for a different reason: a device deliberately run
    /// without a sensor is indistinguishable from a new user, and neither should be blocked.
    enum StartGateVerdict: Equatable {
        case allowed

        /// A sensor is enrolled and this watch has heard it before, but not recently. Expected
        /// between loans, when the app has no runtime to listen with.
        case noDirectConnection(sensorName: String, silentMinutes: Int)

        /// Enrolled, never yet heard by THIS watch. A relay-only loan still works; it stops
        /// looping if the phone leaves.
        case waitingForFirstReading(sensorName: String)

        /// No sensor has ever been enrolled here.
        case noSensorEverEnrolled
    }

    /// Pure, and static, so the verdict can be exercised without a G7 or a store behind it.
    /// `sportModeStartGate` supplies the live arguments.
    static func startGateVerdict(sensorName: String?,
                                 sensorActivatedAt: Date?,
                                 lastDirectG7At: Date?,
                                 now: Date) -> StartGateVerdict {
        guard let name = sensorName else { return .noSensorEverEnrolled }

        // An identity past its life is not something to warn about: the stack discards it and
        // runs a fresh acquisition, so naming a dead sensor would give the user nothing to act on.
        guard !persistedSensorIsPastLife(sensorActivatedAt, now: now) else { return .allowed }
        guard let lastDirect = lastDirectG7At else {
            return .waitingForFirstReading(sensorName: name)
        }
        let silent = now.timeIntervalSince(lastDirect)
        guard silent > startGateSilenceLimit else { return .allowed }
        return .noDirectConnection(sensorName: name, silentMinutes: Int(silent / 60))
    }

    func sportModeStartGate(now: Date = Date()) -> StartGateVerdict {
        Self.startGateVerdict(sensorName: g7Manager?.sensorName,
                              sensorActivatedAt: g7Manager?.sensorActivatedAt,
                              lastDirectG7At: lastGlucoseSourceStamps.direct,
                              now: now)
    }

    /// A G7 session runs 10 days plus a 12-hour grace. Past that, a persisted identity is dead
    /// and the escapes that depend on this may honour a cleared sensor. An unknown activation
    /// date is NOT past its life — nil means unknown, and guessing would strand the sensor.
    static func persistedSensorIsPastLife(_ activatedAt: Date?, now: Date = Date()) -> Bool {
        guard let activatedAt else { return false }
        return now.timeIntervalSince(activatedAt) > .hours(10 * 24 + 12)
    }

    // MARK: - Glucose sources

    /// Weak: `StockLoopStack` owns the manager and holds this object as its delegate, so a
    /// strong reference here would close the cycle.
    weak var g7Manager: G7CGMManager?

    /// What the last persisted G7 state named, so the "manager forgot the sensor" notice is
    /// written once per episode rather than on every state update.
    var lastPersistedSensorID: String?

    /// The direct-G7 stamp is PERSISTED as well as held in memory. In memory only, every
    /// relaunch told a user with a perfectly healthy sensor to go and check Dexcom, and the
    /// stranded-identity clock restarted from zero each time.
    static let lastDirectG7DefaultsKey = "SportMode.lastDirectG7At"

    /// Record WHERE a reading came from, so the wrist can answer "am I standing on my own right
    /// now?". Stamped on arrival by the ingest paths — see `processCGMReadingResult`.
    func noteGlucoseSource(directG7: Bool) {
        bgSourceLock.lock()
        if directG7 { _lastDirectG7At = self.now() } else { _lastPhoneRelayAt = self.now() }
        bgSourceLock.unlock()
        if directG7 {
            defaults.set(self.now(), forKey: Self.lastDirectG7DefaultsKey)
        }

        refreshGlanceData()
    }

    /// For glucose that reached the store by some path other than the CGM delegate — the grant
    /// seed, principally. Those samples came out of the phone's own store, so "via iPhone" IS
    /// their provenance, and without the stamp the provenance line is blank for the first minutes
    /// of every loan.
    func notePhoneGlucoseDelivered() {
        noteGlucoseSource(directG7: false)
    }

    /// One-line "who is feeding this watch" for the log at the start of a loan.
    var g7ContentionSummary: String {
        let stamps = lastGlucoseSourceStamps
        func age(_ d: Date?) -> String { d.map { String(format: "%.0fs", now().timeIntervalSince($0)) } ?? "never" }

        return "g7direct=\(age(stamps.direct)) phoneRelay=\(age(stamps.phone))"
    }

    /// In-memory stamps, with the persisted value standing in for the direct one after a
    /// relaunch. Only the direct stamp is persisted: a phone relay proves nothing about the
    /// watch's own radio, which is the question these ages are asked to answer.
    var lastGlucoseSourceStamps: (direct: Date?, phone: Date?) {
        bgSourceLock.lock()
        let mem = (_lastDirectG7At, _lastPhoneRelayAt)
        bgSourceLock.unlock()

        let direct = mem.0 ?? defaults.object(forKey: Self.lastDirectG7DefaultsKey) as? Date
        return (direct, mem.1)
    }

    /// The basal schedule AS THE OVERRIDE LEAVES IT. Everything that nets a delivered rate
    /// against "what would be running anyway" must use this and not `settings.basalRateSchedule`:
    /// netting a temp against the raw schedule under an active override renders "+0.00" while the
    /// pod runs a multiple of the intended basal.
    var basalRateScheduleApplyingOverrideHistory: BasalRateSchedule? {
        settings.basalRateSchedule.map { overrideHistory.resolvingRecentBasalSchedule($0) }
    }

    /// Carried from the phone in the grant, and applied ON `dataAccessQueue` at intake. The hop
    /// is what puts it in front of the first prediction: FIFO on the serial queue is the only
    /// reason that prediction cannot run Standard and then jump to Integral a moment later.
    func setIntegralRetrospectiveCorrection(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.integralRCDefaultsKey)
        dataAccessQueue.async {
            self.integralRetrospectiveCorrectionEnabled = enabled
            SportLog.event("loan", "retrospective correction: \(enabled ? "INTEGRAL" : "standard") (from grant)")
        }
    }

    /// IOB for display: the book first, the last algorithm run only as a fallback. The book
    /// answers even before a cycle has run, which is what fills the number in at takeover.
    var liveInsulinOnBoard: Double? {
        dispatchPrecondition(condition: .onQueue(dataAccessQueue))
        return insulinOnBoardFromStore(at: now()) ?? activeInsulin
    }

    /// Queue-owned; `isIntegralRetrospectiveCorrectionEnabled` is the safe way to read it.
    var integralRetrospectiveCorrectionEnabled = false

    // MARK: - Last algorithm run
    //
    // These four are whatever the MOST RECENT run produced, and two different runs write them:
    // the temp-basal run in `updatePredictedGlucoseAndRecommendedDose` and the manual-bolus run
    // in `manualBolusRecommendationOnQueue`, which `publishHUDContext` calls on every publish.
    // So the displayed numbers may belong to the manual-bolus pass rather than to the pass that
    // decided the temp. All four are `dataAccessQueue`-owned.

    var predictedGlucose: [PredictedGlucoseValue]?

    var activeInsulin: Double?
    var activeCarbs: Double?
    var lastAlgorithmEffects: LoopAlgorithmEffects<StoredCarbEntry>?

    var lastPredictionBreakdown: PredictionBreakdown?

    /// The pending command and WHEN it was decided. The date is not decoration — the enact path
    /// refuses a recommendation older than five minutes.
    var recommendedAutomaticDose: (recommendation: AutomaticDoseRecommendation, date: Date)?

    /// The phone's prediction as of the grant, kept only so the log can compare the two devices
    /// over the one window where they ran on the same inputs. Nothing doses from it.
    var phonePredictionSnapshotAtGrant: LoanPredictionSnapshot?
    func stashPhonePredictionSnapshot(_ snapshot: LoanPredictionSnapshot?) {
        dataAccessQueue.async { self.phonePredictionSnapshotAtGrant = snapshot }
    }

    /// The display's copy, kept because a successful enact clears `recommendedAutomaticDose` —
    /// without it the glance would blank the recommended rate on exactly the cycles that dosed.
    var lastRecommendation: AutomaticDoseRecommendation?

    /// When a cycle last completed — the freshness ring's only input. Persisted on every write:
    /// a relaunch mid-loan that came back with no value opened the ring grey for a cycle.
    private static let lastLoopCompletedKey = "WatchLoopManager.lastLoopCompleted"
    var lastLoopCompleted: Date? {
        didSet { UserDefaults.standard.set(lastLoopCompleted, forKey: Self.lastLoopCompletedKey) }
    }

    /// Adopt someone else's completion time — the phone's, at grant — so a fresh loan does not
    /// open looking stale. MONOTONIC: it can only move forward, so a late or replayed seed can
    /// never make the wrist look fresher than its own last cycle proves it is.
    func seedLastLoopCompleted(_ date: Date, source: String) {
        guard (lastLoopCompleted ?? .distantPast) < date else { return }
        lastLoopCompleted = date
        SportLog.event("loop", String(format: "loop recency SEEDED from %@ — last cycle %.0fs ago", source, self.now().timeIntervalSince(date)))
    }
    /// Last cycle's outcome, for display and the debug row. Cleared at the start of each cycle,
    /// so nil means "the cycle in progress has not failed yet", not "all is well".
    var lastLoopError: Error?

    /// Shared by BOTH glucose sources, so the 4.2-minute gate applies across them: a direct
    /// reading and the phone's relay of the same reading must not each fire a cycle.
    var lastCGMLoopTrigger: Date = .distantPast

    /// The last phone-relayed sample taken, latched so the several copies that can arrive within
    /// milliseconds of each other are not each re-examined against an uncommitted store.
    var lastPhoneFallbackSyncId: String?

    /// A labelled copy of stock's `DoseEnactor`; see that file.
    let doseEnactor = WatchDoseEnactor()

    /// Say "idle, no pod" once per idle stretch instead of once per reading.
    var loggedIdleNoPump = false

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
