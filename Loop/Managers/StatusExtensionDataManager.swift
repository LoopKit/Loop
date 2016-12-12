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

    @objc private func update(_ notification: Notification) {

        self.dataManager.glucoseStore?.preferredUnit() { (unit, error) in
            if error == nil, let unit = unit {
                self.createContext(unit) { (context) in
                    if let context = context {
                        UserDefaults(suiteName: Bundle.main.appGroupSuiteName)?.statusExtensionContext = context
                    }
                }
            }
        }
    }

    private func createContext(_ preferredUnit: HKUnit, _ completionHandler: @escaping (_ context: StatusExtensionContext?) -> Void) {
        guard let glucoseStore = self.dataManager.glucoseStore else {
            completionHandler(nil)
            return
        }
        
        dataManager.loopManager.getLoopStatus {
            (predictedGlucose, _, recommendedTempBasal, lastTempBasal, lastLoopCompleted, _, _, error) in
            
            if error != nil {
                // TODO: unclear how to handle the error here properly.
                completionHandler(nil)
            }
            
            let dataManager = self.dataManager
            let context = StatusExtensionContext()
        
            #if IOS_SIMULATOR
                // If we're in the simulator, there's a higher likelihood that we don't have
                // a fully configured app. Inject some baseline debug data to let us test the
                // experience. This data will be overwritten by actual data below, if available.
                context.batteryPercentage = 0.25
                context.reservoir = ReservoirContext(startDate: Date(), unitVolume: 42.5, capacity: 200)
                context.netBasal = NetBasalContext(rate: 2.1, percentage: 0.6, startDate: Date() - TimeInterval(250))
                context.eventualGlucose = 119.123
            #endif

            context.preferredUnitDisplayString = preferredUnit.glucoseUnitDisplayString
            context.loop = LoopContext(
                dosingEnabled: dataManager.loopManager.dosingEnabled,
                lastCompleted: lastLoopCompleted)

            if let glucose = glucoseStore.latestGlucose {
                // It's possible that the unit came in nil and we defaulted to mg/dL. To account for that case,
                // convert the latest glucose to those units just to be sure.
                context.latestGlucose = GlucoseContext(
                    quantity: glucose.quantity.doubleValue(for: preferredUnit),
                    startDate: glucose.startDate,
                    sensor: dataManager.sensorInfo)
            }
            
            if let lastNetBasal = dataManager.loopManager.lastNetBasal {
                context.netBasal = NetBasalContext(rate: lastNetBasal.rate, percentage: lastNetBasal.percent, startDate: lastNetBasal.startDate)
            }
            
            if let reservoir = dataManager.doseStore.lastReservoirValue,
               let capacity = dataManager.pumpState?.pumpModel?.reservoirCapacity {
                context.reservoir = ReservoirContext(
                    startDate: reservoir.startDate,
                    unitVolume: reservoir.unitVolume,
                    capacity: capacity)
            }
            
            if let batteryPercentage = dataManager.latestPumpStatusFromMySentry?.batteryRemainingPercent {
                context.batteryPercentage = Double(batteryPercentage) / 100.0
            }
        
            if let lastPoint = predictedGlucose?.last {
                context.eventualGlucose = lastPoint.quantity.doubleValue(for: preferredUnit)
            }
            
            completionHandler(context)
        }
    }
}
