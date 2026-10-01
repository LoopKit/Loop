//
//  CarbList+PodLoan.swift
//  WatchApp Extension
//
//  What the stock Active Carbs list does while the WRIST holds the pod: it reads the loan's own
//  carb store, and it gains swipe-to-delete.
//

import SwiftUI
import LoopKit

extension CarbList {

    /// DURING A LOAN THIS LIST IS EDITABLE, and it reads a different store.
    ///
    /// The loan stack owns the authoritative carb store while the pod is on the wrist, so reading
    /// the stock store here would show the phone's copy and delete from the wrong book. Deletion
    /// exists for the same reason the loan exists at all: the phone may not be there to edit on.
    /// Off-loan the premise is the opposite — you have your phone — so this stays exactly as
    /// stock: the phone's entries, read-only.
    var loanSession: StockLoopSession? {
        guard let session = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession,
              session.loanController.isLoanActiveNonBlocking else { return nil }
        return session
    }

    /// Delete locally FIRST, then journal. The order is deliberate: the local store is what this
    /// loop cycle predicts from, so the next cycle should already reflect the deletion even if the
    /// journal mint fails — and a mint failure is loud rather than silent.
    private func delete(_ entry: StoredCarbEntry) {
        guard let session = loanSession else { return }
        let grams = entry.quantity.doubleValue(for: .gram)
        let syncIdentifier = entry.syncIdentifier
        let startDate = entry.startDate

        entries.removeAll { $0 == entry }   // optimistic: the row is gone, the loop recalculates
        SportLog.event("carb-ui", String(format: "wrist DELETE %.0f g @ %@ · sync=%@",
                                         grams, timeFormatter.string(from: startDate),
                                         syncIdentifier ?? "none(watch-entered)"))

        // deleteLoanCarbEntry invalidates carbEffect and re-runs the loop, so the prediction drops
        // the carb within seconds rather than at the next reading.
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
        // Swipe-to-delete only while the wrist holds the pod. Off-loan the phone owns
        // these entries and a delete here would edit the wrong book.
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
