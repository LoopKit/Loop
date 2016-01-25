//
//  SampleValue.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public protocol SampleValue {
    var startDate: NSDate { get }
    var quantity: HKQuantity { get }
}
