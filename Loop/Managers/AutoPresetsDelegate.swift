//
//  AutoPresetsDelegate.swift
//  Loop
//
//  Created for Loop AutoPresets Feature
//

import Foundation
import LoopKit

/// Protocol that Loop implements to receive commands from AutoPresets
public protocol AutoPresetsDelegate: AnyObject {
    /// Called when AutoPresets wants to activate a preset
    func autoPresets(_ coordinator: AutoPresetsCoordinator,
                     shouldActivatePreset preset: TemporaryScheduleOverridePreset)

    /// Called when AutoPresets wants to deactivate the current preset
    func autoPresets(_ coordinator: AutoPresetsCoordinator,
                     shouldDeactivatePreset preset: TemporaryScheduleOverridePreset)

    /// Returns currently available override presets from Loop
    func autoPresetsAvailablePresets(_ coordinator: AutoPresetsCoordinator) -> [TemporaryScheduleOverridePreset]

    /// Returns the currently active override, if any
    func autoPresetsCurrentOverride(_ coordinator: AutoPresetsCoordinator) -> TemporaryScheduleOverride?
}
