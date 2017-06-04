//
//  NetBasal.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/7/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import InsulinKit
import LoopKit

struct NetBasal {
    let rate: Double
    let percent: Double
    let startDate: Date
    
    init(lastTempBasal: DoseEntry?, maxBasal: Double?, scheduledBasal: AbsoluteScheduleValue<Double>) {
        if let lastTempBasal = lastTempBasal, lastTempBasal.endDate > Date(), let maxBasal = maxBasal {
            rate = lastTempBasal.value - scheduledBasal.value
            startDate = lastTempBasal.startDate
            
            if rate < 0 {
                percent = rate / scheduledBasal.value
            } else {
                percent = rate / (maxBasal - scheduledBasal.value)
            }
        } else {
            rate = 0
            percent = 0
            
            if let lastTempBasal = lastTempBasal, lastTempBasal.endDate > scheduledBasal.startDate {
                startDate = lastTempBasal.endDate
            } else {
                startDate = scheduledBasal.startDate
            }
        }
    }
}
