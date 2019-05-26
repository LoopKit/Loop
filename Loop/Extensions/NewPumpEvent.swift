//
//  NewPumpEvent.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


extension NewPumpEvent {

    /// Constructs a pump event placeholder representing a bolus just enacted.
    ///
    /// - Parameters:
    ///   - units: The units of insulin requested
    ///   - date: The date the bolus was enacted
    static func enactedBolus(dose: DoseEntry) -> NewPumpEvent {
        return self.init(
            date: dose.startDate,
            dose: dose,
            isMutable: true,
            raw: Data(),  // This can be empty, as mutable events aren't persisted
            title: ""
        )
    }
}
