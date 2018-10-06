//
//  Double.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


extension FloatingPoint {
    func floored(to increment: Self) -> Self {
        if increment == 0 {
            return self
        }

        return floor(self / increment) * increment
    }

    func ceiled(to increment: Self) -> Self {
        if increment == 0 {
            return self
        }

        return ceil(self / increment) * increment
    }
}

