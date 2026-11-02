//
//  Environment+SettingsProvider.swift
//  Loop
//
//  Created by Pete Schwamb on 3/19/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit


@MainActor
private struct SettingsManagerKey: @preconcurrency EnvironmentKey {
    static let defaultValue: SettingsManager = SettingsManager.placeholder
}

extension EnvironmentValues {
    var settingsManager: SettingsManager {
        get { self[SettingsManagerKey.self] }
        set { self[SettingsManagerKey.self] = newValue }
    }
}
