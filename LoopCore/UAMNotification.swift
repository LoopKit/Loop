//
//  UAMNotification.swift
//  Loop
//
//  Created by Anna Quinlan on 11/18/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

/// Information about an unannounced meal notification
public struct UAMNotification: Equatable, Codable {
    public let deliveryTime: Date
    public let carbAmount: Double
    
    public init(deliveryTime: Date, carbAmount: Double) {
        self.deliveryTime = deliveryTime
        self.carbAmount = carbAmount
    }
}
