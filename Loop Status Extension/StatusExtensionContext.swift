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

struct ReservoirContext {
    let startDate: Date
    let unitVolume: Double
    let capacity: Int
}

struct LoopContext {
    let dosingEnabled: Bool
    let lastCompleted: Date?
}

struct NetBasalContext {
    let rate: Double
    let percentage: Double
    let startDate: Date
}

struct SensorDisplayableContext: SensorDisplayable {
    let isStateValid: Bool
    let stateDescription: String
    let trendType: GlucoseTrend?
    let isLocal: Bool
}

struct GlucoseContext {
    let quantity: Double
    let startDate: Date
    let sensor: SensorDisplayable?
}

final class StatusExtensionContext: RawRepresentable {
    typealias RawValue = [String: Any]
    private let version = 1
    
    var preferredUnitString: String?
    var latestGlucose: GlucoseContext?
    var reservoir: ReservoirContext?
    var loop: LoopContext?
    var netBasal: NetBasalContext?
    var batteryPercentage: Double?
    var eventualGlucose: Double?
    
    init() { }
    
    required init?(rawValue: RawValue) {
        let raw = rawValue
        
        if let preferredString = raw["preferredUnitString"] as? String,
           let latestValue = raw["latestGlucose_value"] as? Double,
           let startDate = raw["latestGlucose_startDate"] as? Date {
 
            var sensor: SensorDisplayableContext? = nil
            if let state = raw["latestGlucose_sensor_isStateValid"] as? Bool,
               let desc = raw["latestGlucose_sensor_stateDescription"] as? String,
               let local = raw["latestGlucose_sensor_isLocal"] as? Bool {
                
                var glucoseTrend: GlucoseTrend?
                if let trendType = raw["latestGlucose_sensor_trendType"] as? Int {
                    glucoseTrend = GlucoseTrend(rawValue: trendType)
                }
                
                sensor = SensorDisplayableContext(
                    isStateValid: state,
                    stateDescription: desc,
                    trendType: glucoseTrend,
                    isLocal: local)
            }
            
            preferredUnitString = preferredString
            latestGlucose = GlucoseContext(
                quantity: latestValue,
                startDate: startDate,
                sensor: sensor)
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

        raw["preferredUnitString"] = preferredUnitString
        
        if preferredUnitString != nil,
            let glucose = latestGlucose {
            raw["latestGlucose_value"] = glucose.quantity
            raw["latestGlucose_startDate"] = glucose.startDate
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


extension StatusExtensionContext: CustomDebugStringConvertible {
    var debugDescription: String {
        return String(reflecting: rawValue)
    }
}
