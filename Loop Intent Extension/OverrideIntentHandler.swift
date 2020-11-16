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
    
    var presetOptions: [String]? {
        guard let defaults = self.defaults, let names = defaults.intentExtensionInfo?.overridePresetNames else {
            return nil
        }
        
        return names
    }
    
    @available(iOSApplicationExtension 14.0, watchOSApplicationExtension 7.0, *)
    func provideOverrideNameOptionsCollection(for intent: EnableOverridePresetIntent, with completion: @escaping (INObjectCollection<NSString>?, Error?) -> Void) {
        guard let presets = presetOptions else {
            completion(nil, nil)
            return
        }
        completion(INObjectCollection(items: presets.map { NSString(string: $0) } ), nil)
    }
    
    func containsOverrideName(name: String) -> Bool {
        let lowercasedName = name.lowercased()
        
        if presetOptions?.first(where: {$0.lowercased() == lowercasedName}) != nil {
            return true
        }
        return false
    }
    
    func handle(intent: EnableOverridePresetIntent, completion: @escaping (EnableOverridePresetIntentResponse) -> Void) {
        guard let defaults = self.defaults, let overrideName = intent.overrideName?.lowercased(), containsOverrideName(name: overrideName) else {
            completion(EnableOverridePresetIntentResponse(code: .failure, userActivity: nil))
            return
        }

        defaults.intentExtensionOverrideToSet = overrideName
        // Continue in app because the UserDefaults KVO doesn't work in the background
        completion(EnableOverridePresetIntentResponse(code: .continueInApp, userActivity: nil))
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
