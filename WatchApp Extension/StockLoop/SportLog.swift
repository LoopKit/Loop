//
//  SportLog.swift
//  WatchApp Extension
//
//  Sport Mode's log on the watch, through the watch app's log. Each line carries a [category].
//

import Foundation
import os.log

enum SportLog {
    private static let log = OSLog(category: "SportMode")

    /// `category` names the part of Sport Mode the line is about.
    static func event(_ category: String, _ message: String) {
        log.default("[%{public}@] %{public}@", category, message)
    }

    private static let lastLock = NSLock()
    private static var lastByKey: [String: String] = [:]

    /// As `event`, but only when the message differs from the last one logged under `key`: for lines
    /// written on every wake that rarely change.
    static func eventOnChange(_ category: String, key: String, _ message: String) {
        lastLock.lock()
        let changed = lastByKey[key] != message
        if changed { lastByKey[key] = message }
        lastLock.unlock()
        if changed { event(category, message) }
    }
}
