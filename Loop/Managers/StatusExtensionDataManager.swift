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
        self.dataManager.glucoseStore?.preferredUnit() { (unit, error) in
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
        guard let glucoseStore = self.dataManager.glucoseStore else {
            completionHandler(nil)
            return
        }
        
        dataManager.loopManager.getLoopStatus {
            (predictedGlucose, _, recommendedTempBasal, lastTempBasal, lastLoopCompleted, _, _, error) in

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
                context.eventualGlucose = GlucoseContext(
                    value: 89.123,
                    unit: HKUnit.milligramsPerDeciliterUnit(),
                    startDate: Date(timeIntervalSinceNow: TimeInterval(hours: 4)),
                    sensor: nil
                )

                let lastLoopCompleted = Date(timeIntervalSinceNow: -TimeInterval(minutes: 0))
            #else
                guard error == nil else {
                    // TODO: unclear how to handle the error here properly.
                    completionHandler(nil)
                    return
                }
            #endif

            context.loop = LoopContext(
                dosingEnabled: dataManager.loopManager.dosingEnabled,
                lastCompleted: lastLoopCompleted)

            if let glucose = glucoseStore.latestGlucose {
                context.latestGlucose = GlucoseContext(
                    value: glucose.quantity.doubleValue(for: glucoseUnit),
                    unit: glucoseUnit,
                    startDate: glucose.startDate,
                    sensor: dataManager.sensorInfo != nil ? SensorDisplayableContext(dataManager.sensorInfo!) : nil
                )
            }
            
            if let lastNetBasal = dataManager.loopManager.lastNetBasal {
                context.netBasal = NetBasalContext(rate: lastNetBasal.rate, percentage: lastNetBasal.percent, startDate: lastNetBasal.startDate)
            }
            
            if let reservoir = dataManager.doseStore.lastReservoirValue,
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
        
            if let lastPoint = predictedGlucose?.last {
                context.eventualGlucose = GlucoseContext(
                    value: lastPoint.quantity.doubleValue(for: glucoseUnit),
                    unit: glucoseUnit,
                    startDate: lastPoint.startDate,
                    sensor: nil
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
