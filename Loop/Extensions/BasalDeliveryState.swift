//
//  BasalDeliveryState.swift
//  Loop
//
//  Created by Pete Schwamb on 8/5/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopCore
import LoopAlgorithm

extension PumpManagerStatus.BasalDeliveryState {
    func getNetBasal(basalSchedule: BasalRateSchedule, maximumBasalRatePerHour: Double?) -> NetBasal? {
        func scheduledBasal(for date: Date) -> AbsoluteScheduleValue<Double>? {
            return basalSchedule.between(start: date, end: date).first
        }

        switch self {
        case .tempBasal(let dose):
            if let scheduledBasal = scheduledBasal(for: dose.startDate) {
                return NetBasal(
                    lastTempBasal: dose,
                    maxBasal: maximumBasalRatePerHour,
                    scheduledBasal: scheduledBasal
                )
            } else {
                return nil
            }
        case .suspended(let date):
            if let scheduledBasal = scheduledBasal(for: date) {
                return NetBasal(
                    suspendedAt: date,
                    maxBasal: maximumBasalRatePerHour,
                    scheduledBasal: scheduledBasal
                )
            } else {
                return nil
            }
        case .active(let date):
            if scheduledBasal(for: date) != nil {
                return NetBasal(scheduledRateStartedAt: date)
            } else {
                return nil
            }
        default:
            return nil
        }
    }
}

