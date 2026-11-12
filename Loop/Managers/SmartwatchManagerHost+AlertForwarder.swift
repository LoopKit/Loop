//
//  SmartwatchManagerHost+AlertForwarder.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopAlgorithm
import LoopKit

extension SmartwatchManagerHost: AlertForwarder {
    /// Forwards Loop's immediate, unmuted alerts to the watch so it buzzes in step
    /// with the phone. Delayed/repeating alerts are left to the phone's notification
    /// schedule. Muted alerts are not sent: Loop's mute covers critical alerts too
    /// (they are delivered at volume 0), so the watch follows the mute for every
    /// alert. Each alert that isn't sent is logged with the reason.
    func alertManager(_ manager: AlertManager, didIssueAlert alert: Alert, muted: Bool) {
        guard let smartwatchManager = deviceManager.smartwatchManager else {
            return
        }
        let content = alert.foregroundContent ?? alert.backgroundContent
        // Log why an alert doesn't reach the watch, so a watch alert level of 0
        // can be explained from the device log.
        // The watch is a glucose display, so only forward glucose alerts (from
        // GlucoseAlertManager). Pump/pod reminders, CGM sensor-expiry and other
        // system alerts stay on the phone. This also avoids a stale watch level:
        // a pod reminder is acknowledged but never retracted, so it would otherwise
        // linger in the plugin's active set forever.
        guard alert.identifier.managerIdentifier == GlucoseAlertManager.managerIdentifier else {
            // Device log only: override reminders, pod alerts and the like never
            // reach the watch, so they would only clutter the watch's own log.
            logAlert(smartwatchManager, "\(content.title) not sent to the watch: only glucose alerts are forwarded", showInPluginLog: false)
            return
        }
        guard case .immediate = alert.trigger else {
            logAlert(smartwatchManager, "\(content.title) not sent to the watch: it is scheduled for later, and only immediate alerts are forwarded")
            return
        }
        guard !muted else {
            logAlert(smartwatchManager, "\(content.title) not sent to the watch: Loop's alerts are muted")
            return
        }
        smartwatchManager.watchAlertDidIssue(alert, glucoseAlertType: Self.glucoseAlertType(of: alert.identifier), issuedAt: Date())
        // Loop never retracts a test alert: clear it on the watch once it has shown.
        if Self.isTestAlert(alert.identifier) {
            lastWatchTestAlertAt = Date()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Self.watchTestAlertDuration * 1_000_000_000))
                guard let current = self.deviceManager.smartwatchManager else { return }
                self.retractWatchAlertsNoLongerShown(current)
            }
        }
        // Queued after the plugin's own "issued" line, which also hops to the main
        // actor. Uses the unit the watch reads (HealthKit's stored one).
        let firedAt = Date()
        Task { @MainActor in
            let unit = await self.preferredGlucoseUnit()
            if let note = self.nextAlertNote(for: alert, unit: unit, now: firedAt) {
                self.logAlert(smartwatchManager, note)
            }
        }
    }

    /// When Loop will alert again for a glucose alert it just fired, and what
    /// clears it, so the device log explains the next phone alert and watch buzz.
    /// Reads GlucoseAlertManager's active settings; the alert fired just now, so a
    /// repeat is due one repeat interval from now, on the first reading from then.
    private func nextAlertNote(for alert: Alert, unit: LoopUnit, now: Date) -> String? {
        let config = deviceManager.glucoseAlertManager.activeConfiguration(at: now)
        let title = (alert.foregroundContent ?? alert.backgroundContent).title
        let rule: (above: Bool, threshold: Double, repeatInterval: TimeInterval?)
        switch alert.identifier.alertIdentifier {
        case GlucoseAlertManager.highAlertIdentifier:
            rule = (true, config.highThresholdMgDL, config.highSnoozeEnabled ? config.highRepeatInterval : nil)
        case GlucoseAlertManager.lowAlertIdentifier:
            rule = (false, config.lowThresholdMgDL, config.lowSnoozeEnabled ? config.lowRepeatInterval : nil)
        case GlucoseAlertManager.urgentLowAlertIdentifier:
            rule = (false, config.urgentLowThresholdMgDL, config.urgentLowRepeatInterval)
        case GlucoseAlertManager.predictedLowAlertIdentifier:
            return "Next alert: \(title) doesn't repeat; it fires once per predicted low."
        default:
            return nil
        }
        let margin = config.recoveryMarginMgDL
        let level = glucoseText(rule.threshold, unit: unit)
        let clearLevel = glucoseText(rule.above ? rule.threshold - margin : rule.threshold + margin, unit: unit)
        let side = rule.above ? "above" : "below"
        let recovers = rule.above ? "falls below" : "rises above"
        guard let repeatInterval = rule.repeatInterval else {
            return "Next alert: \(title) doesn't repeat (repeat is off). It fires again only after glucose \(recovers) \(clearLevel) and then goes \(side) \(level) again."
        }
        let next = now.addingTimeInterval(repeatInterval)
        return "Next alert: if glucose is still \(side) \(level), Loop repeats \(title) and forwards it to the watch at the first reading from \(timeText(next)) (every \(intervalText(repeatInterval))). It clears once glucose \(recovers) \(clearLevel)."
    }

    private func glucoseText(_ milligramsPerDeciliter: Double, unit: LoopUnit) -> String {
        let quantity = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: milligramsPerDeciliter)
        return QuantityFormatter(for: unit).string(from: quantity) ?? "\(Int(milligramsPerDeciliter)) mg/dL"
    }

    private func timeText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        }
        if calendar.isDateInTomorrow(date) {
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short) + " tomorrow"
        }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

    private func intervalText(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// Retractions of glucose alerts, the only ones forwarded, so an alert the
    /// watch was given doesn't stay active there.
    func alertManager(_ manager: AlertManager, didRetractAlertWithIdentifier identifier: Alert.Identifier) {
        guard let smartwatchManager = deviceManager.smartwatchManager,
              identifier.managerIdentifier == GlucoseAlertManager.managerIdentifier
        else {
            return
        }
        smartwatchManager.watchAlertDidRetract(identifier)
    }
}
