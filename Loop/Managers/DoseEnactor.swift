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

    func enact(recommendation: AutomaticDoseRecommendation, with pumpManager: PumpManager) async throws {

        if let basalAdjustment = recommendation.basalAdjustment {
            self.log.default("Enacting recommended basal change")
            try await pumpManager.enactTempBasal(unitsPerHour: basalAdjustment.unitsPerHour, for: basalAdjustment.duration)
        }

        if let bolusUnits = recommendation.bolusUnits, bolusUnits > 0 {
            self.log.default("Enacting recommended bolus dose")
            try await pumpManager.enactBolus(units: bolusUnits, activationType: .automatic)
        }
    }
}

