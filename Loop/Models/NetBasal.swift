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
    let start: Date
    let end: Date
    
    init(lastTempBasal: DoseEntry?, maxBasal: Double?, scheduledBasal: AbsoluteScheduleValue<Double>) {
        if let lastTempBasal = lastTempBasal, lastTempBasal.endDate > Date(), let maxBasal = maxBasal {
            rate = lastTempBasal.unitsPerHour - scheduledBasal.value
            start = lastTempBasal.startDate
            end = lastTempBasal.endDate
            
            if rate < 0 {
                percent = rate / scheduledBasal.value
            } else {
                percent = rate / (maxBasal - scheduledBasal.value)
            }
        } else {
            rate = 0
            percent = 0
            
            if let lastTempBasal = lastTempBasal, lastTempBasal.endDate > scheduledBasal.startDate {
                start = lastTempBasal.endDate
                end = scheduledBasal.endDate
            } else {
                start = scheduledBasal.startDate
                end = scheduledBasal.endDate
            }
        }
    }
}
