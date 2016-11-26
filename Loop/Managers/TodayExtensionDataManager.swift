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
    unowned let deviceDataManager: DeviceDataManager
    private var lastContext: TodayExtensionContext?

    init(deviceDataManager: DeviceDataManager) {
        self.deviceDataManager = deviceDataManager
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
        guard let glucoseStore = self.deviceDataManager.glucoseStore else {
            completionHandler(nil)
            return
        }

        // let reservoir = deviceDataManager.doseStore.lastReservoirValue
        // let maxBolus = deviceDataManager.maximumBolus

        if let glucose = glucoseStore.latestGlucose {
            deviceDataManager.loopManager.getLoopStatus {
                (predictedGlucose, _, recommendedTempBasal, lastTempBasal, lastLoopCompleted, _, _, error) in

                let context = TodayExtensionContext()
                context.latestGlucose = glucose
                
                completionHandler(context)
            }
        }
    }
}
