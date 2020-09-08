//
//  SettingsStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

protocol SettingsStoreProtocol: AnyObject {
    func storeSettings(_ settings: StoredSettings, completion: @escaping () -> Void)
}

extension SettingsStore: SettingsStoreProtocol { }
