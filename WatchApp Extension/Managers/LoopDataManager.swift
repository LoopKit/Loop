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


class LoopDataManager {
    let carbStore: CarbStore

    var glucoseStore: GlucoseStore!

    @PersistedProperty(key: "Settings")
    private var rawWatchInfo: LoopSettingsUserInfo.RawValue?

    // Main queue only
    var watchInfo: LoopSettingsUserInfo {
        didSet {
            needsDidUpdateContextNotification = true
            sendDidUpdateContextNotificationIfNecessary()
            rawWatchInfo = watchInfo.rawValue
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

    private let log = OSLog(category: "LoopDosingManager")

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
            scheduleOverride: nil,
            preMealOverride: nil
        )
        
        Task {
            glucoseStore = await GlucoseStore(
                cacheStore: cacheStore,
                cacheLength: .hours(4)
            )
        }

        if let rawWatchInfo = rawWatchInfo, let watchInfo = LoopSettingsUserInfo(rawValue: rawWatchInfo) {
            self.watchInfo = watchInfo
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
                    try? await self.glucoseStore.addGlucoseSamples([newGlucoseSample])
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
                        try await self.glucoseStore.setSyncGlucoseSamples(context.samples)
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

        Task {
            var historicalGlucose: [StoredGlucoseSample]?
            do {
                historicalGlucose = try await glucoseStore.getGlucoseSamples(start: .earliestGlucoseCutoff)
            } catch {
                self.log.error("Failure getting glucose samples: %{public}@", String(describing: error))
            }
            let chartData = GlucoseChartData(
                unit: activeContext.displayGlucoseUnit,
                correctionRange: self.watchInfo.loopSettings.glucoseTargetRangeSchedule,
                preMealOverride: self.watchInfo.preMealOverride,
                scheduleOverride: self.watchInfo.scheduleOverride,
                historicalGlucose: historicalGlucose,
                predictedGlucose: (activeContext.isClosedLoop ?? false) ? activeContext.predictedGlucose?.values : nil
            )
            completion(chartData)
        }
    }
}
