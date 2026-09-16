//
//  CriticalAlertAlarmScheduler.swift
//  Loop
//
//  On iOS 26+ builds without the Critical Alerts entitlement, this schedules
//  an AlarmKit alarm as the audible critical-alert channel instead of the
//  AVAudioPlayer + AVAudioSession + volume-booster + vibration hack in
//  CriticalAlertAudioPlayer. AlarmKit breaks through the silent switch, Focus
//  and Do Not Disturb with a system-rendered alarm, and is far more reliable
//  than driving the system volume ourselves.
//
//  Requires the user to grant AlarmKit authorization (requested during
//  onboarding). When AlarmKit is unavailable (iOS < 26) or unauthorized,
//  callers fall back to CriticalAlertAudioPlayer.
//

import Foundation
import LoopKit
import os.log

#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import struct SwiftUI.Color   // Color only; `import SwiftUI` would make `Alert` ambiguous with LoopKit.Alert
#endif

@MainActor
final class CriticalAlertAlarmScheduler {
    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "CriticalAlertAlarmScheduler")

    /// Maps an issued alert to the AlarmKit alarm scheduled for it, so the
    /// alarm can be cancelled when the alert is acknowledged or retracted.
    private var alarmsByAlert: [Alert.Identifier: UUID] = [:]

    /// True only if AlarmKit is available (iOS 26+) AND the user authorized it.
    /// When false, callers should use the CriticalAlertAudioPlayer fallback.
    var isAuthorizedAndAvailable: Bool {
        guard #available(iOS 26, *) else { return false }
        #if canImport(AlarmKit)
        return AlarmManager.shared.authorizationState == .authorized
        #else
        return false
        #endif
    }

    /// Request AlarmKit authorization if it hasn't been decided yet. Called
    /// during onboarding. No-op below iOS 26 or once already granted/denied.
    static func requestAuthorization() async {
        guard #available(iOS 26, *) else { return }
        #if canImport(AlarmKit)
        guard AlarmManager.shared.authorizationState == .notDetermined else { return }
        do {
            _ = try await AlarmManager.shared.requestAuthorization()
        } catch {
            os_log("AlarmKit authorization request failed: %{public}@",
                   log: OSLog(subsystem: "com.loopkit.Loop", category: "CriticalAlertAlarmScheduler"),
                   type: .error, String(describing: error))
        }
        #endif
    }

    /// How far in the future to schedule the "immediate" alarm. AlarmKit fixed
    /// alarms ring at a future wall-clock moment; a now/past date schedules
    /// silently and never fires, so we nudge it a couple seconds ahead.
    private static let immediateFireDelay: TimeInterval = 2

    /// Schedule an (effectively immediate) AlarmKit alarm for the alert. Returns
    /// true if AlarmKit will handle it (so the caller skips the audio fallback),
    /// false if AlarmKit isn't usable and the caller should fall back now.
    /// `onScheduleFailure` runs if the async schedule throws, so the caller can
    /// still play the audio fallback rather than leaving the alert silent.
    @discardableResult
    func scheduleAlarm(for alert: Alert, onScheduleFailure: @escaping () -> Void) -> Bool {
        guard #available(iOS 26, *), isAuthorizedAndAvailable else { return false }
        #if canImport(AlarmKit)
        // Replace any existing alarm for this alert.
        cancelAlarm(for: alert.identifier)

        let title = alert.backgroundContent.title

        let stopButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: NSLocalizedString("Stop", comment: "Stop button on the AlarmKit critical alarm")),
            textColor: .white,
            systemImageName: "stop.circle"
        )
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: stopButton
            )
        )
        let attributes = AlarmAttributes<EmptyAlarmMetadata>(presentation: presentation, tintColor: .red)

        // Fire immediately. No countdownDuration (preAlert nil) → alert-only,
        // so no Widget Extension / Live Activity is required. The stop button
        // runs StopCriticalAlertIntent, which acknowledges the corresponding
        // Loop alert (in addition to AlarmKit stopping the alarm).
        //
        // The alert's configured sound is a bundled IMA4 .caf under 30s, which
        // is the same constraint as a notification sound, so AlarmKit can play
        // it by name from the main bundle.
        let sound: AlertConfiguration.AlertSound = alert.sound?.filename.map { .named($0) } ?? .default
        let configuration = AlarmManager.AlarmConfiguration<EmptyAlarmMetadata>.alarm(
            schedule: .fixed(Date().addingTimeInterval(Self.immediateFireDelay)),
            attributes: attributes,
            stopIntent: StopCriticalAlertIntent(identifier: alert.identifier),
            sound: sound
        )

        let id = UUID()
        alarmsByAlert[alert.identifier] = id
        let log = self.log
        let identifier = alert.identifier
        Task { [weak self] in
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                os_log("Scheduled AlarmKit alarm %{public}@ for %{public}@", log: log, type: .info, id.uuidString, String(describing: identifier))
            } catch {
                os_log("Failed to schedule AlarmKit alarm for %{public}@: %{public}@ — falling back to audio", log: log, type: .error, String(describing: identifier), String(describing: error))
                self?.alarmsByAlert.removeValue(forKey: identifier)
                onScheduleFailure()
            }
        }
        return true
        #else
        return false
        #endif
    }

    /// Cancel/stop the AlarmKit alarm scheduled for the given alert, if any.
    func cancelAlarm(for identifier: Alert.Identifier) {
        guard #available(iOS 26, *) else { return }
        #if canImport(AlarmKit)
        guard let id = alarmsByAlert.removeValue(forKey: identifier) else { return }
        // stop() ends a ringing alarm; cancel() removes a scheduled one. The
        // alarm may be in either state, so try both and ignore errors.
        try? AlarmManager.shared.stop(id: id)
        try? AlarmManager.shared.cancel(id: id)
        os_log("Cancelled AlarmKit alarm %{public}@ for %{public}@", log: log, type: .info, id.uuidString, String(describing: identifier))
        #endif
    }
}

