//
//  UserDefaults+Loop.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit


extension UserDefaults {
    private enum Key: String {
        case pumpManagerState = "com.loopkit.Loop.PumpManagerState"
        case cgmManagerState = "com.loopkit.Loop.CGMManagerState"
        case loopNotRunningNotifications = "com.loopkit.Loop.loopNotRunningNotifications"
    }

    var pumpManagerRawValue: [String: Any]? {
        get {
            return dictionary(forKey: Key.pumpManagerState.rawValue)
        }
        set {
            set(newValue, forKey: Key.pumpManagerState.rawValue)
        }
    }

    var cgmManagerRawValue: [String: Any]? {
        get {
            return dictionary(forKey: Key.cgmManagerState.rawValue)
        }
        set {
            set(newValue, forKey: Key.cgmManagerState.rawValue)
        }
    }
    
    var cgmManager: CGMManager? {
        get {
            guard let rawValue = cgmManagerState else {
                return nil
            }

            return CGMManagerFromRawValue(rawValue)
        }
        set {
            cgmManagerState = newValue?.rawValue
        }
    }

    var loopNotRunningNotifications: [StoredLoopNotRunningNotification] {
        get {
            let decoder = JSONDecoder()
            guard let data = object(forKey: Key.loopNotRunningNotifications.rawValue) as? Data else {
                return []
            }
            return (try? decoder.decode([StoredLoopNotRunningNotification].self, from: data)) ?? []
        }
        set {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(newValue)
                set(data, forKey: Key.loopNotRunningNotifications.rawValue)
            } catch {
                assertionFailure("Unable to encode Loop not running notification")
            }
        }
    }
}
