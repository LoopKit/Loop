    //
//  DoseEnactor.swift
//  Loop
//
//  Created by Pete Schwamb on 7/30/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

class DoseEnactor {
    
    fileprivate let dosingQueue: DispatchQueue = DispatchQueue(label: "com.loopkit.DeviceManagerDosingQueue", qos: .utility)
    
    private let log = DiagnosticLog(category: "DoseEnactor")

    func enact(recommendation: AutomaticDoseRecommendation, with pumpManager: PumpManager, completion: @escaping (PumpManagerError?) -> Void) {
        
        dosingQueue.async {
            let doseDispatchGroup = DispatchGroup()

            var tempBasalError: PumpManagerError? = nil
            var bolusError: PumpManagerError? = nil

            if let basalAdjustment = recommendation.basalAdjustment {
                self.log.default("Enacting recommend basal change")

                doseDispatchGroup.enter()
                pumpManager.enactTempBasal(unitsPerHour: basalAdjustment.unitsPerHour, for: basalAdjustment.duration, completion: { error in
                    if let error = error {
                        tempBasalError = error
                    }
                    doseDispatchGroup.leave()
                })
            }

            doseDispatchGroup.wait()

            guard tempBasalError == nil else {
                completion(tempBasalError)
                return
            }
            
            if let bolusUnits = recommendation.bolusUnits, bolusUnits > 0 {
                self.log.default("Enacting recommended bolus dose")
                doseDispatchGroup.enter()
                pumpManager.enactBolus(units: bolusUnits, activationType: .automatic) { (error) in
                    if let error = error {
                        bolusError = error
                    } else {
                        self.log.default("PumpManager successfully issued bolus command")
                    }
                    doseDispatchGroup.leave()
                }
            }
            doseDispatchGroup.wait()
            completion(bolusError)
        }
    }
}