/// Hands the AlarmKit Stop button's tap back to the AlertManager so the
/// corresponding Loop alert is acknowledged (not just silenced). The Stop
/// button runs `StopCriticalAlertIntent` in the app process; the intent is
/// reconstructed by the system and has no reference to the live AlertManager,
/// so it routes through this shared bridge. AlertManager registers the handler;
/// taps that arrive before it's registered (e.g. the app was relaunched to run
/// the intent) are queued and flushed once it is.
@MainActor
final class CriticalAlertAcknowledgementBridge {
    static let shared = CriticalAlertAcknowledgementBridge()
    private init() {}

    private var handler: ((Alert.Identifier) async -> Void)?
    private var pending: [Alert.Identifier] = []

    func setHandler(_ handler: @escaping (Alert.Identifier) async -> Void) {
        self.handler = handler
        guard !pending.isEmpty else { return }
        let queued = pending
        pending = []
        Task { for identifier in queued { await handler(identifier) } }
    }

    func acknowledge(_ identifier: Alert.Identifier) async {
        if let handler {
            await handler(identifier)
        } else {
            pending.append(identifier)
        }
    }
}

#if canImport(AlarmKit)
/// Minimal metadata for Loop critical-alert alarms. We present an alert-only
/// alarm (no countdown / custom Live Activity), so this carries nothing.
@available(iOS 26, *)
struct EmptyAlarmMetadata: AlarmMetadata {
    init() {}
}

/// Run in the app process when the user taps Stop on an AlarmKit critical
/// alarm. Acknowledges the Loop alert it was scheduled for, via the shared
/// bridge. Carries the alert identifier as parameters so the system can
/// reconstruct it.
@available(iOS 26, *)
struct StopCriticalAlertIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Glucose Alarm"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Manager Identifier") var managerIdentifier: String
    @Parameter(title: "Alert Identifier") var alertIdentifier: String

    init() {}

    init(identifier: Alert.Identifier) {
        self.managerIdentifier = identifier.managerIdentifier
        self.alertIdentifier = identifier.alertIdentifier
    }

    func perform() async throws -> some IntentResult {
        await CriticalAlertAcknowledgementBridge.shared.acknowledge(
            Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: alertIdentifier)
        )
        return .result()
    }
}
#endif
