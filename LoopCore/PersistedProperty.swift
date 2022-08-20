//
//  PersistedProperty.swift
//  Loop
//
//  Created by Pete Schwamb on 5/29/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log

@propertyWrapper public struct PersistedProperty<Value> {
    let key: String
    let storageURL: URL

    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "PersistedProperty")

    public init(key: String, shared: Bool = false) {
        self.key = key

        let documents: URL

        if shared {
            let appGroup = Bundle.main.appGroupSuiteName
            guard let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
                preconditionFailure("Could not get a container directory URL. Please ensure App Groups are set up correctly in entitlements.")
            }
            documents = directoryURL.appendingPathComponent("com.loopkit.LoopKit", isDirectory: true)

        } else {
            guard let localDocuments = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
                preconditionFailure("Could not get a documents directory URL.")
            }
            documents = localDocuments
        }
        storageURL = documents.appendingPathComponent(key + ".plist")
    }

    public var wrappedValue: Value? {
        get {
            do {
                let data = try Data(contentsOf: storageURL)
                os_log(.info, "Reading %{public}@ from %{public}@", key, storageURL.absoluteString)
                guard let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? Value else {
                    os_log(.error, "Unexpected type for %{public}@", key)
                    return nil
                }
                return value
            } catch {
                os_log(.error, "Error reading %{public}@: %{public}@", key, error.localizedDescription)
            }
            return nil
        }
        set {
            guard let newValue = newValue else {
                do {
                    try FileManager.default.removeItem(at: storageURL)
                } catch {
                    os_log(.error, "Error deleting %{public}@: %{public}@", key, error.localizedDescription)
                }
                return
            }
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: newValue, format: .binary, options: 0)
                try data.write(to: storageURL, options: .atomic)
                os_log(.info, "Wrote %{public}@ to %{public}@", key, storageURL.absoluteString)
            } catch {
                os_log(.error, "Error saving %{public}@: %{public}@", key, error.localizedDescription)
            }
        }
    }
}
