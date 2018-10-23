//
//  FPUDelay.swift
//  Loop
//
//  Created by Robert Silvers on 10/19/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

struct FPUDelay: RawRepresentable {
    typealias RawValue = [String: Any]
    
    let value: Double
    
    public init(value: Double) {
        self.value = value
    }
    
    init?(rawValue: RawValue) {
        guard let value = rawValue["value"] as? Double else {
            return nil
        }
        self.value = value
    }
    
    var rawValue: RawValue {
        return [
            "value": value,
        ]
    }
}

extension FPUDelay: Equatable {
    static func ==(lhs: FPUDelay, rhs: FPUDelay) -> Bool {
        return lhs.value == rhs.value
    }
}
