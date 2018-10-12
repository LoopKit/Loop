//
//  WatchComplicationUpdateManager.swift
//  Loop
//
//  Created by Michael Pangburn on 9/23/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import HealthKit
import WatchConnectivity


final class WatchComplicationUpdateManager {
    private unowned let watchManager: WatchDataManager
    private let log: CategoryLogger

    init(watchManager: WatchDataManager) {
        self.watchManager = watchManager
        self.log = watchManager.deviceManager.logger.forCategory("WatchComplicationUpdateManager")
        configureBudgetUpdateObservation()
    }

    var lastComplicationContext: WatchContext?

    func shouldUpdateComplicationImmediately(with context: WatchContext) -> Bool {
        if let lastComplicationContextGlucoseDate = lastComplicationContext?.glucoseDate,
            let newContextGlucoseDate = context.glucoseDate {
            // Ensure a new glucose value has been received.
            guard lastComplicationContextGlucoseDate != newContextGlucoseDate else {
                return false
            }
        }

        if watchManager.settings.wakingHours.isInProgress() {
            return enoughTimePassedToUpdate(with: context) || enoughTrendDriftToUpdate(with: context)
        } else {
            // Ignore trend drift during sleeping hours.
            return enoughTimePassedToUpdate(with: context)
        }
    }

    private func enoughTimePassedToUpdate(with context: WatchContext) -> Bool {
        guard let lastComplicationContext = lastComplicationContext else {
            // No complication update sent yet.
            return true
        }
        return context.creationDate.timeIntervalSince(lastComplicationContext.creationDate) >= complicationUserInfoTransferInterval
    }

    private var complicationUserInfoTransferInterval: TimeInterval {
        let wakingHours = watchManager.settings.wakingHours
        let now = Date()
        if wakingHours.isInProgress(at: now) {
            let nowUntilBudgetReset = DateInterval(start: now, end: WCSession.expectedComplicationUserInfoTransferBudgetResetDate)
            let remainingTimeInWakingHours = wakingHours.durationInProgress(in: nowUntilBudgetReset)
            return remainingTimeInWakingHours / Double(WCSession.default.remainingComplicationUserInfoTransfers + 1)
        } else {
            // Sleeping hours now; send next complication user info transfer at beginning of waking hours.
            return wakingHours.nextStartDate(after: now).timeIntervalSince(now)
        }
    }

    private let minTrendDriftToUpdate = (amount: 20 as Double, unit: HKUnit.milligramsPerDeciliter)

    private func enoughTrendDriftToUpdate(with context: WatchContext) -> Bool {
        guard let lastComplicationUpdateContext = lastComplicationContext else {
            // No complication update sent yet.
            return true
        }

        guard let lastGlucose = lastComplicationUpdateContext.glucose, let newGlucose = context.glucose else {
            // Glucose values unavailable to compare.
            return false
        }

        let normalized = { (glucose: HKQuantity) in glucose.doubleValue(for: self.minTrendDriftToUpdate.unit) }
        let trendDrift = abs(normalized(newGlucose) - normalized(lastGlucose))
        return trendDrift >= minTrendDriftToUpdate.amount
    }

    // MARK: - Logging

    private var budgetUpdateObservationToken: NSKeyValueObservation?

    private var lastLoggedRemainingUpdates: Int?

    deinit {
        budgetUpdateObservationToken?.invalidate()
    }

    private func configureBudgetUpdateObservation() {
        budgetUpdateObservationToken = WCSession.default.observe(\.remainingComplicationUserInfoTransfers, options: [.initial, .new]) { [weak self] session, change in
            guard let self = self else { return }
            if let newValue = change.newValue, newValue != self.lastLoggedRemainingUpdates {
                self.log.debug(["remainingComplicationUserInfoTransfers": newValue])
                self.lastLoggedRemainingUpdates = newValue
            }
        }
    }
}

private extension WCSession {
    static var expectedComplicationUserInfoTransferBudgetResetDate: Date {
        let now = Date()
        if let fiveAM = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 5), matchingPolicy: .nextTime) {
            return fiveAM
        } else {
            return now.addingTimeInterval(.hours(24))
        }
    }
}

extension WatchComplicationUpdateManager: CustomDebugStringConvertible {
    var debugDescription: String {
        return """
        ### WatchComplicationUpdateManager
        * lastComplicationContext: \(String(reflecting: lastComplicationContext))
        * complicationUserInfoTransferInterval: \(String(format: "%.1f", complicationUserInfoTransferInterval.minutes))min
        """
    }
}
