//
//  LoopDataManager+PodLoanWatch.swift
//  WatchApp Extension
//
//  Sport Mode on the watch's LoopDataManager: the watch's own CGM readings and the phone's relayed
//  ones reaching the loop, the watch's sensor kept during a loan, and overrides on the wrist's dosing.
//

import Foundation
import LoopKit
import LoopCore
import WatchConnectivity

extension LoopDataManager {

    /// Called from `addDirectGlucose(_:)` once the store has the watch's own reading: Sport Mode's loop reacts.
    func podLoanNoteDirectGlucose(_ samples: [NewGlucoseSample], storedNew: Bool) {
        guard let loopManager = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.stack.loopManager else { return }
        loopManager.noteCGMManager(WatchCGMHost.shared.cgmManager)
        loopManager.didStoreDirectGlucose(samples, storedNew: storedNew)
    }

    /// Called from `directGlucoseDidEnd()`: the watch let go of the sensor.
    func podLoanNoteDirectGlucoseEnded() {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.stack.loopManager.noteCGMManager(nil)
    }

    /// Called from `directGlucoseUnreliable()`: the watch holding the pod cancels a high temp, as the phone does.
    func podLoanNoteDirectGlucoseUnreliable() {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.stack.loopManager.receivedUnreliableGlucose()
    }

    /// While the wrist owns the alarms (taking over, live, handing back, draining, resuming), a reading
    /// the phone relayed and the store took is offered to the wrist's loop and alarms. The phone's copy
    /// of a reading often lands before the watch's own, which then stores nothing new, so this is
    /// what runs the cycle for it.
    func podLoanNoteRelayedGlucose(_ sample: NewGlucoseSample, storedNew: Bool) {
        guard storedNew, let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
              session.loanController.wristOwnsAlarms else { return }
        session.stack.loopManager.didStorePhoneGlucose(sample)
    }

    /// Stock's CGM follows the phone's sharing in each context, except while the wrist owns the alarms:
    /// it keeps reading the sensor it doses from, and the context is only a wake for its acquisition.
    func podLoanUpdateWatchCGM(from context: WatchContext) {
        if ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.wristOwnsAlarms == true {
            WatchCGMHost.shared.recheckAcquisition()
        } else {
            WatchCGMHost.shared.update(from: context)
        }
    }

    /// From a loan's takeover until its records are home the carb store holds carbs the phone does not
    /// have yet, which the phone's carb sync (a wholesale replace) would erase.
    var pausesPhoneCarbSync: Bool {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.wristOwnsAlarms ?? false
    }

    /// Non-nil only while the wrist is dosing.
    var loanControllerIfActive: PodLoanWatchController? {
        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
              session.loanController.isLoanActive else { return nil }
        return session.loanController
    }

    /// Applies an override to the wrist's dosing and the loan's records during a loan (the screens
    /// show the loop's), then (best-effort) the phone, which is often off during a loan.
    func applyOverrideDuringLoan(_ loan: PodLoanWatchController,
                                 _ override: TemporaryScheduleOverride?,
                                 presetId: String?,
                                 alertIdentifier: String?) async {
        loan.applyWristOverride(override)
        do {
            try await WCSession.default.sendSetPreset(presetIdentifier: presetId, alertIdentifier: alertIdentifier)
        } catch {
            SportLog.event("override", "phone not told of the override: \(error)")
        }
    }
}
