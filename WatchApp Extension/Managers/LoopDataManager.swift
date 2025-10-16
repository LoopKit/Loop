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

    let carbStore: CarbStore

    var glucoseStore: GlucoseStore?

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
        guard let presetId = watchInfo.scheduleOverride?.presetId else {
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
    private(set) var activeContext: WatchContext? {
        didSet {
            rawWatchContext = activeContext?.rawValue
            needsDidUpdateContextNotification = true
            sendDidUpdateContextNotificationIfNecessary()
        }
    }

    private var needsDidUpdateContextNotification: Bool = false

    /// The last attempt to backfill glucose. We use a date because the message timeout is longer
    /// than our desired retry interval, so we allow multiple messages in-flight
    /// Main queue only
    private var lastGlucoseBackfill = Date.distantPast

    public let healthStore: HKHealthStore

    init() {
        healthStore = HKHealthStore()
        let cacheStore = PersistenceController.controllerInLocalDirectory()

        carbStore = CarbStore(
            cacheStore: cacheStore,
            cacheLength: .hours(24),    // Require 24 hours to store recent carbs "since midnight" for CarbEntryListController
            syncVersion: 0
        )

        self.watchInfo = LoopSettingsUserInfo(
            loopSettings: LoopSettings(),
            scheduleOverride: nil
        )
        
        Task {
            glucoseStore = await GlucoseStore(
                cacheStore: cacheStore,
                cacheLength: .hours(4)
            )
        }

        if let rawWatchInfo, let watchInfo = LoopSettingsUserInfo(rawValue: rawWatchInfo) {
            self.watchInfo = watchInfo
        }

        if let rawWatchContext, let watchContext = WatchContext(rawValue: rawWatchContext) {
            self.activeContext = watchContext
        }
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

        guard lastGlucoseBackfill < .staleGlucoseCutoff else {
            log.default("Skipping glucose backfill request because our latest attempt was %{public}@", String(describing: lastGlucoseBackfill))
            return false
        }

        // Loop doesn't read data from HealthKit anymore, and its local watch data is truly ephemeral
        // to power the chart. Fetch enough data to populate the display of the chart.
        let latestDate = max(lastGlucoseBackfill, .earliestGlucoseCutoff)
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
                            preset: activityType.defaultPreset(duration: .finite(.minutes(90)))
                        )
                    )
                )
            }
        }

        return presets
    }

    var glucoseValue: String {
        guard let activeContext = activeContext,
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

extension LoopDataManager {
    var displayGlucoseUnit: LoopUnit {
        activeContext?.displayGlucoseUnit ?? .milligramsPerDeciliter
    }
}

extension LoopDataManager {

    func generateChartData() async -> GlucoseChartData? {
        guard let activeContext = activeContext else {
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
            scheduleOverride: self.watchInfo.scheduleOverride,
            historicalGlucose: historicalGlucose,
            predictedGlucose: (activeContext.isClosedLoop ?? false) ? activeContext.predictedGlucose?.values : nil
        )
        return chartData
    }
}
