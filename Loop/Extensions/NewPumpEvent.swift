//
//  NewPumpEvent.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


extension NewPumpEvent {

    /*
     It takes a MM pump about 40s to deliver 1 Unit while bolusing
     See: http://www.healthline.com/diabetesmine/ask-dmine-speed-insulin-pumps#3
     */
    private static let deliveryUnitsPerMinute = 1.5

    /// Constructs a pump event placeholder representing a bolus just enacted.
    ///
    /// - Parameters:
    ///   - units: The units of insulin requested
    ///   - date: The date the bolus was enacted
    static func enactedBolus(units: Double, at date: Date) -> NewPumpEvent {
        let dose = DoseEntry(
            type: .bolus,
            startDate: date,
            endDate: date.addingTimeInterval(.minutes(units / NewPumpEvent.deliveryUnitsPerMinute)),
            value: units,
            unit: .units
        )

        return self.init(
            date: date,
            dose: dose,
            isMutable: true,
            raw: Data(),  // This can be empty, as mutable events aren't persisted
            title: ""
        )
    }
}
