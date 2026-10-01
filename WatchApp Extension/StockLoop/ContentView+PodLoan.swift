//
//  ContentView+PodLoan.swift
//  WatchApp Extension
//
//  What Sport Mode adds to the watch app's root view: the page index the glance lives at, the
//  per-page onboarding gate, and what the root does when a loan starts or a carb/bolus flow ends.
//

import SwiftUI

extension ContentView {

    /// The glance's page index. Named rather than written inline because a live loan lands the
    /// user here, and a bare `2` at that call site would be a silent dependency on page order.
    static let sportPage = 2

    /// Stock's onboarding gate, applied per PAGE instead of to the whole app.
    ///
    /// The stock pages have nothing to show until the phone reports both managers onboarded, so
    /// they still show stock's prompt. Sport Mode and diagnostics stay reachable regardless: the
    /// wrist has its own stores, its own CGM and its own log, and the diagnostics page is how you
    /// find out WHY the phone says onboarding is incomplete. Gating it behind the very flag you
    /// are trying to debug is the wrong way round.
    ///
    /// A LIVE LOAN OPENS THE GATE ON ITS OWN. The flag this consults is the PHONE's — set from the
    /// phone's own CGM and pump onboarding state, and reaching the wrist inside a context update.
    /// During a loan the phone may be switched off entirely, so it cannot arrive: waiting for it
    /// blanks precisely the screens the wrist needs while it is the one holding the pod. The watch
    /// is authoritative then, with its own stores and its own CGM, so the phone's readiness is not
    /// the question being asked.
    var isOnboarded: Bool {
        let phoneSaysOnboarded = loopManager.activeContext?.isOnboardingCompleted == true
        let gate = loanIsLive || phoneSaysOnboarded
        // Bench 2026-09-18: log the DECISION with both inputs, on change only (SwiftUI evaluates
        // this on every render). Pairs with the "[onboarding-gate]" line in LoopDataManager.
        let key = "\(gate)|\(loanIsLive)|\(phoneSaysOnboarded)"
        if key != Self.lastGateKey {
            Self.lastGateKey = key
            SportLog.event("gate", "stock pages \(gate ? "SHOWN" : "BEHIND onboarding") — loanIsLive=\(loanIsLive) phoneSaysOnboarded=\(phoneSaysOnboarded) [onboarding-gate]")
        }
        return gate
    }
    static var lastGateKey = ""

    /// Called from `body`'s `.onChange(of: selectedPage)`.
    func podLoanRememberPage(_ newValue: Int) {
        // Only pages 0/1 are remembered; landing on Sport is a consequence of a live loan,
        // not a preference to restore on next launch.
        if newValue < Self.sportPage {
            UserDefaults.standard.startOnChartPage = newValue == 1
        }
    }

    /// Called from `body`'s `.podLoanPhaseDidChange` receiver.
    func podLoanPhaseDidChange() {
        let live = glanceModel.wantsFocus || glanceModel.loanIsLive   // the controller's flag covers a resume
        loanIsLive = live
        if live { selectedPage = Self.sportPage }
    }

    /// Finishing a carb entry or a bolus during a loan returns to the glance.
    ///
    /// Gated on `wantsFocus` rather than applied always, so this never yanks the page away from
    /// someone using the watch as a plain remote.
    func podLoanReturnToGlanceAfterFlow() {
        if glanceModel.wantsFocus { selectedPage = Self.sportPage }
    }

    /// Called from `body`'s `.task`.
    func podLoanSyncGateOnLaunch() {
        // The gate also has to be right on a COLD LAUNCH into a live loan — relaunching
        // mid-session posts no phase change, and that is exactly when the watch is holding
        // the pod and needs these pages.
        loanIsLive = glanceModel.wantsFocus || glanceModel.loanIsLive
    }
}
