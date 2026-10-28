//
//  LoopDosingManager.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/21/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopCore
import WatchConnectivity
import os.log
import LoopAlgorithm
import UserNotifications
import WatchKit

@MainActor
@Observable
class LoopDataManager {
    static let shared = LoopDataManager()

    /// The watch's stores, one set for its screens and, during a loan, its loop. Carbs, doses and
    /// dosing decisions share one Core Data stack; glucose has its own (see `init`).
    let carbStore: CarbStore

    var glucoseStore: GlucoseStore?

    /// The stores only the loop uses; nil until opened.
    private(set) var loopStores: WatchLoopStores?

    @ObservationIgnored
    private var storesOpened: Task<Void, Never>?

    /// Every store, once all are open; nil if one could not be.
    func openedStores() async -> (glucoseStore: GlucoseStore, carbStore: CarbStore, loopStores: WatchLoopStores)? {
        await storesOpened?.value
        guard let glucoseStore, let loopStores else { return nil }
        return (glucoseStore, carbStore, loopStores)
    }

    @ObservationIgnored
    @PersistedProperty(key: "Settings")
    private var rawWatchInfo: LoopSettingsUserInfo.RawValue?

    @ObservationIgnored
    @PersistedProperty(key: "WatchContext")
    private var rawWatchContext: WatchContext.RawValue?

    // Main queue only
    var watchInfo: LoopSettingsUserInfo {
        didSet {
            needsDidUpdateContextNotification = true
            sendDidUpdateContextNotificationIfNecessary()
            rawWatchInfo = watchInfo.rawValue
        }
    }

    var pendingPresetReminder: PendingPresetReminder?

    var pendingPreset: SelectablePreset? {
        if let presetIdentifier = pendingPresetReminder?.presetIdentifier {
            return selectablePresets.first(where: { $0.id == presetIdentifier })!
        } else {
            return nil
        }
    }

    var activePreset: SelectablePreset? {
        guard let presetId = scheduleOverride?.presetId else {
            return nil
        }
        return selectablePresets.first(where: { $0.id == presetId })
    }

    var glucoseChartScene: GlucoseChartScene = {
        let s = GlucoseChartScene()
        s.size = WKInterfaceDevice.current().screenBounds.size
        return s
    }()

    // When set, user will be navigated to carbs/bolus flow
    var bolusViewModel: CarbAndBolusFlowViewModel?

    // Main queue only
    var supportedBolusVolumes = UserDefaults.standard.supportedBolusVolumes {
        didSet {
            UserDefaults.standard.supportedBolusVolumes = supportedBolusVolumes
            needsDidUpdateContextNotification = true
            sendDidUpdateContextNotificationIfNecessary()
        }
    }

    private let log = OSLog(category: "LoopDosingManager")

    // Main queue only
    /// The phone's last context. Screens read `displayContext`.
    private(set) var activeContext: WatchContext? {
        didSet {
            rawWatchContext = activeContext?.rawValue
            updateDisplayContext()
        }
    }

    /// The state of the watch holding a lent pod, published by Sport Mode for the screens; nil otherwise.
    var wristState: WatchContext? {
        didSet { updateDisplayContext() }
    }

    /// The override the watch's loop doses with during a loan, published by Sport Mode for the
    /// screens: `.none` between loans, `.some(nil)` during a loan with no override.
    var wristOverride: TemporaryScheduleOverride?? = .none

    /// The active override, as the screens show it (`scheduleOverride(phone:wrist:)`).
    var scheduleOverride: TemporaryScheduleOverride? {
        Self.scheduleOverride(phone: watchInfo.scheduleOverride, wrist: wristOverride)
    }

    /// During a loan, the override the watch's loop doses with; otherwise the phone's.
    nonisolated static func scheduleOverride(phone: TemporaryScheduleOverride?, wrist: TemporaryScheduleOverride??) -> TemporaryScheduleOverride? {
        wrist ?? phone
    }

    /// What the screens show (`displayContext(phone:wrist:directGlucose:)`).
    private(set) var displayContext: WatchContext?

    private func updateDisplayContext() {
        displayContext = Self.displayContext(phone: activeContext, wrist: wristState, directGlucose: latestDirectGlucose)
        needsDidUpdateContextNotification = true
        sendDidUpdateContextNotificationIfNecessary()
    }

