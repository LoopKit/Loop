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

final class TodayExtensionContext: NSObject, RawRepresentable {
    typealias RawValue = [String: Any]
    private let version = 1
    
    var latestGlucose: GlucoseContext?
    var reservoir: ReservoirContext?
    var loop: LoopContext?
    var netBasal: NetBasalContext?
    var batteryPercentage: Double?
    var eventualGlucose: String?
    
    override init() {
        super.init()
    }
    
    required init?(rawValue: RawValue) {
        super.init()
        let raw = rawValue
        
        if let unitString = raw["latestGlucose_unit"] as? String,
           let latestValue = raw["latestGlucose_value"] as? Double,
           let startDate = raw["latestGlucose_startDate"] as? Date {
            latestGlucose = GlucoseContext(
                latest: HKQuantitySample(
                    type: HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bloodGlucose)!,
                    quantity: HKQuantity(unit: HKUnit(from: unitString), doubleValue: latestValue),
                    start: startDate,
                    end: startDate),
                sensor: nil)
            
            if let state = raw["latestGlucose_sensor_isStateValid"] as? Bool,
               let desc = raw["latestGlucose_sensor_stateDescription"] as? String,
               let local = raw["latestGlucose_sensor_isLocal"] as? Bool {
                latestGlucose?.sensor = SensorDisplayableContext(
                    isStateValid: state,
                    stateDescription: desc,
                    trendType: raw["latestGlucose_sensor_trendType"] as? GlucoseTrend,
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
        
        eventualGlucose = raw["eventualGlucose"] as? String
    }
    
    var rawValue: RawValue {
        var raw: RawValue = [
            "version": version
        ]

        if let glucose = latestGlucose {
            // TODO: use the users preferred unit type here
            raw["latestGlucose_value"] = glucose.latest.quantity.doubleValue(for: HKUnit.milligramsPerDeciliterUnit())
            raw["latestGlucose_startDate"] = glucose.latest.startDate
            raw["latestGlucose_unit"] = HKUnit.milligramsPerDeciliterUnit().unitString
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
            raw["netBasal_percentage"] = netBasal.percentage
            raw["netBasal_startDate"] = netBasal.startDate
        }
        
        if let eventualGlucose = eventualGlucose {
            raw["eventualGlucose"] = eventualGlucose
        }
        
        return raw
    }
}
