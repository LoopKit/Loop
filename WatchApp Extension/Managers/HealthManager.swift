//
//  HealthKitManager.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/21/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

class HealthManager {
    var glucoseStore = GlucoseStore()
}

extension Notification.Name {
    static let GlucoseUpdated = Notification.Name(rawValue: "com.loopkit.notification.GlucoseUpdated")
}
