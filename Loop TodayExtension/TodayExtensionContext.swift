//
//  TodayExtensionContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

class TodayExtensionContext {
    var data: [String:Any] = [:]
    let storage = UserDefaults(suiteName: "group.com.loudnate.Loop")
    
    var latestGlucose: GlucoseValue {
        get {
            // TODO: replace hardcoded mg/dL here with the user's preferred units
            return HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bloodGlucose)!,
                quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(),
                                     doubleValue: data["gv"] as! Double),
                start: data["gd"] as! Date,
                end: data["gd"] as! Date)
        }
        set(lgv) {
            data["gd"] = lgv.startDate
            data["gv"] = lgv.quantity.doubleValue(for: HKUnit.milligramsPerDeciliterUnit())
        }
    }
    
    func save() {
        storage?.set(data, forKey: "TodayExtensionContext")
    }
    
    func load() -> TodayExtensionContext? {
        if let data = storage?.object(forKey: "TodayExtensionContext") as! [String:Any]? {
            self.data = data
            return self
        }
        return nil
    }
}
