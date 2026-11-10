//
//  PhoneLog.swift
//  Loop
//
//  Sport Mode's log on the phone, through Loop's diagnostic log. Each line carries a [category].
//

import Foundation

enum PhoneLog {
    private static let log = DiagnosticLog(category: "SportMode")

    /// `category` names the part of Sport Mode the line is about.
    static func event(_ category: String, _ message: String) {
        log.default("[%{public}@] %{public}@", category, message)
    }
}
