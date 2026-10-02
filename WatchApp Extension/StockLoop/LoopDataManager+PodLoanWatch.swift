//
//  LoopDataManager+PodLoanWatch.swift
//  WatchApp Extension
//
//  Sport Mode on the watch's LoopDataManager: the phone relay context, the phone's CGM
//  configuration, phone contexts that arrive during a loan, and overrides on the wrist's dosing.
//

import Foundation
import LoopKit
import LoopCore
import WatchConnectivity

extension LoopDataManager {

    /// Called from `activeContext`'s `didSet`.
    func podLoanNoteContextChange(_ oldValue: WatchContext?) {
        guard FeatureFlags.sportModeEnabled else { return }
        // The phone's onboarding input to the gate, logged on change.
        let flag = activeContext?.isOnboardingCompleted
        if flag != oldValue?.isOnboardingCompleted || (oldValue == nil) != (activeContext == nil) {
            SportLog.event("gate", "phone context: onboardingCompleted=\(flag.map { String($0) } ?? "nil") (context \(activeContext == nil ? "NIL" : "present"), watchAuthored=\(activeContext?.isWatchAuthored == true)) [onboarding-gate]")
        }
    }

    /// Called from `updateContext(_:)`.
    func podLoanNotePhoneRelayContext(_ context: WatchContext) {
        // Keep the phone's relay apart from the active context, which is the watch's during a loan.
        if !context.isWatchAuthored {
            phoneRelayContext = context
        }
    }

    /// Called from `updateContext(_:)`: the phone's CGM configuration rides in each context.
    func podLoanAdoptCGMConfiguration(from context: WatchContext) {
        guard !context.isWatchAuthored,
              let configuration = context.cgmConfiguration.flatMap(SharedDeviceConfiguration.init(rawValue:)) else { return }
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.stack.loopManager.adoptCGMConfiguration(configuration)
    }

    /// Called from `updateContext(_:)` when a phone context is refused mid-loan.
    func podLoanAbsorbPhoneContextDuringLoan(_ context: WatchContext) {
        // Still store the relayed reading and post the notification the ingest path hangs off.
        if let newGlucoseSample = context.newGlucoseSample {
            Task {
                try? await self.glucoseStore?.addGlucoseSamples([newGlucoseSample])
            }
        }
        NotificationCenter.default.post(name: LoopDataManager.didUpdateContextNotification, object: self)
    }

    /// Non-nil only while the wrist is dosing.
    var loanControllerIfActive: PodLoanWatchController? {
        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
              session.loanController.isLoanActiveNonBlocking else { return nil }
        return session.loanController
    }

    /// Applies an override to the wrist's dosing and the loan's records during a loan, then the
    /// UI, then (best-effort) the phone, which is often off during a loan.
    func applyOverrideDuringLoan(_ loan: PodLoanWatchController,
                                 _ override: TemporaryScheduleOverride?,
                                 _ watchInfoUpdate: LoopSettingsUserInfo,
                                 presetId: String?,
                                 alertIdentifier: String?) async {
        loan.applyWristOverride(override)
        watchInfo = watchInfoUpdate
        do {
            try await WCSession.default.sendSetPreset(presetIdentifier: presetId, alertIdentifier: alertIdentifier)
        } catch {
            SportLog.event("override", "phone not told (\(error)) — the wrist holds the pod, so its own dosing is authoritative")
        }
    }
}
