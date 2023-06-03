//
//  SettingsViewModel+ApplyLinearRamp.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-03.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

extension SettingsViewModel {

    var applyLinearRampToBolusApplicationFactorBinding: Binding<Bool> {
        Binding<Bool>(
            get: { UserDefaults.standard.bool(forKey: "applyLinearRampToBolusApplicationFactor") },
            set: { UserDefaults.standard.set($0, forKey: "applyLinearRampToBolusApplicationFactor") }
        )
    }
}
