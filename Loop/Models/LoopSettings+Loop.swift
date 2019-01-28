//
//  LoopSettings+Loop.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//


// MARK: - Static configuration
extension LoopSettings {
    var enabledEffects: PredictionInputEffect {
        let inputs = PredictionInputEffect.all
        // To disable retrospective correction, uncomment line below and change `let` to `var` above
        // inputs.remove(.retrospection)
        return inputs
    }
}
