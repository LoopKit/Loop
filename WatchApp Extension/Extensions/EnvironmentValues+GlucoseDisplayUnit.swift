//
//  Env.swift
//  Loop
//
//  Created by Pete Schwamb on 9/9/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit

@MainActor
private struct GlucoseDisplayUnitKey: @preconcurrency EnvironmentKey {
    static let defaultValue: LoopUnit = .milligramsPerDeciliter
}

extension EnvironmentValues {
    var glucoseDisplayUnit: LoopUnit {
        get { self[GlucoseDisplayUnitKey.self] }
        set { self[GlucoseDisplayUnitKey.self] = newValue }
    }
}
