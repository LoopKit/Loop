//
//  SensorValueGlucoseEvent.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import MinimedKit


extension SensorValueGlucoseEvent {
    var glucoseSyncIdentifier: String? {
        let date = timestamp

        guard
            let year = date.year,
            let month = date.month,
            let day = date.day,
            let hour = date.hour,
            let minute = date.minute,
            let second = date.second
        else {
            return nil
        }

        return "\(year)-\(month)-\(day) \(hour)-\(minute)-\(second)"
    }
}
