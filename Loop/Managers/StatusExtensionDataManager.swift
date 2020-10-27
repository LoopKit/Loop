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

        NotificationCenter.default.addObserver(self, selector: #selector(notificationReceived(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)
        NotificationCenter.default.addObserver(self, selector: #selector(notificationReceived(_:)), name: .PumpManagerChanged, object: nil)
       
        // Wait until LoopDataManager has had a chance to initialize itself
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.update()
        }
    }

    fileprivate var defaults: UserDefaults? {
        return UserDefaults.appGroup
    }

    var context: StatusExtensionContext? {
        return defaults?.statusExtensionContext
    }

    @objc private func notificationReceived(_ notification: Notification) {
        update()
    }
    
    private func update() {
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

        let basalDeliveryState = deviceManager.pumpManager?.status.basalDeliveryState

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
                let lastLoopCompleted = manager.lastLoopCompleted
            #endif

            context.lastLoopCompleted = lastLoopCompleted

            // Drop the first element in predictedGlucose because it is the currentGlucose
            // and will have a different interval to the next element
            if let predictedGlucose = state.predictedGlucoseIncludingPendingInsulin?.dropFirst(),
                predictedGlucose.count > 1 {
                let first = predictedGlucose[predictedGlucose.startIndex]
                let second = predictedGlucose[predictedGlucose.startIndex.advanced(by: 1)]
                context.predictedGlucose = PredictedGlucoseContext(
                    values: predictedGlucose.map { $0.quantity.doubleValue(for: glucoseUnit) },
                    unit: glucoseUnit,
                    startDate: first.startDate,
                    interval: second.startDate.timeIntervalSince(first.startDate))
            }

            if let basalDeliveryState = basalDeliveryState,
                let basalSchedule = manager.basalRateScheduleApplyingOverrideHistory,
                let netBasal = basalDeliveryState.getNetBasal(basalSchedule: basalSchedule, settings: manager.settings)
            {
                context.netBasal = NetBasalContext(rate: netBasal.rate, percentage: netBasal.percent, start: netBasal.start, end: netBasal.end)
            }

            context.batteryPercentage = dataManager.pumpManager?.status.pumpBatteryChargeRemaining
            context.reservoirCapacity = dataManager.pumpManager?.pumpReservoirCapacity

            if let sensorInfo = dataManager.sensorState {
                context.sensor = SensorDisplayableContext(
                    isStateValid: sensorInfo.isStateValid,
                    stateDescription: sensorInfo.stateDescription,
                    trendType: sensorInfo.trendType,
                    isLocal: sensorInfo.isLocal
                )
            }
            
            if let pumpManagerHUDProvider = dataManager.pumpManagerHUDProvider {
                context.pumpManagerHUDViewsContext = PumpManagerHUDViewsContext(pumpManagerHUDViewsRawValue: PumpManagerHUDViewsRawValueFromHUDProvider(pumpManagerHUDProvider))
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
