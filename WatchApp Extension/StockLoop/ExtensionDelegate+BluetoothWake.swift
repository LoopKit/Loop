//
//  ExtensionDelegate+BluetoothWake.swift
//  WatchApp Extension
//
//  The Bluetooth wake: how the watch app accounts for `WKBluetoothAlertRefreshBackgroundTask`,
//  which is how watchOS hands the app the runtime a daemon-held G7 connect earned it.
//
//  The three counters this works on are instance stored properties, so they stay on the stock
//  delegate; everything that reads them lives here.
//

import Foundation
import WatchKit

extension ExtensionDelegate {

    /// A held task older than this is from a previous wake whose 25-s timer never fired (the
    /// process was suspended under it): complete it and start a fresh hold.
    private static let bluetoothWakeStaleAfter: TimeInterval = 60

    /// Called from `handle(_ backgroundTasks:)`, once per delivery.
    func podLoanNoteBackgroundTasks(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        let bluetoothOnly = backgroundTasks.allSatisfy { $0 is WKBluetoothAlertRefreshBackgroundTask }
        if !bluetoothOnly {
            let kinds = backgroundTasks.map { String(describing: type(of: $0)) }.sorted().joined(separator: ",")
            SportLog.event("lifecycle", "background tasks [\(kinds)] on main [bt-task]")
        }
    }

    // watchOS 9+: "Updates from Bluetooth are available to the application." The G7
    // central opts into state restoration, so a daemon-held sensor connect relaunches
    // the app and this task is how watchOS hands it the wake. ONE task is held per wake
    // (25 s, or until the system expires it — the grant, ≈20 s on 2026-09-14); every
    // further delivery in the same wake is completed on arrival and counted. The
    // 2026-09-14 event run held every one of ~55 deliveries per wake with its own timer
    // and ledger write, and the pile stalled main 4 s on the next resume.
    func holdBluetoothTask(_ task: WKBluetoothAlertRefreshBackgroundTask) {
        dispatchPrecondition(condition: .onQueue(.main))
        bluetoothDeliveriesThisWake += 1
        if let since = heldBluetoothTaskSince, heldBluetoothTask != nil {
            if Date().timeIntervalSince(since) < Self.bluetoothWakeStaleAfter {
                task.setTaskCompletedWithSnapshot(false)   // same wake: coalesced
                return
            }
            completeHeldBluetoothTask("stale — a new wake arrived")
            bluetoothDeliveriesThisWake = 1
        }
        let delivered = Date()
        heldBluetoothTask = task
        heldBluetoothTaskSince = delivered
        SportLog.event("radio", "WOKEN BY BLUETOOTH — WKBluetoothAlertRefreshBackgroundTask; holding one task 25 s [bt-task]")
        // The system's own lifetime grant for this task, measured: it calls this before it
        // terminates the task, and the log stamp says how long it gave us.
        task.expirationHandler = { [weak self] in
            SportLog.event("radio", String(format: "Bluetooth background task EXPIRED by the system after %.1f s — that is the grant [bt-task]", Date().timeIntervalSince(delivered)))
            DispatchQueue.main.async { self?.completeHeldBluetoothTask("expired", only: task) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.completeHeldBluetoothTask("25 s hold over", only: task) }
    }

    /// Complete the held task. `only` guards a late timer or expiration from completing a
    /// NEWER hold than the one it was armed for.
    private func completeHeldBluetoothTask(_ why: String, only: WKBluetoothAlertRefreshBackgroundTask? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let task = heldBluetoothTask, let since = heldBluetoothTaskSince else { return }
        if let only = only, only !== task { return }
        SportLog.event("radio", String(format: "Bluetooth background task completed after %.1f s (%@) · %d deliveries coalesced this wake [bt-task]", Date().timeIntervalSince(since), why, bluetoothDeliveriesThisWake))
        task.setTaskCompletedWithSnapshot(false)
        heldBluetoothTask = nil
        heldBluetoothTaskSince = nil
        bluetoothDeliveriesThisWake = 0
    }
}
