//
//  ExponentialInsulinModelPreset.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


public enum ExponentialInsulinModelPreset: String {
    case humalogNovologAdult
    case humalogNovologChild
    case fiasp
    case lyumjev
}


// MARK: - Model generation
extension ExponentialInsulinModelPreset {
    var actionDuration: TimeInterval {
        switch self {
        case .humalogNovologAdult:
            return .minutes(360)
        case .humalogNovologChild:
            return .minutes(360)
        case .fiasp:
            return .minutes(360)
        case .lyumjev:
            return .minutes(300)
        }
    }

    var peakActivity: TimeInterval {
        switch self {
        case .humalogNovologAdult:
            return .minutes(75)
        case .humalogNovologChild:
            return .minutes(65)
        case .fiasp:
            return .minutes(55)
        case .lyumjev:
            return .minutes(45)
        }
    }
    
    var effectDelay: TimeInterval {
        switch self {
        case .humalogNovologAdult:
            return .minutes(10)
        case .humalogNovologChild:
            return .minutes(10)
        case .fiasp:
            return .minutes(10)
        case .lyumjev:
            return .minutes(8)
        }
    }

    var model: InsulinModel {
        return ExponentialInsulinModel(actionDuration: actionDuration, peakActivityTime: peakActivity, delay: effectDelay)
    }
}


extension ExponentialInsulinModelPreset: InsulinModel {
    public var effectDuration: TimeInterval {
        return model.effectDuration
    }
    
    public var delay: TimeInterval {
        return model.delay
    }

    public func percentEffectRemaining(at time: TimeInterval) -> Double {
        return model.percentEffectRemaining(at: time)
    }
}


extension ExponentialInsulinModelPreset: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "\(self.rawValue)(\(String(reflecting: model))"
    }
}
