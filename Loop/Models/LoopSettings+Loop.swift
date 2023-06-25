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
        return inputs
    }

    static let retrospectiveCorrectionEffectDuration = TimeInterval(hours: 1)
    
    /// Creates an instance of the enabled retrospective correction implementation    
    func enabledRetrospectiveCorrectionAlgorithm() -> RetrospectiveCorrection {
        var enabledRetrospectiveCorrectionAlgorithm: RetrospectiveCorrection
        
        let isIntegralRetrospectiveCorrectionEnabled = UserDefaults.standard.integralRetrospectiveCorrectionEnabled
        
        if isIntegralRetrospectiveCorrectionEnabled {
            enabledRetrospectiveCorrectionAlgorithm = IntegralRetrospectiveCorrection(effectDuration: LoopSettings.retrospectiveCorrectionEffectDuration)
        } else {
            enabledRetrospectiveCorrectionAlgorithm = StandardRetrospectiveCorrection(effectDuration: LoopSettings.retrospectiveCorrectionEffectDuration)
        }
        
        return enabledRetrospectiveCorrectionAlgorithm
    }
    
}
