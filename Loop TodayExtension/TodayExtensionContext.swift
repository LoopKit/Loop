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
import InsulinKit
import MinimedKit

struct ReservoirValueContext: ReservoirValue {
    var startDate: Date
    var unitVolume: Double
}

struct GlucoseContext {
    var sample: HKQuantitySample
}

// Context passed between Loop and the Today Extension. For now it's all one way
// traffic from Loop.
class TodayExtensionContext {
    var data: [String:Any] = [:]
    let storage = UserDefaults(suiteName: "group.com.loudnate.Loop")
    
    var hasLatestGlucose: Bool = false
    var latestGlucose: GlucoseValue {
        get {
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
    
    var hasBattery: Bool = false
    var batteryPercentage: Double {
        get {
            return data["bp"] as! Double
        }
        set(bp) {
            data["bp"] = bp
        }
    }
    
    var hasReservoir: Bool = false
    var reservoir: ReservoirValue {
        get {
            return ReservoirValueContext(
                startDate: data["rsd"] as! Date,
                unitVolume: data["ruv"] as! Double)
        }
        set(rv) {
            data["rsd"] = rv.startDate
            data["ruv"] = rv.unitVolume
        }
    }
    
    var reservoirCapacity: Int {
        get {
            return data["rc"] as! Int
        }
        set(rc) {
            data["rc"] = rc
        }
    }
    
    var dosingEnabled: Bool {
        get {
            return data["de"] as! Bool
        }
        set(de) {
            data["de"] = de
        }
    }
    
    var hasBasal: Bool = false
    var netBasalRate: Double {
        get      { return data["nbr"] as! Double }
        set(de)  { data["nbr"] = de              }
    }
    var netBasalPercent: Double {
        get      { return data["nbp"] as! Double }
        set(dp)  { data["nbp"] = dp              }
    }
    var basalStartDate: Date {
        get      { return data["bsd"] as! Date   }
        set(bsd) { data["bsd"] = bsd             }
    }
    
    func save() {
        storage?.set(data, forKey: "TodayExtensionContext")
    }
    
    func load() -> TodayExtensionContext? {
        if let data = storage?.object(forKey: "TodayExtensionContext") as! [String:Any]? {
            self.data = data
            self.hasLatestGlucose = data["gv"] != nil
            self.hasBattery = data["bp"] != nil
            self.hasReservoir = data["ruv"] != nil
            self.hasBasal = data["nbr"] != nil
            return self
        }
        return nil
    }
}
