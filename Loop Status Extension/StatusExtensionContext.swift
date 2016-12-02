//
//  StatusExtensionContext.swift
//  Loop Status Extension
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//
//  This class allows Loop to pass context data to the Loop Status Extension.

import Foundation
import HealthKit
import LoopKit
import InsulinKit

struct ReservoirContext: ReservoirValue {
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

struct GlucoseValueContext: GlucoseValue {
    var quantity: HKQuantity
    var startDate: Date
}

final class StatusExtensionContext: NSObject, RawRepresentable {
    typealias RawValue = [String: Any]
    private let version = 1
    
    var preferredUnit: HKUnit?
    var latestGlucose: GlucoseContext?
    var reservoir: ReservoirContext?
    var loop: LoopContext?
    var netBasal: NetBasalContext?
    var batteryPercentage: Double?
    var eventualGlucose: Double?
    
    override init() {
        super.init()
    }
    
    required init?(rawValue: RawValue) {
        super.init()
        let raw = rawValue
        
        if let preferredUnitString = raw["preferredUnit"] as? String,
           let latestValue = raw["latestGlucose_value"] as? Double,
           let startDate = raw["latestGlucose_startDate"] as? Date {
            
            preferredUnit = HKUnit(from: preferredUnitString)
            latestGlucose = GlucoseContext(
                latest: HKQuantitySample(
                    type: HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bloodGlucose)!,
                    quantity: HKQuantity(unit: HKUnit(from: preferredUnitString), doubleValue: latestValue),
                    start: startDate,
                    end: startDate),
                sensor: nil)
            
            if let state = raw["latestGlucose_sensor_isStateValid"] as? Bool,
               let desc = raw["latestGlucose_sensor_stateDescription"] as? String,
               let local = raw["latestGlucose_sensor_isLocal"] as? Bool {
                
                var glucoseTrend: GlucoseTrend?
                if let trendType = raw["latestGlucose_sensor_trendType"] as? Int {
                    glucoseTrend = GlucoseTrend(rawValue: trendType)
                }
                
                latestGlucose?.sensor = SensorDisplayableContext(
                    isStateValid: state,
                    stateDescription: desc,
                    trendType: glucoseTrend,
                    isLocal: local)
            }
        }
        
        batteryPercentage = raw["batteryPercentage"] as? Double
        
        if let startDate = raw["reservoir_startDate"] as? Date,
           let unitVolume = raw["reservoir_unitVolume"] as? Double,
           let capacity = raw["reservoir_capacity"] as? Int {
            reservoir = ReservoirContext(startDate: startDate, unitVolume: unitVolume, capacity: capacity)
        }

        if let dosingEnabled = raw["loop_dosingEnabled"] as? Bool,
           let lastCompleted = raw["loop_lastCompleted"] as? Date {
            loop = LoopContext(dosingEnabled: dosingEnabled, lastCompleted: lastCompleted)
        }
        
        if let rate = raw["netBasal_rate"] as? Double,
           let percentage = raw["netBasal_percentage"] as? Double,
           let startDate = raw["netBasal_startDate"] as? Date {
            netBasal = NetBasalContext(rate: rate, percentage: percentage, startDate: startDate)
        }
        
        eventualGlucose = raw["eventualGlucose"] as? Double
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [
            "version": version
        ]

        raw["preferredUnit"] = preferredUnit?.unitString
        
        if let glucose = latestGlucose,
           let preferredUnit = preferredUnit {
            raw["latestGlucose_value"] = glucose.latest.quantity.doubleValue(for: preferredUnit)
            raw["latestGlucose_startDate"] = glucose.latest.startDate
        }

        if let sensor = latestGlucose?.sensor {
            raw["latestGlucose_sensor_isStateValid"] = sensor.isStateValid
            raw["latestGlucose_sensor_stateDescription"] = sensor.stateDescription
            raw["latestGlucose_sensor_isLocal"] = sensor.isLocal
            
            if let trendType = sensor.trendType {
                raw["latestGlucose_sensor_trendType"] = trendType.rawValue
            }
        }

        if let batteryPercentage = batteryPercentage {
            raw["batteryPercentage"] = batteryPercentage
        }
        
        if let reservoir = reservoir {
            raw["reservoir_startDate"] = reservoir.startDate
            raw["reservoir_unitVolume"] = reservoir.unitVolume
            raw["reservoir_capacity"] = reservoir.capacity
        }
        
        if let loop = loop {
            raw["loop_dosingEnabled"] = loop.dosingEnabled
            raw["loop_lastCompleted"] = loop.lastCompleted
        }
        
        if let netBasal = netBasal {
            raw["netBasal_rate"] = netBasal.rate
            raw["netBasal_percentage"] = netBasal.percentage
            raw["netBasal_startDate"] = netBasal.startDate
        }
        
        if let eventualGlucose = eventualGlucose {
            raw["eventualGlucose"] = eventualGlucose
        }
        
        return raw
    }
}
