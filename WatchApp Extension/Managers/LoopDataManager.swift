//
//  LoopDataManager.swift
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


class LoopDataManager {
    let carbStore: CarbStore

    let glucoseStore: GlucoseStore

    var healthStore: HKHealthStore {
        return glucoseStore.healthStore
    }

    @PersistedProperty(key: "Settings")
    private var rawSettings: LoopSettings.RawValue?

    // Main queue only
    var settings: LoopSettings {
        didSet {
            needsDidUpdateContextNotification = true
            sendDidUpdateContextNotificationIfNecessary()
            rawSettings = settings.rawValue
        }
    }

    // Main queue only
    var supportedBolusVolumes = UserDefaults.standard.supportedBolusVolumes {
        didSet {
            UserDefaults.standard.supportedBolusVolumes = supportedBolusVolumes
            needsDidUpdateContextNotification = true
            sendDidUpdateContextNotificationIfNecessary()
        }
    }

    private let log = OSLog(category: "LoopDataManager")

    // Main queue only
    private(set) var activeContext: WatchContext? {
        didSet {
            needsDidUpdateContextNotification = true
            sendDidUpdateContextNotificationIfNecessary()
        }
    }

    private var needsDidUpdateContextNotification: Bool = false

    /// The last attempt to backfill glucose. We use a date because the message timeout is longer
    /// than our desired retry interval, so we allow multiple messages in-flight
    /// Main queue only
    private var lastGlucoseBackfill = Date.distantPast

    init() {
        let healthStore = HKHealthStore()
        let cacheStore = PersistenceController.controllerInLocalDirectory()

        carbStore = CarbStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: false,
            storeEntriesToHealthKit: false,
            cacheStore: cacheStore,
            cacheLength: .hours(24),    // Require 24 hours to store recent carbs "since midnight" for CarbEntryListController
            defaultAbsorptionTimes: LoopCoreConstants.defaultCarbAbsorptionTimes,
            observationInterval: 0,     // No longer use HealthKit as source of recent carbs
            syncVersion: 0,
            provenanceIdentifier: HKSource.default().bundleIdentifier
        )
        glucoseStore = GlucoseStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: false,
            storeSamplesToHealthKit: false,
            cacheStore: cacheStore,
            cacheLength: .hours(4),
            observationInterval: 0,     // No longer use HealthKit as source of recent glucose
            provenanceIdentifier: HKSource.default().bundleIdentifier
        )

        settings = LoopSettings()

        if let rawSettings = rawSettings, let storedSettings = LoopSettings(rawValue: rawSettings) {
            self.settings = storedSettings
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
                self.glucoseStore.addGlucoseSamples([newGlucoseSample]) { (_) in }
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

    func requestCarbBackfill() {
        dispatchPrecondition(condition: .onQueue(.main))

        let start = min(Calendar.current.startOfDay(for: Date()), Date(timeIntervalSinceNow: -carbStore.maximumAbsorptionTimeInterval))
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
                self.glucoseStore.setSyncGlucoseSamples(context.samples) { (error) in
                    if let error = error {
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
}

extension LoopDataManager {
    var displayGlucoseUnit: HKUnit {
        activeContext?.displayGlucoseUnit ?? .milligramsPerDeciliter
    }
}

extension LoopDataManager {
    func generateChartData(completion: @escaping (GlucoseChartData?) -> Void) {
        guard let activeContext = activeContext else {
            completion(nil)
            return
        }

        glucoseStore.getGlucoseSamples(start: .earliestGlucoseCutoff) { result in
            var historicalGlucose: [StoredGlucoseSample]?
            switch result {
            case .failure(let error):
                self.log.error("Failure getting glucose samples: %{public}@", String(describing: error))
                historicalGlucose = nil
            case .success(let samples):
                historicalGlucose = samples
            }
            let chartData = GlucoseChartData(
                unit: activeContext.displayGlucoseUnit,
                correctionRange: self.settings.glucoseTargetRangeSchedule,
                preMealOverride: self.settings.preMealOverride,
                scheduleOverride: self.settings.scheduleOverride,
                historicalGlucose: historicalGlucose,
                predictedGlucose: (activeContext.isClosedLoop ?? false) ? activeContext.predictedGlucose?.values : nil
            )
            completion(chartData)
        }
    }
}
