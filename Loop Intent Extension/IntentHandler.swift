//
//  IntentHandler.swift
//  Loop Intent Extension
//
//  Created by Anna Quinlan on 10/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Intents

class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        if intent is EnableOverridePresetIntent {
            return OverrideIntentHandler()
        }
        return self
    }
}
