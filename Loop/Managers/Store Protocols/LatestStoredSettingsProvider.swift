//
//  LatestStoredSettingsProvider.swift
//  Loop
//
//  Created by Anna Quinlan on 8/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

protocol LatestStoredSettingsProvider: AnyObject {
    var latestSettings: StoredSettings { get }
}

extension SettingsManager: LatestStoredSettingsProvider { }
