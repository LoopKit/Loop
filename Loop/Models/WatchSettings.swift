//
//  WatchSettings.swift
//  Loop
//
//  Created by Michael Pangburn on 9/24/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


struct WatchSettings {
    var wakingHours: DailyScheduleInterval
}

extension WatchSettings {
    static var `default`: WatchSettings {
        return WatchSettings(wakingHours: DailyScheduleInterval(startTime: .hour(6), endTime: .hour(22)))
    }

    var sleepingHours: DailyScheduleInterval {
        return wakingHours.complement()
    }
}

extension WatchSettings: RawRepresentable {
    typealias RawValue = [String: Any]
    private static let version = 1

    private enum Key: String {
        case version = "version"
        case wakingHours = "wakingHours"
    }

    init?(rawValue: RawValue) {
        guard
            let version = rawValue[Key.version.rawValue] as? Int,
            version == WatchSettings.version,
            let wakingHoursRawValue = rawValue[Key.wakingHours.rawValue] as? DailyScheduleInterval.RawValue,
            let wakingHours = DailyScheduleInterval(rawValue: wakingHoursRawValue)
            else {
                return nil
        }

        self.init(wakingHours: wakingHours)
    }

    var rawValue: RawValue {
        return [
            Key.version.rawValue: WatchSettings.version,
            Key.wakingHours.rawValue: wakingHours.rawValue
        ]
    }
}
