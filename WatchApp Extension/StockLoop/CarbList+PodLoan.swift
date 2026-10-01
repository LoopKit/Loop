//
//  CarbList+PodLoan.swift
//  WatchApp Extension
//
//  The Active Carbs list while the wrist holds the pod: it reads the loan's carb store and
//  allows swipe-to-delete.
//

import SwiftUI
import LoopKit

extension CarbList {

    /// During a loan: the loan's store, editable. Off-loan: stock, read-only.
    var loanSession: StockLoopSession? {
        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
              session.loanController.isLoanActiveNonBlocking else { return nil }
        return session
    }

    /// Delete locally first, so the next cycle reflects it, then journal.
    private func delete(_ entry: StoredCarbEntry) {
        guard let session = loanSession else { return }
        let grams = entry.quantity.doubleValue(for: .gram)
        let syncIdentifier = entry.syncIdentifier
        let startDate = entry.startDate

        entries.removeAll { $0 == entry }   // optimistic: the row is gone, the loop recalculates
        SportLog.event("carb-ui", String(format: "wrist DELETE %.0f g @ %@ · sync=%@",
                                         grams, timeFormatter.string(from: startDate),
                                         syncIdentifier ?? "none(watch-entered)"))

        // Re-runs the loop, so the prediction drops the carb at once.
        session.stack.loopManager.deleteLoanCarbEntry(entry) { ok in
            guard ok else {
                Task { @MainActor in
                    warning = NSLocalizedString("Couldn't delete", comment: "Watch carb list error when a delete fails")
                    await reloadCarbEntries()   // put the row back — it is still live and still dosing
                }
                return
            }
            session.loanController.loanDidDeleteCarb(syncIdentifier: syncIdentifier,
                                                     startDate: startDate,
                                                     grams: grams)
            Task { @MainActor in await reloadCarbEntries() }
        }
    }

    /// The swipe action's content, from `body`.
    @ViewBuilder
    func podLoanDeleteButton(_ entry: StoredCarbEntry) -> some View {
        // Only while the wrist holds the pod.
        if loanSession != nil {
            Button(role: .destructive) {
                delete(entry)
            } label: {
                Label(NSLocalizedString("Delete", comment: "Watch carb list swipe action"),
                      systemImage: "trash")
            }
        }
    }

    /// The section footer, from `body`.
    @ViewBuilder
    var podLoanWarningFooter: some View {
        if let warning {
            Text(warning).font(.caption).foregroundStyle(.orange)
        }
    }
}
