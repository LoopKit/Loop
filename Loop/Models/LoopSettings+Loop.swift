//
//  LoopSettings+Loop.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopCore

// MARK: - Static configuration
extension LoopSettings {
    var enabledEffects: PredictionInputEffect {
        var inputs = PredictionInputEffect.all
        if !LoopConstants.retrospectiveCorrectionEnabled {
            inputs.remove(.retrospection)
        }
        if !UserDefaults.standard.negativeInsulinDamperEnabled {
            inputs.remove(.damper)
        }
        return inputs
    }    
}
