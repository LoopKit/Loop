//
//  MockSettingsStore.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
@testable import Loop

class MockLatestStoredSettingsProvider: LatestStoredSettingsProvider {
    var settings: StoredSettings { StoredSettings() }
    func storeSettings(_ settings: StoredSettings, completion: @escaping () -> Void) {
        completion()
    }
}
