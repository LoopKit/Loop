//
//  BasalDeliveryState.swift
//  Loop
//
//  Created by Pete Schwamb on 8/5/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopCore

extension PumpManagerStatus.BasalDeliveryState {
    func getNetBasal(basalSchedule: BasalRateSchedule, settings: LoopSettings) -> NetBasal? {
        func scheduledBasal(for date: Date) -> AbsoluteScheduleValue<Double>? {
            return basalSchedule.between(start: date, end: date).first
        }

        switch self {
        case .tempBasal(let dose):
            if let scheduledBasal = scheduledBasal(for: dose.startDate) {
                return NetBasal(
                    lastTempBasal: dose,
                    maxBasal: settings.maximumBasalRatePerHour,
                    scheduledBasal: scheduledBasal
                )
            } else {
                return nil
            }
        case .suspended(let date):
            if let scheduledBasal = scheduledBasal(for: date) {
                return NetBasal(
                    suspendedAt: date,
                    maxBasal: settings.maximumBasalRatePerHour,
                    scheduledBasal: scheduledBasal
                )
            } else {
                return nil
            }
        case .active(let date):
            if let scheduledBasal = scheduledBasal(for: date) {
                return NetBasal(scheduledRateStartedAt: date, scheduledBasal: scheduledBasal)
            } else {
                return nil
            }
        default:
            return nil
        }
    }
}

