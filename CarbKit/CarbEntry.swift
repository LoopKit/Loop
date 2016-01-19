//
//  CarbEntry.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public protocol CarbEntry: SampleValue {
    var foodType: String? { get }
    var absorptionTime: NSTimeInterval? { get }
    var createdByCurrentApp: Bool { get }
}
