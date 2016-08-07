//
//  DoseStore.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/31/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import InsulinKit
import MinimedKit


// Bridges support for MinimedKit data types
extension DoseStore {
    /**
     Adds and persists new pump events.
     */
    func add(pumpEvents: [TimestampedHistoryEvent], completionHandler: (error: DoseStore.Error?) -> Void) {

        var events: [(date: NSDate, dose: DoseEntry?, raw: NSData?, isMutable: Bool)] = []
        var lastTempBasalAmount: DoseEntry?

        for event in pumpEvents {
            var dose: DoseEntry?

            switch event.pumpEvent {
            case let bolus as BolusNormalPumpEvent:
                InsulinKit.PumpEventType.bolus

                let unit: DoseUnit

                switch bolus.type {
                case .Normal:
                    unit = .units
                case .Square:
                    unit = .unitsPerHour
                }

                dose = DoseEntry(type: .bolus, startDate: event.date, endDate: event.date.dateByAddingTimeInterval(bolus.duration), value: bolus.amount, unit: unit)
            case is SuspendPumpEvent:
                dose = DoseEntry(suspendDate: event.date)
            case is ResumePumpEvent:
                dose = DoseEntry(resumeDate: event.date)
            case let temp as TempBasalPumpEvent:
                if case .Absolute = temp.rateType {
                    lastTempBasalAmount = DoseEntry(type: .tempBasal, startDate: event.date, value: temp.rate, unit: .unitsPerHour)
                }
            case let temp as TempBasalDurationPumpEvent:
                if let amount = lastTempBasalAmount where amount.startDate == event.date {
                    dose = DoseEntry(
                        type: .tempBasal,
                        startDate: event.date,
                        endDate: event.date.dateByAddingTimeInterval(NSTimeInterval(minutes: Double(temp.duration))),
                        value: amount.value,
                        unit: amount.unit
                    )
                }
            default:
                break
            }

            events.append((
                date: event.date,
                dose: dose,
                raw: event.pumpEvent.rawData,
                isMutable: event.isMutable()
            ))
        }

        addPumpEvents(events, completionHandler: completionHandler)
    }
}