    private var needsDidUpdateContextNotification: Bool = false

    /// The newest reading from the watch's own connection to the CGM. Main queue only.
    private(set) var latestDirectGlucose: NewGlucoseSample? {
        didSet { updateDisplayContext() }
    }

    /// Bumped once the watch's own readings are in the store, for the chart.
    private(set) var directGlucoseRevision = 0

    /// The last attempt to backfill glucose. We use a date because the message timeout is longer
    /// than our desired retry interval, so we allow multiple messages in-flight
    /// Main queue only
    private var lastGlucoseBackfill = Date.distantPast

    public let healthStore: HKHealthStore

    init() {
        healthStore = HKHealthStore()
        let cacheStore = PersistenceController.controllerInLocalDirectory()
        let provenanceIdentifier = HKSource.default().bundleIdentifier
        // The phone's history length, as the loop's stores need; the carb list reads since midnight.
        let localCacheDuration = Bundle.main.localCacheDuration

        carbStore = CarbStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            provenanceIdentifier: provenanceIdentifier
        )

        self.watchInfo = LoopSettingsUserInfo(
            loopSettings: LoopSettings(),
            scheduleOverride: nil
        )

        // Give GlucoseStore its own Core Data stack rather than sharing `cacheStore` with
        // CarbStore. GlucoseStore drives its context exclusively with the async
        // `context.perform` API, while CarbStore uses `performAndWait`. Sharing one serial
        // context between the two mixes those concurrency models and can race, producing a
        // torn read of a freshly-inserted CachedGlucoseObject (a nil required attribute).
        // A dedicated context removes that cross-store contention.
        let glucoseCacheStore = PersistenceController.controllerInLocalDirectory(named: "com.loopkit.LoopKit.Glucose")

        if let rawWatchInfo, let watchInfo = LoopSettingsUserInfo(rawValue: rawWatchInfo) {
            self.watchInfo = watchInfo
        }

        if let rawWatchContext, let watchContext = WatchContext(rawValue: rawWatchContext) {
            self.activeContext = watchContext
        }
        // Observers do not run in an initializer.
        displayContext = activeContext

        // Glucose kept 24 hours: the loop reads 12 (the carb absorption window), the chart less.
        storesOpened = Task {
            glucoseStore = await GlucoseStore(
                healthKitSampleStore: nil,
                cacheStore: glucoseCacheStore,
                cacheLength: .hours(24),
                provenanceIdentifier: provenanceIdentifier
            )
            loopStores = await WatchLoopStores.open(cacheStore: cacheStore, cacheLength: localCacheDuration,
                                                    provenanceIdentifier: provenanceIdentifier)
        }
    }
}

/// Stock's `AlertStore` logs through the phone's `DiagnosticLog`, which forwards to logging
/// services the watch does not have; os_log under the same subsystem stands in.
typealias DiagnosticLog = OSLog

/// The stores only the loop uses: doses and dosing decisions on the carbs' Core Data stack, as
/// stock's phone builds them, and its alert history and device log.
struct WatchLoopStores {
    let doseStore: DoseStore
    let dosingDecisionStore: DosingDecisionStore
    let alertStore: AlertStore
    let deviceLog: PersistentDeviceLog

    static func open(cacheStore: PersistenceController, cacheLength: TimeInterval, provenanceIdentifier: String) async -> WatchLoopStores? {
        guard let documents = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }

        let doseStore = await DoseStore(
            healthKitSampleStore: nil,
            cacheStore: cacheStore,
            cacheLength: cacheLength,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            provenanceIdentifier: provenanceIdentifier
        )
        let dosingDecisionStore = DosingDecisionStore(store: cacheStore, expireAfter: cacheLength)

