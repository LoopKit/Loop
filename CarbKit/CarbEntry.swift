//
//  CarbEntry.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public protocol CarbEntry: SampleValue {
    var value: Double { get }
    var startDate: NSDate { get }
    var unit: HKUnit { get }
    var foodType: String? { get }
    var absorptionTime: NSTimeInterval? { get }
    var createdByCurrentApp: Bool { get }
}
