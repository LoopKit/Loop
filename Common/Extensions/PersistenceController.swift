//
//  PersistenceController.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopKit


extension PersistenceController {
    class func controllerInAppGroupDirectory() -> PersistenceController {
        let appGroup = Bundle.main.appGroupSuiteName
        guard let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            assertionFailure("Could not get a container directory URL. Please ensure App Groups are set up correctly in entitlements.")
            return self.init(directoryURL: URL(fileURLWithPath: "/"))
        }

        let isReadOnly = Bundle.main.bundleURL.pathExtension == "appex"

        return self.init(directoryURL: directoryURL.appendingPathComponent("com.loopkit.LoopKit", isDirectory: true), isReadOnly: isReadOnly)
    }
}
