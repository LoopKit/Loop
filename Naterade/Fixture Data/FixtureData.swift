//
//  SampleData.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import GlucoseKit
import HealthKit
import InsulinKit
import LoopKit


struct GlucoseFixtureValue: GlucoseValue {
    let startDate: NSDate
    let quantity: HKQuantity
}


struct FixtureData {
    private typealias JSONDictionary = [String: AnyObject]

    private static var dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

    private static func loadFixture<T>(resourceName: String) -> T {
        let path = NSBundle.mainBundle().pathForResource(resourceName, ofType: "json")!
        return try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! T
    }

    static var recentGlucoseData: [GlucoseValue] {
        let glucose: [JSONDictionary] = loadFixture("clean_glucose")

        return glucose.reverse().map({ (entry) -> GlucoseValue in
            return GlucoseFixtureValue(
                startDate: dateFormatter.dateFromString(entry["display_time"] as! String)!,
                quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: entry["glucose"] as! Double)
            )
        })
    }

    static var predictedGlucoseData: [GlucoseValue] {
        let glucose: [JSONDictionary] = loadFixture("predict_glucose")

        return glucose.map({ (entry) -> GlucoseValue in
            return GlucoseFixtureValue(startDate: dateFormatter.dateFromString(entry["date"] as! String)!, quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: entry["amount"] as! Double))
        })
    }

    static var recentIOBData: [InsulinValue] {
        let values: [JSONDictionary] = loadFixture("iob")

        return values.map({ (entry) in
            return InsulinValue(
                startDate: dateFormatter.dateFromString(entry["date"] as! String)!,
                value: entry["amount"] as! Double
            )
        })
    }

    static var recentDoseData: [DoseEntry] {
        let history: [JSONDictionary] = loadFixture("normalize_history")

        return history.reverse().flatMap({ (entry) -> DoseEntry? in
            let unitString = entry["unit"] as! String
            let unit: DoseUnit

            switch unitString {
            case "U/hour":
                unit = .UnitsPerHour
            case "U":
                unit = .Units
            default:
                return nil
            }

            return DoseEntry(startDate: dateFormatter.dateFromString(entry["start_at"] as! String)!, endDate: dateFormatter.dateFromString(entry["end_at"] as! String)!, value: entry["amount"] as! Double, unit: unit, description: nil)
        })
    }
}