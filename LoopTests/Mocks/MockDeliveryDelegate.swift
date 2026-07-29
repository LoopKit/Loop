//
//  MockDeliveryDelegate.swift
//  LoopTests
//
//  Created by Pete Schwamb on 12/1/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm
@testable import Loop

class MockDeliveryDelegate: DeliveryDelegate {
    var isSuspended: Bool = false

    var isManualTempBasalRunning: Bool = false

    var pumpInsulinType: InsulinType?
    
    var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    
    var isPumpConfigured: Bool = true

    var pumpManagerStatus: PumpManagerStatus?

    var pumpStatusHighlight: DeviceStatusHighlight?

    var cgmManagerStatus: CGMManagerStatus?

    var lastEnact: (bolus: Double?, tempBasal: TempBasalRecommendation?)

    func enact(bolus: Double?, tempBasal: TempBasalRecommendation?, decisionId: UUID?) async throws {
        lastEnact = (bolus, tempBasal)
    }

    var lastBolus: Double?
    var lastBolusActivationType: BolusActivationType?

    func enactBolus(units: Double, decisionId: UUID?, activationType: BolusActivationType) async throws {
        lastBolus = units
        lastBolusActivationType = activationType
    }
    
    func roundBasalRate(unitsPerHour: Double) -> Double {
        (unitsPerHour * 20).rounded() / 20.0
    }
    
    func roundBolusVolume(units: Double) -> Double {
        (units * 20).rounded() / 20.0
    }
    

}
