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
import WatchConnectivity
import os.log

class LoopDataManager {
    let glucoseStore: GlucoseStore

    var healthStore: HKHealthStore {
        return glucoseStore.healthStore
    }

    // Main queue only
    var settings = LoopSettings() {
        didSet {
            UserDefaults.standard.loopSettings = settings
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

    init(settings: LoopSettings = UserDefaults.standard.loopSettings ?? LoopSettings()) {
        self.settings = settings

        glucoseStore = GlucoseStore(
            healthStore: HKHealthStore(),
            cacheStore: PersistenceController.controllerInLocalDirectory(),
            cacheLength: .hours(4)
        )
    }
}

extension LoopDataManager {
    static let didUpdateContextNotification = Notification.Name(rawValue: "com.loopkit.notification.ContextUpdated")
}

extension LoopDataManager {
    func updateContext(_ context: WatchContext) {
        dispatchPrecondition(condition: .onQueue(.main))

        if activeContext == nil || context.shouldReplace(activeContext!) {
            activeContext = context
        }
    }

    func addConfirmedBolus(_ bolus: SetBolusUserInfo) {
        dispatchPrecondition(condition: .onQueue(.main))

        activeContext?.iob = (activeContext?.iob ?? 0) + bolus.value
    }

    func addConfirmedCarbEntry(_ entry: CarbEntryUserInfo) {
        dispatchPrecondition(condition: .onQueue(.main))

        activeContext?.cob = (activeContext?.cob ?? 0) + entry.value
    }

    func sendDidUpdateContextNotificationIfNecessary() {
        dispatchPrecondition(condition: .onQueue(.main))

        if needsDidUpdateContextNotification && !WCSession.default.hasContentPending {
            needsDidUpdateContextNotification = false
            NotificationCenter.default.post(name: LoopDataManager.didUpdateContextNotification, object: self)
        }
    }

    @discardableResult
    func requestGlucoseBackfillIfNecessary() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))

        guard lastGlucoseBackfill < .staleGlucoseCutoff else {
            log.default("Skipping glucose backfill request because our latest attempt was %{public}@", String(describing: lastGlucoseBackfill))
            return false
        }

        let latestDate = glucoseStore.latestGlucose?.startDate ?? .earliestGlucoseCutoff
        guard latestDate < .staleGlucoseCutoff else {
            self.log.default("Skipping glucose backfill request because our latest sample date is %{public}@", String(describing: latestDate))
            return false
        }

        lastGlucoseBackfill = Date()
        let userInfo = GlucoseBackfillRequestUserInfo(startDate: latestDate)
        WCSession.default.sendGlucoseBackfillRequestMessage(userInfo) { (result) in
            switch result {
            case .success(let context):
                self.glucoseStore.addGlucose(context.samples) { _ in }
            case .failure:
                // Already logged
                // Reset our last date to immediately retry
                DispatchQueue.main.async {
                    self.lastGlucoseBackfill = .staleGlucoseCutoff
                }
                break
            }
        }

        return true
    }
}

extension LoopDataManager {
    func generateChartData(completion: @escaping (GlucoseChartData?) -> Void) {
        guard let activeContext = activeContext else {
            completion(nil)
            return
        }

        glucoseStore.getCachedGlucoseSamples(start: .earliestGlucoseCutoff) { samples in
            let chartData = GlucoseChartData(
                unit: activeContext.preferredGlucoseUnit,
                correctionRange: self.settings.glucoseTargetRangeSchedule,
                scheduleOverride: self.settings.scheduleOverride,
                historicalGlucose: samples,
                predictedGlucose: activeContext.predictedGlucose?.values
            )
            completion(chartData)
        }
    }
}
