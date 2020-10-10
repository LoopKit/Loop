//
//  INRelevantShortcutStore+Loop.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Intents
import os.log


@available(watchOSApplicationExtension 5.0, *)
extension INRelevantShortcutStore {
    func registerShortcuts() {
        var shortcuts = [INRelevantShortcut]()

        let carbShortcut = INShortcut(userActivity: .forDidAddCarbEntryOnWatch())
        let carbRelevantShortcut = INRelevantShortcut(shortcut: carbShortcut)
        carbRelevantShortcut.shortcutRole = .action
        carbRelevantShortcut.relevanceProviders = []

        shortcuts.append(carbRelevantShortcut)
        
        let overrideShortcut = INShortcut(userActivity: .forDidEnableOverrideOnWatch())
        let overrideRelevantShortcut = INRelevantShortcut(shortcut: overrideShortcut)
        overrideRelevantShortcut.shortcutRole = .action
        overrideRelevantShortcut.relevanceProviders = []

        shortcuts.append(overrideRelevantShortcut)

        setRelevantShortcuts(shortcuts) { (error) in
            if let error = error {
                os_log(.error, "Error specifying shortcuts: %{public}@", String(describing: error))
            }
        }
    }
}
