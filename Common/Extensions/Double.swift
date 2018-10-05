//
//  Double.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


extension Double {
    func floored(to increment: Double) -> Double {
        if increment == 0 {
            return self
        }

        return floor(self / increment) * increment
    }

    func ceiled(to increment: Double) -> Double {
        if increment == 0 {
            return self
        }

        return ceil(self / increment) * increment
    }
}

