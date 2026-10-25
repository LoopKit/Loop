//
//  PredictionInputEffect.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/4/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

struct PredictionInputEffect: OptionSet {
    let rawValue: Int

    static let carbs            = PredictionInputEffect(rawValue: 1 << 0)
    static let insulin          = PredictionInputEffect(rawValue: 1 << 1)
    static let momentum         = PredictionInputEffect(rawValue: 1 << 2)
    static let retrospection    = PredictionInputEffect(rawValue: 1 << 3)
    static let suspend          = PredictionInputEffect(rawValue: 1 << 4)
    static let guardAndRunway   = PredictionInputEffect(rawValue: 1 << 5)

    static let all: PredictionInputEffect = [.carbs, .insulin, .momentum, .retrospection, .guardAndRunway]

    var localizedTitle: String? {
        switch self {
        case [.carbs]:
            return NSLocalizedString("Carbohydrates", comment: "Title of the prediction input effect for carbohydrates")
        case [.insulin]:
            return NSLocalizedString("Insulin", comment: "Title of the prediction input effect for insulin")
        case [.momentum]:
            return NSLocalizedString("Glucose Momentum", comment: "Title of the prediction input effect for glucose momentum")
        case [.retrospection]:
            return NSLocalizedString("Retrospective Correction", comment: "Title of the prediction input effect for retrospective correction")
        case [.suspend]:
            return NSLocalizedString("Suspension of Insulin Delivery", comment: "Title of the prediction input effect for suspension of insulin delivery")
        case [.guardAndRunway]:
            return NSLocalizedString("Guard + Runway", comment: "Title of the prediction input effect for the guard and runway experiment")
        default:
            return nil
        }
    }

    func localizedDescription(forGlucoseUnit unit: LoopUnit) -> String? {
        switch self {
        case [.carbs]:
            return String(format: NSLocalizedString("Carbs Absorbed (g) ÷ Carb Ratio (g/U) × Insulin Sensitivity (%1$@/U)", comment: "Description of the prediction input effect for carbohydrates. (1: The glucose unit string)"), unit.localizedShortUnitString)
        case [.insulin]:
            return String(format: NSLocalizedString("Insulin Absorbed (U) × Insulin Sensitivity (%1$@/U)", comment: "Description of the prediction input effect for insulin"), unit.localizedShortUnitString)
        case [.momentum]:
            return NSLocalizedString("15 min glucose regression coefficient (b₁), continued with decay over 30 min", comment: "Description of the prediction input effect for glucose momentum")
        case [.retrospection]:
            return NSLocalizedString("30 min comparison of glucose prediction vs actual, continued with decay over 60 min", comment: "Description of the prediction input effect for retrospective correction")
        case [.suspend]:
             return NSLocalizedString("Glucose effect of suspending insulin delivery", comment: "Description of the prediction input effect for suspension of insulin delivery")
        case [.guardAndRunway]:
            return NSLocalizedString("Forecast lowered by recent glucose volatility over the next 2 hours, and the automatic dosing target lowered when there is room above the suspend threshold", comment: "Description of the prediction input effect for the guard and runway experiment")
        default:
            return nil
        }
    }
}

extension PredictionInputEffect {
    var algorithmEffectOptions: AlgorithmEffectsOptions {
        var rval = [AlgorithmEffectsOptions]()
        if self.contains(.carbs) {
            rval.append(.carbs)
        }
        if self.contains(.insulin) {
            rval.append(.insulin)
        }
        if self.contains(.momentum) {
            rval.append(.momentum)
        }
        if self.contains(.retrospection) {
            rval.append(.retrospection)
        }
        return AlgorithmEffectsOptions(rval)
    }
}
