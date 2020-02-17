//
//  InhaledInsulinModel.swift
//  Loop
//
//  Created by Anna Quinlan on 2/16/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

extension InhaledInsulinModel: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let delay = rawValue["delay"] as? TimeInterval else {
            return nil
        }

        self.init(modelDelay: delay)}

    public var rawValue: [String : Any] {
        return ["delay": self.delay]
    }
}
