//
//  AutoPresets_Delegate.swift
//  Loop
//
//  AutoPresets — Protocol that Loop implements to receive commands from AutoPresets.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// Protocol that Loop implements to receive commands from AutoPresets
public protocol AutoPresets_Delegate: AnyObject {
    /// Called when AutoPresets wants to activate a preset
    func autoPresets(_ coordinator: AutoPresets_Coordinator,
                     shouldActivatePreset preset: TemporaryScheduleOverridePreset)

    /// Called when AutoPresets wants to deactivate the current preset
    func autoPresets(_ coordinator: AutoPresets_Coordinator,
                     shouldDeactivatePreset preset: TemporaryScheduleOverridePreset)

    /// Returns currently available override presets from Loop
    func autoPresetsAvailablePresets(_ coordinator: AutoPresets_Coordinator) -> [TemporaryScheduleOverridePreset]

    /// Returns the currently active override, if any
    func autoPresetsCurrentOverride(_ coordinator: AutoPresets_Coordinator) -> TemporaryScheduleOverride?
}
