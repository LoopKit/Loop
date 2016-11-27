//
//  TodayExtensionContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//
//  This class allows Loop to pass context data to the Today Extension.

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

struct NetBasalContext {
    var rate: Double
    var percentage: Double
    var startDate: Date
}

struct SensorDisplayableContext: SensorDisplayable {
    var isStateValid: Bool
    var stateDescription: String
    var trendType: GlucoseTrend?
    var isLocal: Bool
}

struct GlucoseContext {
    var latest: GlucoseValue
    var sensor: SensorDisplayable?
}

class TodayExtensionContext {
    var data: [String:Any] = [:]
    let storage = UserDefaults(suiteName: "group.com.loudnate.Loop")
    
    var glucose: GlucoseContext? {
        get {
            if data["gcgv"] == nil { return nil }
            
            var sensor: SensorDisplayableContext? = nil
            if data["gcsv"] != nil {
                sensor = SensorDisplayableContext(
                    isStateValid: data["gcsv"] as! Bool,
                    stateDescription: data["gcsd"] as! String,
                    trendType: data["gcst"] as? GlucoseTrend,
                    isLocal: data["gcsl"] as! Bool)
            }
            return GlucoseContext(
                latest: HKQuantitySample(
                    type: HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bloodGlucose)!,
                    quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(),
                                         doubleValue: data["gcgv"] as! Double),
                    start: data["gcgd"] as! Date,
                    end: data["gcgd"] as! Date),
                sensor: sensor)
        }
        set(lgv) {
            data["gcgv"] = lgv?.latest.quantity.doubleValue(for: HKUnit.milligramsPerDeciliterUnit())
            data["gcgd"] = lgv?.latest.startDate
            data["gcsv"] = lgv?.sensor?.isStateValid
            data["gcsd"] = lgv?.sensor?.stateDescription
            data["gcst"] = lgv?.sensor?.trendType
            data["gcsl"] = lgv?.sensor?.isLocal
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
    
    var netBasal: NetBasalContext? {
        get {
            if data["nbr"] == nil { return nil }
            return NetBasalContext(
                rate: data["nbr"] as! Double,
                percentage: data["nbp"] as! Double,
                startDate: data["nbsd"] as! Date)
        }
        set(b) {
            data["nbr"] = b?.rate
            data["nbp"] = b?.percentage
            data["nbsd"] = b?.startDate
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
