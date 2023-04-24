//
//  OverrideAction.swift
//  Loop
//
//  Created by Bill Gestrich on 2/21/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKit

extension OverrideAction {
    
    func toValidOverride(allowedPresets: [TemporaryScheduleOverridePreset]) throws -> TemporaryScheduleOverride {
        guard let preset = allowedPresets.first(where: { $0.name == name }) else {
            throw OverrideActionError.unknownPreset(name)
        }
        
        var remoteOverride = preset.createOverride(enactTrigger: .remote(remoteAddress))
        
        if let durationTime = durationTime {
            
            guard durationTime <= LoopConstants.maxOverrideDurationTime else {
                throw OverrideActionError.durationExceedsMax(LoopConstants.maxOverrideDurationTime)
            }
            
            guard durationTime >= 0 else {
                throw OverrideActionError.negativeDuration
            }
            
            if durationTime == 0 {
                remoteOverride.duration = .indefinite
            } else {
                remoteOverride.duration = .finite(durationTime)
            }
        }
        
        return remoteOverride
    }
}

enum OverrideActionError: LocalizedError {
    
    case unknownPreset(String)
    case durationExceedsMax(TimeInterval)
    case negativeDuration
    
    var errorDescription: String? {
        switch self {
        case .unknownPreset(let presetName):
            return String(format: NSLocalizedString("Unknown preset: %1$@", comment: "Remote command error description: unknown preset (1: preset name)."), presetName)
        case .durationExceedsMax(let maxDurationTime):
            return String(format: NSLocalizedString("Duration exceeds: %1$.1f hours", comment: "Remote command error description: duration exceed max (1: max duration in hours)."), maxDurationTime.hours)
        case .negativeDuration:
            return String(format: NSLocalizedString("Negative duration not allowed", comment: "Remote command error description: negative duration error."))
        }
    }
}
