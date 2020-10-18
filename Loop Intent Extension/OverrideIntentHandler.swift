//
//  OverrideIntentHandler.swift
//  Loop Intent Extension
//
//  Created by Anna Quinlan on 10/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import Intents

class OverrideIntentHandler: NSObject, EnableOverridePresetIntentHandling {
    lazy var defaults = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)
    
    func containsOverrideName(name: String) -> Bool {
        let lowercasedName = name.lowercased()
        
        if let defaults = self.defaults, defaults.intentExtensionInfo?.overridePresetNames?.first(where: {$0.lowercased() == lowercasedName}) != nil {
            return true
        }
        return false
    }
    
    func handle(intent: EnableOverridePresetIntent, completion: @escaping (EnableOverridePresetIntentResponse) -> Void) {
        guard let defaults = self.defaults, let overrideName = intent.overrideName?.lowercased(), containsOverrideName(name: overrideName) else {
            completion(EnableOverridePresetIntentResponse(code: .failure, userActivity: nil))
            return
        }
        
        defaults.intentExtensionInfo?.presetNameToSet = overrideName
//        loopManager.settings.scheduleOverride = preset.createOverride(enactTrigger: .remote("Siri"))
        completion(EnableOverridePresetIntentResponse(code: .success, userActivity: nil))
    }
    
    func resolveOverrideName(for intent: EnableOverridePresetIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let overrideName = intent.overrideName?.lowercased() else {
            completion(INStringResolutionResult.needsValue())
            return
        }
        
        guard containsOverrideName(name: overrideName) else {
            completion(INStringResolutionResult.unsupported())
            return
        }

        completion(INStringResolutionResult.success(with: overrideName))
    }    
}
