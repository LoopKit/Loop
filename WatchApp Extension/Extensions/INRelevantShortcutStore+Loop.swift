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

        let shortcut = INShortcut(userActivity: .forDidAddCarbEntryOnWatch())
        let relevance = INRelevantShortcut(shortcut: shortcut)
        relevance.shortcutRole = .action
        relevance.relevanceProviders = []

        shortcuts.append(relevance)

        setRelevantShortcuts(shortcuts) { (error) in
            if let error = error {
                os_log(.error, "Error specifying shortcuts: %{public}@", String(describing: error))
            }
        }
    }
}