        let alertStoreDirectory = documents.appendingPathComponent("AlertStore")
        try? FileManager.default.createDirectory(at: alertStoreDirectory, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let alertStore = AlertStore(storageDirectoryURL: alertStoreDirectory, expireAfter: cacheLength)

        let deviceLogDirectory = documents.appendingPathComponent("DeviceLog")
        do {
            try FileManager.default.createDirectory(at: deviceLogDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let deviceLog = PersistentDeviceLog(storageFile: deviceLogDirectory.appendingPathComponent("Storage.sqlite"),
                                            maxEntryAge: cacheLength)

        return WatchLoopStores(doseStore: doseStore, dosingDecisionStore: dosingDecisionStore, alertStore: alertStore, deviceLog: deviceLog)
    }
}

extension LoopDataManager {
    static let didUpdateContextNotification = Notification.Name(rawValue: "com.loopkit.notification.ContextUpdated")
}

extension LoopDataManager {
    func updateContext(_ context: WatchContext) {
        dispatchPrecondition(condition: .onQueue(.main))

        if activeContext == nil || context.shouldReplace(activeContext!) {
            if let newGlucoseSample = context.newGlucoseSample {
                Task {
                    try? await self.glucoseStore?.addGlucoseSamples([newGlucoseSample])
                }
            }
            activeContext = context
        }
        WatchCGMHost.shared.update(from: context)
    }

    /// Readings from the watch's own connection to the CGM. Stored beside the phone's (the same
    /// reading from both carries the same sync identifier, so the store keeps one) and shown while
    /// newer than the phone's.
    func addDirectGlucose(_ samples: [NewGlucoseSample]) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let latest = samples.max(by: { $0.date < $1.date }) else { return }
        if latestDirectGlucose.map({ latest.date > $0.date }) ?? true {
            latestDirectGlucose = latest
        }
        Task {
            do {
                _ = try await self.glucoseStore?.addGlucoseSamples(samples)
            } catch {
                self.log.error("Failure adding direct glucose samples: %{public}@", String(describing: error))
            }
            self.directGlucoseRevision += 1
            self.needsDidUpdateContextNotification = true
            self.sendDidUpdateContextNotificationIfNecessary()
        }
    }

    func directGlucoseDidEnd() {
        latestDirectGlucose = nil
    }

    /// What the screens show: the phone's context, with the state of the watch holding a lent pod over
    /// it, or otherwise with the watch's own reading in place of the phone's when it is newer.
    nonisolated static func displayContext(phone: WatchContext?, wrist: WatchContext?, directGlucose: NewGlucoseSample?) -> WatchContext? {
        if let wrist {
            let context = phone.flatMap { WatchContext(rawValue: $0.rawValue) } ?? WatchContext()
            context.overlayWatchState(from: wrist)
            return context
        }
        guard let phone else { return nil }
        guard let direct = directGlucose, direct.date > phone.glucoseDate ?? .distantPast,
              let context = WatchContext(rawValue: phone.rawValue) else {
            return phone
        }
        context.glucose = direct.quantity
        context.glucoseDate = direct.date
        context.glucoseTrend = direct.trend
        context.glucoseTrendRate = direct.trendRate
        context.glucoseCondition = direct.condition
        context.glucoseIsDisplayOnly = direct.isDisplayOnly
        context.glucoseWasUserEntered = direct.wasUserEntered
        context.glucoseSyncIdentifier = direct.syncIdentifier
        return context
    }

    func sendDidUpdateContextNotificationIfNecessary() {
        dispatchPrecondition(condition: .onQueue(.main))

        if needsDidUpdateContextNotification && !WCSession.default.hasContentPending {
            needsDidUpdateContextNotification = false
            NotificationCenter.default.post(name: LoopDataManager.didUpdateContextNotification, object: self)
        }
    }

    func sendUserSelectedNotificationActionMessage(alertIdentifier: String, managerIdentifier: String, actionIdentifier: String) async {
        await WCSession.default.sendUserSelectedNotificationActionMessage(
            alertIdentifier: alertIdentifier,
            managerIdentifier: managerIdentifier,
            actionIdentifier: actionIdentifier
        )
    }

    func requestCarbBackfill() {
        dispatchPrecondition(condition: .onQueue(.main))

        let start = min(Calendar.current.startOfDay(for: Date()), Date(timeIntervalSinceNow: -CarbMath.maximumAbsorptionTimeInterval))
        let userInfo = CarbBackfillRequestUserInfo(startDate: start)
        WCSession.default.sendCarbBackfillRequestMessage(userInfo) { (result) in
            switch result {
            case .success(let context):
                self.carbStore.setSyncCarbObjects(context.objects) { (error) in
                    if let error = error {
                        self.log.error("Failure setting sync carb objects: %{public}@", String(describing: error))
                    }
                }
            case .failure:
                // Already logged
                break
            }
        }
    }

    @discardableResult
    func requestGlucoseBackfillIfNecessary() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))

        // Throttle: don't re-request within the stale window of our last attempt.
        guard lastGlucoseBackfill < .staleGlucoseCutoff else {
            log.default("Skipping glucose backfill request because our latest attempt was %{public}@", String(describing: lastGlucoseBackfill))
            return false
        }

        // Loop doesn't read data from HealthKit anymore, and its local watch data is truly ephemeral
        // to power the chart. Backfill from just after our most recent stored sample so the phone
        // returns exactly what we're missing (no overlap); if we have nothing recent, fall back to
        // the earliest cutoff to repopulate the whole chart window.
        // The watch's own readings don't mean the phone's are here: start no later than the phone's
        // last reading, and the store drops what it already has.
        var latestSampleDate = glucoseStore?.latestGlucose?.startDate ?? .distantPast
        if latestDirectGlucose != nil, let phoneGlucoseDate = activeContext?.glucoseDate {
            latestSampleDate = min(latestSampleDate, phoneGlucoseDate)
        }
        let latestDate = max(latestSampleDate, .earliestGlucoseCutoff)
        guard latestDate < .staleGlucoseCutoff else {
            self.log.default("Skipping glucose backfill request because our latest sample date is %{public}@", String(describing: latestDate))
            return false
        }

        lastGlucoseBackfill = Date()
        let userInfo = GlucoseBackfillRequestUserInfo(startDate: latestDate)
        WCSession.default.sendGlucoseBackfillRequestMessage(userInfo) { (result) in
            switch result {
            case .success(let context):
                Task {
                    do {
                        try await self.glucoseStore?.setSyncGlucoseSamples(context.samples)
                    } catch {
                        self.log.error("Failure setting sync glucose samples: %{public}@", String(describing: error))
                    }
                }
            case .failure:
                // Already logged
                // Reset our last date to immediately retry
                DispatchQueue.main.async {
                    self.lastGlucoseBackfill = .earliestGlucoseCutoff
                }
            }
        }

        return true
    }

    func requestSettingsUpdate() async {
        if let settings = try? await WCSession.default.fetchSettings() {
            self.watchInfo = settings
        }
    }

    func requestContextUpdate(completion: @escaping () -> Void = { }) {
        try? WCSession.default.sendContextRequestMessage(WatchContextRequestUserInfo(), completionHandler: { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let context):
                    self.updateContext(context)
                case .failure:
                    break
                }
                completion()
            }
        })
    }

    func clearOverride() async throws {
        var watchInfoUpdate = self.watchInfo
        watchInfoUpdate.scheduleOverride = nil
        try await WCSession.default.sendSetPreset(presetIdentifier: nil, alertIdentifier: nil)
        watchInfo = watchInfoUpdate
    }

    func activateOverride(_ override: TemporaryScheduleOverride, alertIdentifierToAcknowledge: String? = nil) async throws {
        var watchInfoUpdate = self.watchInfo
        watchInfoUpdate.scheduleOverride = override
        try await WCSession.default.sendSetPreset(presetIdentifier: override.presetId, alertIdentifier: alertIdentifierToAcknowledge)
        watchInfo = watchInfoUpdate
    }

    func acknowledgeAlert(alertIdentifier: String, managerIdentifier: String) async throws {
        self.log.default("Acknowledging alert %{public}@ : %{public}@", alertIdentifier, managerIdentifier)
        try await WCSession.default.sendAcknowledgeAlert(alertIdentifier: alertIdentifier, managerIdentifier: managerIdentifier)
    }

    var selectablePresets: [SelectablePreset] {
        var presets: [SelectablePreset] = []

        let settings = watchInfo.loopSettings

        if let preMealTargetRange = settings.preMealTargetRange {
            presets.append(.preMeal(range: preMealTargetRange))
        }

        presets.append(contentsOf: settings.overridePresets.map { override in
            if override.id.hasPrefix("activity-"), let activityPreset = ActivityPreset(preset: override) {
                return .activity(activityPreset)
            } else {
                return .custom(override)
            }
        })

        ActivityPreset.ActivityType.allCases.forEach { activityType in
            if !settings.overridePresets.contains(where: { $0.id == activityType.id }) {
                presets.append(
                    .activity(
                        ActivityPreset(
                            activityType: activityType,
                            preset: activityType.completeDefaultPreset
                        )
                    )
                )
            }
        }

        return presets
    }

    var listedPresets: [SelectablePreset] {
        selectablePresets.filter { preset in
            if case .activity = preset {
                return watchInfo.showsActivityPresets
            }
            return true
        }
    }

    var glucoseValue: String {
        guard let activeContext = displayContext,
              let glucose = activeContext.glucose,
              let unit = activeContext.displayGlucoseUnit else
        {
            return "- - -"
        }

        let formatter = NumberFormatter.glucoseFormatter(for: unit)

        var glucoseValue: String

        if let glucoseCondition = activeContext.glucoseCondition {
            glucoseValue = glucoseCondition.localizedDescription
        } else {
            glucoseValue = formatter.string(from: glucose.doubleValue(for: unit)) ?? "???"
        }

        let trend = activeContext.glucoseTrend?.symbol ?? ""
        return glucoseValue + trend
    }
}

