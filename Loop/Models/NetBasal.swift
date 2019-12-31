//
//  NetBasal.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/7/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Max basal should generally be set, but in those cases where it isn't just use 3.0U/hr as a default top of scale, so we can show *something*.
fileprivate let defaultMaxBasalForScale = 3.0

struct NetBasal {
    let rate: Double
    let percent: Double
    let start: Date
    let end: Date?

    init(suspendedAt: Date, maxBasal: Double?, scheduledBasal: AbsoluteScheduleValue<Double>) {
        rate = -scheduledBasal.value
        start = suspendedAt
        end = nil

        if rate < 0 {
            percent = rate / scheduledBasal.value
        } else {
            percent = rate / ((maxBasal ?? defaultMaxBasalForScale) - scheduledBasal.value)
        }
    }

    init(scheduledRateStartedAt: Date, scheduledBasal: AbsoluteScheduleValue<Double>) {
        rate = 0
        start = scheduledRateStartedAt
        end = nil
        percent = 0
    }

    init(lastTempBasal: DoseEntry?, maxBasal: Double?, scheduledBasal: AbsoluteScheduleValue<Double>) {
        if let lastTempBasal = lastTempBasal, lastTempBasal.endDate > Date() {
            let maxBasal = maxBasal ?? defaultMaxBasalForScale
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
