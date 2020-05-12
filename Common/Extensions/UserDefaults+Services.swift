//
//  UserDefaults+Services.swift
//  Loop
//
//  Created by Darin Krauss on 5/20/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit

extension UserDefaults {

    private enum Key: String {
        case servicesState = "com.loopkit.Loop.ServicesState"
    }

    var servicesState: [Service.RawStateValue] {
        get {
            return array(forKey: Key.servicesState.rawValue) as? [[String: Any]] ?? []
        }
        set {
            set(newValue, forKey: Key.servicesState.rawValue)
        }
    }

}
