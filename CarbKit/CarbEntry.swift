//
//  CarbEntry.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public struct CarbEntry {
    public let amount: Double
    public let startDate: NSDate
    public let description: String?
    public let absorptionTime: NSTimeInterval?

    let sampleUUID: NSUUID
}
