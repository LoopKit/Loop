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

final class StatusExtensionDataManager: NSObject {
    unowned let dataManager: DeviceDataManager
    private var lastContext: StatusExtensionContext?

    init(deviceDataManager: DeviceDataManager) {
        self.dataManager = deviceDataManager
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(update(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)
    }

    @objc private func update(_ notification: Notification) {
        createContext { (context) in
            if let context = context {
                UserDefaults.shared()?.statusExtensionContext = context
                self.lastContext = context
            }
        }
    }

    private func createContext(_ completionHandler: @escaping (_ context: StatusExtensionContext?) -> Void) {
        guard let glucoseStore = self.dataManager.glucoseStore else {
            completionHandler(nil)
            return
        }

        dataManager.loopManager.getLoopStatus {
            (predictedGlucose, _, recommendedTempBasal, lastTempBasal, lastLoopCompleted, _, _, error) in
            
            let context = StatusExtensionContext()
        
            #if IOS_SIMULATOR
                // If we're in the simulator, there's a higher likelihood that we don't have
                // a fully configured app. Inject some baseline debug data to let us test the
                // experience. This data will be overwritten by actual data below, if available.
                context.batteryPercentage = 0.25
                context.reservoir = ReservoirContext(startDate: Date(), unitVolume: 42.5, capacity: 200)
                context.netBasal = NetBasalContext(rate: 2.1, percentage: 0.6, startDate: Date() - TimeInterval(250))
                context.eventualGlucose = String(
                    format: NSLocalizedString("Eventually %@", comment: ""),
                    String(describing: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: 119.0)))
            #endif

            let dataManager = self.dataManager
            
            context.loop = LoopContext(
                dosingEnabled: dataManager.loopManager.dosingEnabled,
                lastCompleted: lastLoopCompleted)

            if let glucose = glucoseStore.latestGlucose {
                context.latestGlucose = GlucoseContext(
                    latest: glucose,
                    sensor: dataManager.sensorInfo)
            }
            
            let (netBasalRate, netBasalPercentage, basalStartDate) = dataManager.loopManager.calculateNetBasalRate()
            if let rate = netBasalRate, let percentage = netBasalPercentage, let startDate = basalStartDate {
                context.netBasal = NetBasalContext(rate: rate, percentage: percentage, startDate: startDate)
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
                context.eventualGlucose = String(
                    format: NSLocalizedString("Eventually %@", comment: "The subtitle format describing eventual glucose. (1: localized glucose value description)"),
                    String(describing: lastPoint.quantity))
            }
            
            completionHandler(context)
        }
    }
}
