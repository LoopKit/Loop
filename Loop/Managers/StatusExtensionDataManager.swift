//
//  StatusExtensionDataManager.swift
//  Loop
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit
import UIKit
import LoopKit


final class StatusExtensionDataManager {
    unowned let deviceManager: DeviceDataManager

    init(deviceDataManager: DeviceDataManager) {
        self.deviceManager = deviceDataManager

        NotificationCenter.default.addObserver(self, selector: #selector(update(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)
    }

    fileprivate var defaults: UserDefaults? {
        return UserDefaults.appGroup
    }

    var context: StatusExtensionContext? {
        return defaults?.statusExtensionContext
    }

    @objc private func update(_ notification: Notification) {
        guard let unit = (deviceManager.loopManager.glucoseStore.preferredUnit ?? context?.predictedGlucose?.unit) else {
            return
        }

        createContext(glucoseUnit: unit) { (context) in
            if let context = context {
                self.defaults?.statusExtensionContext = context
            }
        }
    }

    private func createContext(glucoseUnit: HKUnit, _ completionHandler: @escaping (_ context: StatusExtensionContext?) -> Void) {
        deviceManager.loopManager.getLoopState { (manager, state) in
            let dataManager = self.deviceManager
            var context = StatusExtensionContext()
        
            #if IOS_SIMULATOR
                // If we're in the simulator, there's a higher likelihood that we don't have
                // a fully configured app. Inject some baseline debug data to let us test the
                // experience. This data will be overwritten by actual data below, if available.
                context.batteryPercentage = 0.25
                context.netBasal = NetBasalContext(
                    rate: 2.1,
                    percentage: 0.6,
                    start:
                    Date(timeIntervalSinceNow: -250),
                    end: Date(timeIntervalSinceNow: .minutes(30))
                )
                context.predictedGlucose = PredictedGlucoseContext(
                    values: (1...36).map { 89.123 + Double($0 * 5) }, // 3 hours of linear data
                    unit: HKUnit.milligramsPerDeciliter,
                    startDate: Date(),
                    interval: TimeInterval(minutes: 5))

                let lastLoopCompleted = Date(timeIntervalSinceNow: -TimeInterval(minutes: 0))
            #else
                guard state.error == nil else {
                    // TODO: unclear how to handle the error here properly.
                    completionHandler(nil)
                    return
                }
                let lastLoopCompleted = manager.lastLoopCompleted
            #endif

            context.lastLoopCompleted = lastLoopCompleted

            // Drop the first element in predictedGlucose because it is the currentGlucose
            // and will have a different interval to the next element
            if let predictedGlucose = state.predictedGlucose?.dropFirst(),
                predictedGlucose.count > 1 {
                let first = predictedGlucose[predictedGlucose.startIndex]
                let second = predictedGlucose[predictedGlucose.startIndex.advanced(by: 1)]
                context.predictedGlucose = PredictedGlucoseContext(
                    values: predictedGlucose.map { $0.quantity.doubleValue(for: glucoseUnit) },
                    unit: glucoseUnit,
                    startDate: first.startDate,
                    interval: second.startDate.timeIntervalSince(first.startDate))
            }

            let date = state.lastTempBasal?.startDate ?? Date()
            if let scheduledBasal = manager.basalRateScheduleApplyingOverrideIfActive?.between(start: date, end: date).first {
                let netBasal = NetBasal(
                    lastTempBasal: state.lastTempBasal,
                    maxBasal: manager.settings.maximumBasalRatePerHour,
                    scheduledBasal: scheduledBasal
                )

                context.netBasal = NetBasalContext(rate: netBasal.rate, percentage: netBasal.percent, start: netBasal.start, end: netBasal.end)
            }

            context.batteryPercentage = dataManager.pumpManager?.pumpBatteryChargeRemaining
            context.reservoirCapacity = dataManager.pumpManager?.pumpReservoirCapacity

            if let sensorInfo = dataManager.cgmManager?.sensorState {
                context.sensor = SensorDisplayableContext(
                    isStateValid: sensorInfo.isStateValid,
                    stateDescription: sensorInfo.stateDescription,
                    trendType: sensorInfo.trendType,
                    isLocal: sensorInfo.isLocal
                )
            }

            completionHandler(context)
        }
    }
}


extension StatusExtensionDataManager: CustomDebugStringConvertible {
    var debugDescription: String {
        return [
            "## StatusExtensionDataManager",
            "appGroupName: \(Bundle.main.appGroupSuiteName)",
            "statusExtensionContext: \(String(reflecting: defaults?.statusExtensionContext))",
            ""
        ].joined(separator: "\n")
    }
}
