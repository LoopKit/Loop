//
//  CarbAndBolusFlow+PodLoan.swift
//  WatchApp Extension
//
//  Whether the wrist is the one holding the pod, as the carb-and-bolus flow's own views ask it.
//

import SwiftUI

extension CarbAndBolusFlow {

    /// Non-blocking read (a view must never sync onto the loan controller's queue).
    var loanIsActive: Bool {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.loanController.isLoanActiveNonBlocking ?? false
    }
}