extension WatchContext {
    /// The phone's context with the state of the watch holding a lent pod over it: every field the
    /// watch has its own value for, an empty one included, so nothing of the phone's dosing state
    /// survives. The rest stay the phone's, so what only the phone knows (its display unit, its CGM,
    /// whether the watch may read the sensor) carries through a loan.
    func overlayWatchState(from watch: WatchContext) {
        creationDate = watch.creationDate
        isOnboardingCompleted = watch.isOnboardingCompleted
        glucose = watch.glucose
        glucoseCondition = watch.glucoseCondition
        glucoseTrend = watch.glucoseTrend
        glucoseTrendRate = watch.glucoseTrendRate
        glucoseDate = watch.glucoseDate
        glucoseIsDisplayOnly = watch.glucoseIsDisplayOnly
        glucoseWasUserEntered = watch.glucoseWasUserEntered
        glucoseSyncIdentifier = watch.glucoseSyncIdentifier
        predictedGlucose = watch.predictedGlucose
        loopLastRunDate = watch.loopLastRunDate
        lastNetTempBasalDose = watch.lastNetTempBasalDose
        lastNetTempBasalDate = watch.lastNetTempBasalDate
        recommendedBolusDose = watch.recommendedBolusDose
        insulinDeliveryState = watch.insulinDeliveryState
        lastManualBolus = watch.lastManualBolus
        potentialCarbEntry = watch.potentialCarbEntry
        cob = watch.cob
        iob = watch.iob
        reservoir = watch.reservoir
        reservoirPercentage = watch.reservoirPercentage
        batteryPercentage = watch.batteryPercentage
        isClosedLoop = watch.isClosedLoop
        deviceIssue = watch.deviceIssue
    }
}

extension LoopDataManager {
    var displayGlucoseUnit: LoopUnit {
        activeContext?.displayGlucoseUnit ?? .milligramsPerDeciliter
    }
}

extension LoopDataManager {

    func generateChartData() async -> GlucoseChartData? {
        guard let activeContext = displayContext else {
            return nil
        }

        var historicalGlucose: [StoredGlucoseSample]?
        do {
            historicalGlucose = try await glucoseStore?.getGlucoseSamples(start: .earliestGlucoseCutoff)
        } catch {
            self.log.error("Failure getting glucose samples: %{public}@", String(describing: error))
        }
        let chartData = GlucoseChartData(
            unit: activeContext.displayGlucoseUnit,
            correctionRange: self.watchInfo.loopSettings.glucoseTargetRangeSchedule,
            scheduleOverride: self.scheduleOverride,
            historicalGlucose: historicalGlucose,
            // With Sport Mode, draw the prediction in any loop mode, as the phone does.
            predictedGlucose: (FeatureFlags.sportModeEnabled || (activeContext.isClosedLoop ?? false)) ? activeContext.predictedGlucose?.values : nil
        )
        return chartData
    }
}
