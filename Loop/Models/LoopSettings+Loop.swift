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
    func enabledRetrospectiveCorrectionAlgorithm(retrospectiveCorrection: RetrospectiveCorrectionOptions) -> RetrospectiveCorrection {
        var enabledRetrospectiveCorrectionAlgorithm: RetrospectiveCorrection
        switch retrospectiveCorrection {
        case .standardRetrospectiveCorrection:
            enabledRetrospectiveCorrectionAlgorithm = StandardRetrospectiveCorrection(effectDuration: LoopSettings.retrospectiveCorrectionEffectDuration)
        case .integralRetrospectiveCorrection:
            enabledRetrospectiveCorrectionAlgorithm = IntegralRetrospectiveCorrection(effectDuration: LoopSettings.retrospectiveCorrectionEffectDuration)
        }
        return enabledRetrospectiveCorrectionAlgorithm
    }
    
}
