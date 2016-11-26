//
//  TodayExtensionDataManager.swift
//  Loop
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit
import UIKit
import CarbKit
import LoopKit

final class TodayExtensionDataManager: NSObject {
    unowned let dataManager: DeviceDataManager
    private var lastContext: TodayExtensionContext?

    init(deviceDataManager: DeviceDataManager) {
        self.dataManager = deviceDataManager
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(update(_:)), name: .LoopDataUpdated, object: deviceDataManager.loopManager)
    }

    @objc private func update(_ notification: Notification) {
        createContext { (context) in
            if let context = context {
                // TODO: check against last context to see if anything changed
                context.save()
                self.lastContext = context
            }
        }
    }

    private func createContext(_ completionHandler: @escaping (_ context: TodayExtensionContext?) -> Void) {
        guard let glucoseStore = self.dataManager.glucoseStore else {
            completionHandler(nil)
            return
        }

        let context = TodayExtensionContext()
        
        #if IOS_SIMULATOR
            // If we're in the simulator, there's a higher likelihood that we don't have
            // a fully configured app. Inject some baseline debug data to let us test the
            // experience. This data will be overwritten by actual data below, if available.
            context.batteryPercentage = 0.25
            context.reservoir = ReservoirValueContext(startDate: Date(), unitVolume: 42.5, capacity: 200)
            context.basal = BasalContext(netRate: 2.1, netPercentage: 0.6, startDate: Date() - TimeInterval(250))
        #endif

        dataManager.loopManager.getLoopStatus {
            (predictedGlucose, _, recommendedTempBasal, lastTempBasal, lastLoopCompleted, _, _, error) in
            let dataManager = self.dataManager
            
            context.loop = LoopContext(
                dosingEnabled: dataManager.loopManager.dosingEnabled,
                lastCompleted: lastLoopCompleted)

            if let glucose = glucoseStore.latestGlucose {
                context.latestGlucose = glucose
            }
            
            let (netBasalRate, netBasalPercentage, basalStartDate) = dataManager.loopManager.calculateNetBasalRate()
            if let rate = netBasalRate, let percentage = netBasalPercentage, let startDate = basalStartDate {
                context.netBasal = NetBasalContext(rate: rate, percentage: percentage, startDate: startDate)
            }
            
            if let reservoir = dataManager.doseStore.lastReservoirValue,
               let capacity = dataManager.pumpState?.pumpModel?.reservoirCapacity {
                context.reservoir = ReservoirValueContext(
                    startDate: reservoir.startDate,
                    unitVolume: reservoir.unitVolume,
                    capacity: capacity)
            }
            
            if let batteryPercentage = dataManager.latestPumpStatusFromMySentry?.batteryRemainingPercent {
                context.batteryPercentage = Double(batteryPercentage) / 100.0
            }
        
            completionHandler(context)
        }
    }
}
