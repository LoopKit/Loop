//
//  DoseEnactor.swift
//  Loop
//
//  Created by Pete Schwamb on 7/30/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

class DoseEnactor {
    
    fileprivate let dosingQueue: DispatchQueue = DispatchQueue(label: "com.loopkit.DeviceManagerDosingQueue", qos: .utility)
    
    private let log = DiagnosticLog(category: "DoseEnactor")

    /// `newDoseId` is called once per dose sent, with the bolus activation type (nil for a temp basal).
    func enact(bolus: Double?, tempBasal: TempBasalRecommendation?, with pumpManager: PumpManager, newDoseId: (BolusActivationType?) async -> UUID) async throws {
        if let tempBasal {
            self.log.default("Enacting recommended basal change")
            try await pumpManager.enactTempBasal(doseId: await newDoseId(nil), unitsPerHour: tempBasal.unitsPerHour, for: tempBasal.duration)
        }

        if let bolus, bolus > 0 {
            self.log.default("Enacting recommended bolus dose")
            try await pumpManager.enactBolus(doseId: await newDoseId(.automatic), units: bolus, activationType: .automatic)
        }
    }
}

