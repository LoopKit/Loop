//
//  RemoteCommand.swift
//  Loop
//
//  Created by Pete Schwamb on 9/16/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public enum RemoteCommandError: Error {
    case expired
}


enum RemoteCommand {
    typealias RawValue = [String: Any]

    case temporaryScheduleOverride(TemporaryScheduleOverride)
    case cancelTemporaryOverride
}


// Push Notifications
extension RemoteCommand {
    init?(notification: [String: Any], allowedPresets: [TemporaryScheduleOverridePreset]) {
        if let overrideEnactName = notification["override-name"] as? String,
            let preset = allowedPresets.first(where: { $0.name == overrideEnactName }),
            let remoteAddress = notification["remote-address"] as? String
        {
            var override = preset.createOverride(enactTrigger: .remote(remoteAddress))
            if let overrideDurationMinutes = notification["override-duration-minutes"] as? Double {
                override.duration = .finite(TimeInterval(minutes: overrideDurationMinutes))
            }
            self = .temporaryScheduleOverride(override)
        } else if let _ = notification["cancel-temporary-override"] as? String {
            self = .cancelTemporaryOverride
        }
        else {
            return nil
        }
    }
}
