//
//  ConstantDosingStrategy.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-03.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopCore
import LoopAlgorithm

struct ConstantApplicationFactorStrategy: ApplicationFactorStrategy {
    func calculateDosingFactor(
        for glucose: LoopQuantity,
        correctionRange: ClosedRange<LoopQuantity>
    ) -> Double {
        // The original strategy uses a constant dosing factor.
        return LoopAlgorithm.defaultBolusPartialApplicationFactor
    }
}
