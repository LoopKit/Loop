//
//  PersistedPumpEvent.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopKit
import NightscoutUploadKit


extension PersistedPumpEvent {
    func treatment(enteredBy source: String) -> NightscoutTreatment? {
        // Doses can be inferred from other types of events, e.g. a No Delivery Alarm type indicates a suspend in delivery.
        // At the moment, Nightscout only supports straightforward events
        guard let type = type, let dose = dose, dose.type.pumpEventType == type else {
            return nil
        }

        switch dose.type {
        case .basal:
            return nil
        case .bolus:
            let duration = dose.endDate.timeIntervalSince(dose.startDate)

            return BolusNightscoutTreatment(
                timestamp: dose.startDate,
                enteredBy: source,
                bolusType: duration > 0 ? .Square : .Normal,
                amount: dose.units,
                programmed: dose.units,  // Persisted pump events are always completed
                unabsorbed: 0,  // The pump's reported IOB isn't relevant, nor stored
                duration: duration,
                carbs: 0,
                ratio: 0
            )
        case .resume:
            return PumpResumeTreatment(timestamp: dose.startDate, enteredBy: source)
        case .suspend:
            return PumpSuspendTreatment(timestamp: dose.startDate, enteredBy: source)
        case .tempBasal:
            return TempBasalNightscoutTreatment(
                timestamp: dose.startDate,
                enteredBy: source,
                temp: .Absolute,  // DoseEntry only supports .absolute types
                rate: dose.unitsPerHour,
                absolute: dose.unitsPerHour,
                duration: Int(dose.endDate.timeIntervalSince(dose.startDate).minutes)
            )
        }
    }
}
