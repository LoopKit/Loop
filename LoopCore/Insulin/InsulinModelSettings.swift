//
//  InsulinModelSettings.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


public enum InsulinModelSettings {
    case exponentialPreset(ExponentialInsulinModelPreset)
    case walsh(WalshInsulinModel)

    public var model: InsulinModel {
        switch self {
        case .exponentialPreset(let model):
            return model
        case .walsh(let model):
            return model
        }
    }

    public init?(model: InsulinModel) {
        switch model {
        case let model as ExponentialInsulinModelPreset:
            self = .exponentialPreset(model)
        case let model as WalshInsulinModel:
            self = .walsh(model)
        default:
            return nil
        }
    }
}


extension InsulinModelSettings: CustomDebugStringConvertible {
    public var debugDescription: String {
        return String(reflecting: model)
    }
}


extension InsulinModelSettings: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let typeName = rawValue["type"] as? InsulinModelType.RawValue,
            let type = InsulinModelType(rawValue: typeName)
        else {
            return nil
        }

        switch type {
        case .exponentialPreset:
            guard let modelRaw = rawValue["model"] as? ExponentialInsulinModelPreset.RawValue,
                let model = ExponentialInsulinModelPreset(rawValue: modelRaw)
            else {
                return nil
            }

            self = .exponentialPreset(model)
        case .walsh:
            guard let modelRaw = rawValue["model"] as? WalshInsulinModel.RawValue,
                let model = WalshInsulinModel(rawValue: modelRaw)
            else {
                return nil
            }

            self = .walsh(model)
        }
    }

    public var rawValue: [String : Any] {
        switch self {
        case .exponentialPreset(let model):
            return [
                "type": InsulinModelType.exponentialPreset.rawValue,
                "model": model.rawValue
            ]
        case .walsh(let model):
            return [
                "type": InsulinModelType.walsh.rawValue,
                "model": model.rawValue
            ]
        }
    }

    private enum InsulinModelType: String {
        case exponentialPreset
        case walsh
    }
}
