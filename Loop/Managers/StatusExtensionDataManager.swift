//
//  StatusExtensionDataManager.swift
//  Loop
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit
import UIKit
import CarbKit
import LoopKit


final class StatusExtensionDataManager {
    unowned let dataManager: DeviceDataManager

    init(deviceDataManager: DeviceDataManager) {
        self.dataManager = deviceDataManager

        NotificationCenter.default.addObserver(self, selector: #selector(update(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)
    }

    fileprivate var defaults: UserDefaults? {
        return UserDefaults(suiteName: Bundle.main.appGroupSuiteName)
    }

    var context: StatusExtensionContext? {
        return defaults?.statusExtensionContext
    }

    @objc private func update(_ notification: Notification) {
        self.dataManager.loopManager.glucoseStore.preferredUnit() { (unit, error) in
            if error == nil, let unit = unit {
                self.createContext(glucoseUnit: unit) { (context) in
                    if let context = context {
                        self.defaults?.statusExtensionContext = context
                    }
                }
            }
        }
    }

    private func createContext(glucoseUnit: HKUnit, _ completionHandler: @escaping (_ context: StatusExtensionContext?) -> Void) {
        dataManager.loopManager.getLoopState { (manager, state) in
            let dataManager = self.dataManager
            var context = StatusExtensionContext()
        
            #if IOS_SIMULATOR
                // If we're in the simulator, there's a higher likelihood that we don't have
                // a fully configured app. Inject some baseline debug data to let us test the
                // experience. This data will be overwritten by actual data below, if available.
                context.batteryPercentage = 0.25
                context.reservoir = ReservoirContext(startDate: Date(), unitVolume: 160, capacity: 300)
                context.netBasal = NetBasalContext(
                    rate: 2.1,
                    percentage: 0.6,
                    startDate:
                    Date(timeIntervalSinceNow: -250)
                )
                context.predictedGlucose = PredictedGlucoseContext(
                    values: (1...36).map { 89.123 + Double($0 * 5) }, // 3 hours of linear data
                    unit: HKUnit.milligramsPerDeciliter(),
                    startDate: Date(),
                    interval: TimeInterval(minutes: 5))

                let lastLoopCompleted = Date(timeIntervalSinceNow: -TimeInterval(minutes: 0))
            #else
                guard state.error == nil else {
                    // TODO: unclear how to handle the error here properly.
                    completionHandler(nil)
                    return
                }
                let lastLoopCompleted = state.lastLoopCompleted
            #endif

            context.loop = LoopContext(
                dosingEnabled: manager.settings.dosingEnabled,
                lastCompleted: lastLoopCompleted
            )

            let updateGroup = DispatchGroup()

            // We can only access the last 30 minutes of data if the device is locked.
            // Cap it there so that we have a consistent view in the widget.
            let chartStartDate = Date().addingTimeInterval(TimeInterval(minutes: -30))
            let chartEndDate = Date().addingTimeInterval(TimeInterval(hours: 3))

            updateGroup.enter()
            manager.glucoseStore.getCachedGlucoseValues(start: chartStartDate, end: Date()) {
                (values) in
                context.glucose = values.map({
                    return GlucoseContext(
                        value: $0.quantity.doubleValue(for: glucoseUnit),
                        unit: glucoseUnit,
                        startDate: $0.startDate
                    )
                })
                updateGroup.leave()
            }

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
            if let scheduledBasal = manager.basalRateSchedule?.between(start: date, end: date).first {
                let netBasal = NetBasal(
                    lastTempBasal: state.lastTempBasal,
                    maxBasal: manager.settings.maximumBasalRatePerHour,
                    scheduledBasal: scheduledBasal
                )

                context.netBasal = NetBasalContext(rate: netBasal.rate, percentage: netBasal.percent, startDate: netBasal.startDate)
            }
            
            if let reservoir = manager.doseStore.lastReservoirValue,
               let capacity = dataManager.pumpState?.pumpModel?.reservoirCapacity {
                context.reservoir = ReservoirContext(
                    startDate: reservoir.startDate,
                    unitVolume: reservoir.unitVolume,
                    capacity: capacity
                )
            }
            
            if let batteryPercentage = dataManager.pumpBatteryChargeRemaining {
                context.batteryPercentage = batteryPercentage
            }
        
            if let targetRanges = manager.settings.glucoseTargetRangeSchedule {
                context.targetRanges = targetRanges.between(start: chartStartDate, end: chartEndDate)
                    .map {
                        return DatedRangeContext(
                            startDate: $0.startDate,
                            endDate: $0.endDate,
                            minValue: $0.value.minValue,
                            maxValue: $0.value.maxValue
                        )
                    }

                if let override = targetRanges.temporaryOverride {
                    context.temporaryOverride = DatedRangeContext(
                        startDate: override.startDate,
                        endDate: override.endDate,
                        minValue: override.value.minValue,
                        maxValue: override.value.maxValue)
                }
            }

            if let sensorInfo = dataManager.sensorInfo {
                context.sensor = SensorDisplayableContext(
                    isStateValid: sensorInfo.isStateValid,
                    stateDescription: sensorInfo.stateDescription,
                    trendType: sensorInfo.trendType,
                    isLocal: sensorInfo.isLocal)
            }

            updateGroup.notify(queue: DispatchQueue.global(qos: .background)) {
                completionHandler(context)
            }
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
