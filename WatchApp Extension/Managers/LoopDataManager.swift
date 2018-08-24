//
//  LoopDataManager.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/21/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

class LoopDataManager {
    var glucoseStore: GlucoseStore
    var activeContext: WatchContext? {
        didSet {
            NotificationCenter.default.post(name: .ContextUpdated, object: nil)
        }
    }

    init() {
        glucoseStore = GlucoseStore(
            healthStore: HKHealthStore(),
            cacheStore: PersistenceController.controllerInAppGroupDirectory(),
            cacheLength: .hours(4))
    }
}

extension Notification.Name {
    static let ContextUpdated = Notification.Name(rawValue: "com.loopkit.notification.ContextUpdated")
}
