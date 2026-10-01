//
//  LoopDataManager+PodLoanWatch.swift
//  WatchApp Extension
//
//  What Sport Mode adds to the watch's LoopDataManager: the phone relay context, the direct read
//  of the phone's G7 pairing code, what becomes of a phone context that arrives while the wrist
//  holds the pod, and an override applied to the wrist's own dosing.
//

import Foundation
import LoopKit
import LoopCore
import WatchConnectivity
import G7SensorKit   // direct-auth pairing codes arrive inside the phone's cgmManagerState

extension LoopDataManager {

    /// Called from `activeContext`'s `didSet`.
    func podLoanNoteContextChange(_ oldValue: WatchContext?) {
        // Bench 2026-09-18: "Please complete onboarding" kept appearing and neither log
        // recorded WHY. The gate is `loanIsLive || isOnboardingCompleted`; this is the second
        // input, as the phone sent it. Logged on change only.
        let flag = activeContext?.isOnboardingCompleted
        if flag != oldValue?.isOnboardingCompleted || (oldValue == nil) != (activeContext == nil) {
            SportLog.event("gate", "phone context: onboardingCompleted=\(flag.map { String($0) } ?? "nil") (context \(activeContext == nil ? "NIL" : "present"), watchAuthored=\(activeContext?.isWatchAuthored == true)) [onboarding-gate]")
        }
    }

    /// Called from `updateContext(_:)`.
    func podLoanNotePhoneRelayContext(_ context: WatchContext) {
        // Keep the phone's own relay separately from whatever is currently active. During a
        // loan the active context is the WATCH's, so a caller that wants "what did the phone
        // last tell us" — the glucose fallback, for one — would otherwise be handed the
        // watch's own reading back and ingest nothing. `isWatchAuthored` is never encoded into
        // rawValue, so anything arriving from the phone reads false here.
        if !context.isWatchAuthored {
            phoneRelayContext = context
        }
    }

    /// Called from `updateContext(_:)`.
    func podLoanReadPairingCode(from context: WatchContext) {
        // DIRECT READ (2026-09-12): the phone's whole G7 state rides in every context as
        // `cgmManagerState`. Take the current sensor's pairing code from it, and let the G7
        // manager notice a sensor change by identity — the watch never scans to learn a new
        // sensor's name (ride-only must not), the phone tells it.
        // The phone sends `CGMManager.rawValue`, which WRAPS the state:
        // ["managerIdentifier": …, "state": G7CGMManagerState.rawValue]. The 2026-09-12 08:45
        // build read the keys at the top level and silently found nothing, so no code ever
        // reached the watch. Unwrap "state" (and tolerate an unwrapped dictionary).
        if !context.isWatchAuthored, let wrapped = context.cgmManagerState {
            let raw = wrapped["state"] as? [String: Any] ?? wrapped
            let code = raw["pairingCode"] as? String
            let phoneSensor = raw["sensorID"] as? String
            ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.stack.cgmManager
                .receivePairingCode(code, phoneSensorID: phoneSensor)
        }
    }

    /// Called from `updateContext(_:)` when a phone context is refused mid-loan.
    func podLoanAbsorbPhoneContextDuringLoan(_ context: WatchContext) {
        // NOT an early return on its own — two things still have to happen, and skipping
        // them kills the BACKUP GLUCOSE SOURCE during exactly the window it exists for:
        //   1. the relayed reading still belongs in the store, and
        //   2. the notification must still fire, because the ingest path hangs off it and it
        //      is normally posted by `activeContext`'s didSet, which we deliberately skip.
        if let newGlucoseSample = context.newGlucoseSample {
            Task {
                try? await self.glucoseStore?.addGlucoseSamples([newGlucoseSample])
            }
        }
        NotificationCenter.default.post(name: LoopDataManager.didUpdateContextNotification, object: self)
    }

    /// The dosing manager, when the WRIST is the one dosing. nil off-loan, where the phone is
    /// authoritative and these paths must keep their stock behaviour exactly.
    var loanDosingManagerIfActive: WatchLoopManager? {
        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
              session.loanController.isLoanActiveNonBlocking else { return nil }
        return session.stack.loopManager
    }

    /// Apply an override to the WRIST's dosing during a loan, and keep the UI in step with it.
    ///
    /// Without this, activating a preset mid-loan changed the display and nothing else. The
    /// reconciler `WatchLoopManager.applyWristOverride` existed and had ZERO callers, so the
    /// dosing override had exactly one writer for a loan's lifetime — the grant intake — while
    /// `watchInfo.scheduleOverride` was driven independently off the WCSession round-trip. Tap
    /// Jogging mid-run and the button highlights, the chart band redraws and ActiveOverrideView
    /// prints 21%, while `applyBasal`/`applySensitivity`/`applyCarbRatio` stay identity maps and
    /// the target falls through to the raw schedule: full-strength insulin toward the
    /// pre-exercise target, during exercise, with every screen saying otherwise.
    ///
    /// THE PHONE SEND IS BEST-EFFORT HERE, and that inversion is the point. Off-loan the send
    /// must throw, because the phone owns the therapy and a preset it never heard about would be
    /// a lie. On-loan the WRIST owns it, and the phone is routinely switched off — which is
    /// exactly when the previous code failed hardest. `sendSetPreset` threw before `watchInfo`
    /// was written, so an ABSENT phone produced an honest no-op while a REACHABLE one produced
    /// the silent therapy divergence. The feature was least broken when the phone was away.
    ///
    /// Local application first, then the UI, then the phone: the two things that must agree are
    /// what doses and what is displayed, and neither may wait on a radio.
    func applyOverrideDuringLoan(_ manager: WatchLoopManager,
                                         _ override: TemporaryScheduleOverride?,
                                         _ watchInfoUpdate: LoopSettingsUserInfo,
                                         presetId: String?,
                                         alertIdentifier: String?) async {
        manager.applyWristOverride(override)
        watchInfo = watchInfoUpdate
        do {
            try await WCSession.default.sendSetPreset(presetIdentifier: presetId, alertIdentifier: alertIdentifier)
        } catch {
            SportLog.event("override", "phone not told (\(error)) — the wrist holds the pod, so its own dosing is authoritative")
        }
    }
}
