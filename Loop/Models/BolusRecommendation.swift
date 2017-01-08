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

    init(amount: Double, pendingInsulin: Double? = nil, notice: String? = nil) {
        self.amount = amount
        self.notice = notice
    }
}
