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


struct SampleData {
    private typealias JSONDictionary = [String: AnyObject]

    private static func loadFixture<T>(resourceName: String) -> T {
        let path = NSBundle.mainBundle().pathForResource(resourceName, ofType: "json")!
        return try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! T
    }

    static var recentGlucoseData: [GlucoseValue] {
        let glucose: [JSONDictionary] = loadFixture("clean_glucose")
        let dateFormatter = NSDateFormatter.ISO8601LocalTimeDateFormatter()

        return glucose.reverse().map({ (entry) -> GlucoseValue in
            return GlucoseValue(
                startDate: dateFormatter.dateFromString(entry["display_time"] as! String)!,
                quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: entry["glucose"] as! Double)
            )
        })
    }
}