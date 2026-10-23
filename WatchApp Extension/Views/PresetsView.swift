//
//  PresetsView.swift
//  Loop
//
//  Created by Pete Schwamb on 9/22/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopCore

struct PresetsView: View {
    @Environment(LoopDataManager.self) var loopManager

    @State private var path = NavigationPath()

    enum DisplayState: Equatable {
        case presetsList
        case activeOverride(TemporaryScheduleOverride)
    }

    var displayState: DisplayState {
        if let override = loopManager.watchInfo.scheduleOverride {
            return .activeOverride(override)
        } else {
            return .presetsList
        }
    }

    var body: some View {
        ZStack {
            switch displayState {
            case .activeOverride(let override):
                PresetConfirmationView(preset: loopManager.selectablePresets.first {$0.id == override.presetId})
            case .presetsList:
                NavigationStack(path: $path) {
                    PresetListView(presets: loopManager.listedPresets, path: $path)
                }
            }
        }
    }
}
