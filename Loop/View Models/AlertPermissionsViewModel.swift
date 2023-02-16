//
//  AlertPermissionsViewModel.swift
//  Loop
//
//  Created by Anna Quinlan on 11/7/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI

public class AlertPermissionsViewModel: ObservableObject {
    @Published var missedMealNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.missedMealNotificationsEnabled = missedMealNotificationsEnabled
        }
    }
    
    @Published var checker: AlertPermissionsChecker
    
    init(checker: AlertPermissionsChecker) {
        self.missedMealNotificationsEnabled = UserDefaults.standard.missedMealNotificationsEnabled
        self.checker = checker
    }
}


extension UserDefaults {
    
    private enum Key: String {
        case missedMealNotificationsEnabled = "com.loopkit.Loop.MissedMealNotificationsEnabled"
    }
    
    var missedMealNotificationsEnabled: Bool {
        get {
            return object(forKey: Key.missedMealNotificationsEnabled.rawValue) as? Bool ?? false
        }
        set {
            set(newValue, forKey: Key.missedMealNotificationsEnabled.rawValue)
        }
    }
}
