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
    var capacity: Int
}

struct LoopContext {
    var dosingEnabled: Bool
    var lastCompleted: Date?
}

struct BasalContext {
    var netRate: Double
    var netPercentage: Double
    var startDate: Date
}

// Context passed between Loop and the Today Extension. For now it's all one way
// traffic from Loop.
class TodayExtensionContext {
    var data: [String:Any] = [:]
    let storage = UserDefaults(suiteName: "group.com.loudnate.Loop")
    
    var latestGlucose: GlucoseValue? {
        get {
            if data["gv"] == nil { return nil }
            return HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bloodGlucose)!,
                quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(),
                                     doubleValue: data["gv"] as! Double),
                start: data["gd"] as! Date,
                end: data["gd"] as! Date)
        }
        set(lgv) {
            data["gd"] = lgv?.startDate
            data["gv"] = lgv?.quantity.doubleValue(for: HKUnit.milligramsPerDeciliterUnit())
        }
    }
    
    var batteryPercentage: Double? {
        get {
            if data["bp"] == nil { return nil }
            return data["bp"] as? Double
        }
        set(bp) {
            data["bp"] = bp
        }
    }
    
    var reservoir: ReservoirValueContext? {
        get {
            if data["rsd"] == nil { return nil }
            return ReservoirValueContext(
                startDate: data["rsd"] as! Date,
                unitVolume: data["ruv"] as! Double,
                capacity: data["rc"] as! Int)
        }
        set(rvc) {
            data["rsd"] = rvc?.startDate
            data["ruv"] = rvc?.unitVolume
            data["rc"] = rvc?.capacity
        }
    }
    
    var loop: LoopContext? {
        get {
            if data["lde"] == nil { return nil }
            return LoopContext(
                dosingEnabled: data["lde"] as! Bool,
                lastCompleted: data["llc"] as! Date?)
        }
        set(l) {
            data["lde"] = l?.dosingEnabled
            data["llc"] = l?.lastCompleted
        }
    }
    
    var basal: BasalContext? {
        get {
            if data["bnr"] == nil { return nil }
            return BasalContext(
                netRate: data["bnr"] as! Double,
                netPercentage: data["bnp"] as! Double,
                startDate: data["bsd"] as! Date)
        }
        set(b) {
            data["bnr"] = b?.netRate
            data["bnp"] = b?.netPercentage
            data["bsd"] = b?.startDate
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
