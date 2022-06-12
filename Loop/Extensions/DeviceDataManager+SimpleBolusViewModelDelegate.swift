//
//  DeviceDataManager+SimpleBolusViewModelDelegate.swift
//  Loop
//
//  Created by Pete Schwamb on 9/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit

extension DeviceDataManager: SimpleBolusViewModelDelegate {
    func addGlucose(_ samples: [NewGlucoseSample], completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void) {
        loopManager.addGlucoseSamples(samples, completion: completion)
    }
    
    func enactBolus(units: Double, activationType: BolusActivationType) {
        enactBolus(units: units, activationType: activationType) { (_) in }
    }
    
    func computeSimpleBolusRecommendation(at date: Date, mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> BolusDosingDecision? {
        return loopManager.generateSimpleBolusRecommendation(at: date, mealCarbs: mealCarbs, manualGlucose: manualGlucose)
    }
    
    var maximumBolus: Double {
        return loopManager.settings.maximumBolus!
    }
    
    var suspendThreshold: HKQuantity {
        return loopManager.settings.suspendThreshold!.quantity
    }
}
