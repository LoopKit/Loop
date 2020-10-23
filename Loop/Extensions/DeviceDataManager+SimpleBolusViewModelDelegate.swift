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
    func addGlucose(_ samples: [NewGlucoseSample], completion: @escaping (Error?) -> Void) {
        loopManager.addGlucoseSamples(samples) { (result) in
            switch result {
            case .failure(let error):
                completion(error)
            case .success:
                completion(nil)
            }
        }
    }
    
    func enactBolus(units: Double, at startDate: Date) {
        enactBolus(units: units, at: startDate) { (_) in }
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
