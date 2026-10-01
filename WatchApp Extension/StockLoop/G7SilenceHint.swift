//
//  G7SilenceHint.swift
//  WatchApp
//
//  One line on the glance when the watch's own Bluetooth stack looks parked: sensor bursts are
//  due, nothing is being read, and the phone is not covering the gap either.
//
//  This is about the WATCH's radio, not about the Dexcom app — the watch authenticates with the
//  sensor itself and shares nothing with it. The copy must name the WATCH's Bluetooth: toggling
//  the phone's does nothing for a parked watch stack, and a hint that sends the user to the
//  wrong device is worse than none.
//
//  It is a hint, not an alert: it appears on a screen the user is already looking at and raises
//  nothing.
//

import Foundation

enum G7SilenceHint {
    /// A new sensor is quiet for its warm-up by design, and the watch cannot read it during that
    /// time however healthy its radio is. Generous on purpose — suppressing a true hint for a
    /// while costs a delay, while telling someone to toggle Bluetooth at a sensor they have just
    /// put on costs their trust in the line.
    static let warmupAllowance: TimeInterval = .hours(2.5)

    /// nil unless the silence is really the watch's to fix.
    ///
    /// - `directAge`: since this watch last read the sensor itself.
    /// - `relayAge`: since the phone last relayed a reading. A phone still relaying means glucose
    ///   is arriving, which is not the failure this line describes.
    /// - `sensorAge`: since the current sensor was started, when that is known.
    ///
    /// The direct age alone cannot tell a parked radio from a sensor change: both look like a
    /// last reading that keeps getting older, because that reading came from the sensor being
    /// replaced. Without the sensor's own age this line told the user to toggle Bluetooth for
    /// the whole warm-up after every sensor change.
    static func text(directAge: TimeInterval?, relayAge: TimeInterval?, sensorAge: TimeInterval? = nil) -> String? {
        // Two missed bursts by construction on the G7's 300 s grid, so one skipped window stays quiet.
        guard let age = directAge, age >= 10.5 * 60 else { return nil }
        if let r = relayAge, r < 10 * 60 { return nil }
        if let sensorAge, sensorAge < warmupAllowance { return nil }
        return String(format: NSLocalizedString("G7 silent %d min · try toggling watch Bluetooth", comment: "Glance line when the watch has missed two or more sensor bursts (1: minutes since the last direct reading)"), Int(age / 60))
    }
}
