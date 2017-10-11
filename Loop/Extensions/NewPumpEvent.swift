//
//  NewPumpEvent.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import InsulinKit


extension NewPumpEvent {

    /// Constructs a pump event placeholder representing a bolus just enacted.
    ///
    /// - Parameters:
    ///   - units: The units of insulin requested
    ///   - date: The date the bolus was enacted
    static func enactedBolus(units: Double, at date: Date) -> NewPumpEvent {
        let dose = DoseEntry(type: .bolus, startDate: date, endDate: date, value: units, unit: .units)

        return self.init(
            date: date,
            dose: dose,
            isMutable: true,
            raw: Data(),  // This can be empty, as mutable events aren't persisted
            title: ""
        )
    }
}
