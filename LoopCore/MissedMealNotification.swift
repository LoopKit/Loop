//
//  MissedMealNotification.swift
//  Loop
//
//  Created by Anna Quinlan on 11/18/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

/// Information about a missed meal notification
public struct MissedMealNotification: Equatable, Codable {
    public let deliveryTime: Date
    public let carbAmount: Double
    
    public init(deliveryTime: Date, carbAmount: Double) {
        self.deliveryTime = deliveryTime
        self.carbAmount = carbAmount
    }
}
