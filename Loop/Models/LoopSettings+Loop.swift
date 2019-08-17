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
        let inputs = PredictionInputEffect.all
        // To disable retrospective correction, uncomment line below and change `let` to `var` above
        // inputs.remove(.retrospection)
        return inputs
    }

    static let retrospectiveCorrectionEffectDuration = TimeInterval(hours: 1)

    
    /// Creates an instance of the enabled retrospective correction implementation
    var enabledRetrospectiveCorrectionAlgorithm: RetrospectiveCorrection {
        
        if (integralRetrospectiveCorrectionEnabled) {
            return IntegralRetrospectiveCorrection(effectDuration: LoopSettings.retrospectiveCorrectionEffectDuration)
        } else {
            return StandardRetrospectiveCorrection(effectDuration: LoopSettings.retrospectiveCorrectionEffectDuration)
        }
        
    }
}
