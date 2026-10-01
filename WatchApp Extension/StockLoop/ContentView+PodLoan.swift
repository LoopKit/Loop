//
//  ContentView+PodLoan.swift
//  WatchApp Extension
//
//  Sport Mode's additions to the root view: the glance page, the per-page onboarding gate,
//  and returning to the glance after a flow.
//

import SwiftUI

extension ContentView {

    /// A live loan lands the user here.
    static let sportPage = 2

    /// Stock's onboarding gate per page: stock pages keep it; Sport Mode and diagnostics stay
    /// reachable. A live loan opens it, since the phone (whose flag this is) may be off.
    var isOnboarded: Bool {
        let phoneSaysOnboarded = loopManager.activeContext?.isOnboardingCompleted == true
        guard FeatureFlags.sportModeEnabled else { return phoneSaysOnboarded }
        let gate = loanIsLive || phoneSaysOnboarded
        // Logged on change; pairs with [onboarding-gate] in LoopDataManager.
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
        // Only pages 0/1 are remembered.
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

    /// Back to the glance after carbs or a bolus during a loan, only when `wantsFocus`.
    func podLoanReturnToGlanceAfterFlow() {
        if glanceModel.wantsFocus { selectedPage = Self.sportPage }
    }

    /// Called from `body`'s `.task`.
    func podLoanSyncGateOnLaunch() {
        // Also right on a cold launch into a live loan, which posts no phase change.
        loanIsLive = glanceModel.wantsFocus || glanceModel.loanIsLive
    }
}
