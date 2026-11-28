//
//  PresetConfirmationView.swift
//  Loop
//
//  Created by Pete Schwamb on 9/22/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopCore

struct PresetConfirmationView: View {
    @Environment(LoopDataManager.self) var loopManager
    @Environment(\.dismiss) private var dismiss

    let preset: SelectablePreset?

    @State private var confirmedViaButton: Bool = false

    enum DisplayState: Equatable {
        case confirmingViaButton(SelectablePreset)
        case confirmingViaCrown(SelectablePreset)
        case activated(TemporaryScheduleOverride)
        case oneTimeUseOverrideEnded
    }

    var displayState: DisplayState {
        if let override = loopManager.scheduleOverride {
            return .activated(override)
        } else if let preset {
            if isConfirmingFromPresetReminder && !confirmedViaButton {
                return .confirmingViaButton(preset)
            } else {
                return .confirmingViaCrown(preset)
            }
        } else {
            return .oneTimeUseOverrideEnded
        }
    }

    var isConfirmingFromPresetReminder: Bool {
        if let reminder = loopManager.pendingPresetReminder,
           let preset,
           reminder.presetIdentifier == preset.id
        {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            switch displayState {
            case .confirmingViaButton(let preset):
                PresetActivateButtonConfirm(preset: preset, confirmed: $confirmedViaButton)
            case .confirmingViaCrown(let preset):
                PresetActivateCrownConfirm(preset: preset)
            case .activated(let override):
                ActiveOverrideView(override: override)
            case .oneTimeUseOverrideEnded:
                // Should not display, as we will dismiss below
                Text("One-time use override has ended.")
            }
        }
        .onDisappear {
            if isConfirmingFromPresetReminder {
                // Treat exiting reminder confirmation as declining
                self.loopManager.pendingPresetReminder = nil
            }
        }
        .onChange(of: displayState, { oldValue, newValue in
            if case .confirmingViaCrown = oldValue,
                case .activated = newValue,
               isConfirmingFromPresetReminder
            {
                // Successfully activated; clear reminder state
                self.loopManager.pendingPresetReminder = nil
            }
        })
        .onChange(of: loopManager.scheduleOverride) { oldValue, newVelue in
            if oldValue != nil, newVelue == nil, preset == nil
            {
                dismiss()
            }
        }
    }
}
