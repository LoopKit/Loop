//
//  AlertPermissionsViewModel.swift
//  Loop
//
//  Created by Anna Quinlan on 11/7/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI

public class AlertPermissionsViewModel: ObservableObject {
    @Published var unannouncedMealNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.unannouncedMealNotificationsEnabled = unannouncedMealNotificationsEnabled
        }
    }
    
    @Published var checker: AlertPermissionsChecker
    
    init(checker: AlertPermissionsChecker) {
        self.unannouncedMealNotificationsEnabled = UserDefaults.standard.unannouncedMealNotificationsEnabled
        self.checker = checker
    }
}


extension UserDefaults {
    
    private enum Key: String {
        case unannouncedMealNotificationsEnabled = "com.loopkit.Loop.UnannouncedMealNotificationsEnabled"
    }
    
    var unannouncedMealNotificationsEnabled: Bool {
        get {
            return object(forKey: Key.unannouncedMealNotificationsEnabled.rawValue) as? Bool ?? false
        }
        set {
            set(newValue, forKey: Key.unannouncedMealNotificationsEnabled.rawValue)
        }
    }
}
