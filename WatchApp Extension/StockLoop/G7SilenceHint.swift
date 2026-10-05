//
//  G7SilenceHint.swift
//  WatchApp
//
//  One glance line when the watch's own Bluetooth looks parked: bursts due, nothing read,
//  and the phone not covering. It names the watch's Bluetooth, not the phone's.
//

import Foundation

enum G7SilenceHint {
    /// A new sensor cannot be read during warm-up.
    static let warmupAllowance: TimeInterval = .hours(2.5)

    /// nil unless the watch can fix it. Ages: since this watch's read, the phone's relay, and sensor start.
    static func text(directAge: TimeInterval?, relayAge: TimeInterval?, sensorAge: TimeInterval? = nil) -> String? {
        // Two missed bursts by construction on the G7's 300 s grid, so one skipped window stays quiet.
        guard let age = directAge, age >= 10.5 * 60 else { return nil }
        if let r = relayAge, r < 10 * 60 { return nil }
        if let sensorAge, sensorAge < warmupAllowance { return nil }
        return String(format: NSLocalizedString("G7 silent %d min · try toggling watch Bluetooth", comment: "Glance line when the watch has missed two or more sensor bursts (1: minutes since the last direct reading)"), Int(age / 60))
    }
}
