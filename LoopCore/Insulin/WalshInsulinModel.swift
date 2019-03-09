//
//  WalshInsulinModel.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


extension WalshInsulinModel: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let duration = rawValue["actionDuration"] as? TimeInterval else {
            return nil
        }

        self.init(actionDuration: duration)
    }

    public var rawValue: [String : Any] {
        return ["actionDuration": self.actionDuration]
    }
}
