//
//  PersistedProperty+Directory.swift
//  LoopCore
//
//  Stock's persisted property, stored in a folder the owner chooses.
//

import Foundation

extension PersistedProperty {
    /// The same storage in a chosen folder, for owners whose tests inject one.
    public init(key: String, directory: URL) {
        self.key = key
        storageURL = directory.appendingPathComponent(key + ".plist")
    }
}
