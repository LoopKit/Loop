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
        SportLog.eventOnChange("gate", key: "stock-pages", "stock pages \(gate ? "shown" : "behind onboarding"): "
            + "\(loanIsLive ? "a loan is live" : "no loan is live"), \(phoneSaysOnboarded ? "phone onboarded" : "phone not onboarded")")
        return gate
    }

    /// Called from `body`'s `.onChange(of: selectedPage)`.
    func podLoanRememberPage(_ newValue: Int) {
        // Only pages 0/1 are remembered.
        if newValue < Self.sportPage {
            UserDefaults.standard.startOnChartPage = newValue == 1
        }
    }

    /// Called from `body`'s `.podLoanPhaseDidChange` receiver.
    func podLoanPhaseDidChange() {
        let live = glanceModel.loanInProgress
        loanIsLive = live
        if live { selectedPage = Self.sportPage }
    }

    /// Back to the glance after carbs or a bolus during a loan.
    func podLoanReturnToGlanceAfterFlow() {
        if glanceModel.loanInProgress { selectedPage = Self.sportPage }
    }

    /// Called from `body`'s `.task`.
    func podLoanSyncGateOnLaunch() {
        // Also right on a cold launch into a live loan, which posts no phase change.
        loanIsLive = glanceModel.loanInProgress
    }
}
