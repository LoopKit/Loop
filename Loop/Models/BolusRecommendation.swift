//
//  BolusRecommendation.swift
//  Loop
//
//  Created by Pete Schwamb on 1/2/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

struct BolusRecommendation {
    let amount: Double
    let notice: String?
    let minBG: GlucoseValue?
    let eventualBG: GlucoseValue?
    let pendingInsulin: Double?
    
    init(amount: Double, notice: String? = nil, minBG: GlucoseValue? = nil, eventualBG: GlucoseValue? = nil, pendingInsulin: Double? = nil) {
        self.amount = amount
        self.notice = notice
        self.minBG = minBG
        self.eventualBG = eventualBG
        self.pendingInsulin = pendingInsulin
    }
}
