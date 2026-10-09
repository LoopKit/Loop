//
//  ExtensionDelegate+BluetoothWake.swift
//  WatchApp Extension
//
//  `WKBluetoothAlertRefreshBackgroundTask`: the runtime a daemon-held G7 connect earns the app.
//

import Foundation
import WatchKit

extension ExtensionDelegate {

    /// A held task older than this is from a previous wake.
    private static let bluetoothWakeStaleAfter: TimeInterval = 60

    /// Tasks already completed, kept (not just their identities) so a freed address cannot be
    /// mistaken for a new task. WatchKit can hand a task over again, also in a LATER wake, and
    /// completing one twice throws: crash 2026-09-29, and 2026-10-07 13:26 ("NSMapTable count
    /// underflow") six completions after a new wake had cleared this list. So it is never cleared.
    private static var completedBluetoothTasks: [WKBluetoothAlertRefreshBackgroundTask] = []

    private func completeOnce(_ task: WKBluetoothAlertRefreshBackgroundTask) {
        guard !Self.completedBluetoothTasks.contains(where: { $0 === task }) else {
            SportLog.event("radio", "Bluetooth task handed over again after completion — not completed twice [bt-task]")
            return
        }
        Self.completedBluetoothTasks.append(task)
        if Self.completedBluetoothTasks.count > 256 { Self.completedBluetoothTasks.removeFirst(64) }
        task.setTaskCompletedWithSnapshot(false)
    }

    /// Called from `handle(_ backgroundTasks:)`, once per delivery.
    func podLoanNoteBackgroundTasks(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        guard FeatureFlags.sportModeEnabled else { return }
        let bluetoothOnly = backgroundTasks.allSatisfy { $0 is WKBluetoothAlertRefreshBackgroundTask }
        if !bluetoothOnly {
            let kinds = backgroundTasks.map { String(describing: type(of: $0)) }.sorted().joined(separator: ",")
            SportLog.event("lifecycle", "background tasks [\(kinds)] on main [bt-task]")
        }
    }

    // One task is held per wake (25 s or until the system expires it); later deliveries in
    // the same wake are completed on arrival and counted.
    func holdBluetoothTask(_ task: WKBluetoothAlertRefreshBackgroundTask) {
        dispatchPrecondition(condition: .onQueue(.main))
        bluetoothDeliveriesThisWake += 1
        if task === heldBluetoothTask {
            return
        }
        if let since = heldBluetoothTaskSince, heldBluetoothTask != nil {
            if Date().timeIntervalSince(since) < Self.bluetoothWakeStaleAfter {
                completeOnce(task)   // same wake: coalesced
                return
            }
            completeHeldBluetoothTask("stale — a new wake arrived")
            bluetoothDeliveriesThisWake = 1
        }
        let delivered = Date()
        heldBluetoothTask = task
        heldBluetoothTaskSince = delivered
        SportLog.event("radio", "WOKEN BY BLUETOOTH — WKBluetoothAlertRefreshBackgroundTask; holding one task 25 s [bt-task]")
        // Logs how long the system actually granted.
        task.expirationHandler = { [weak self] in
            SportLog.event("radio", String(format: "Bluetooth background task EXPIRED by the system after %.1f s — that is the grant [bt-task]", Date().timeIntervalSince(delivered)))
            DispatchQueue.main.async { self?.completeHeldBluetoothTask("expired", only: task) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.completeHeldBluetoothTask("25 s hold over", only: task) }
    }

    /// `only` keeps a late timer from completing a newer hold.
    private func completeHeldBluetoothTask(_ why: String, only: WKBluetoothAlertRefreshBackgroundTask? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let task = heldBluetoothTask, let since = heldBluetoothTaskSince else { return }
        if let only = only, only !== task { return }
        SportLog.event("radio", String(format: "Bluetooth background task completed after %.1f s (%@) · %d deliveries coalesced this wake [bt-task]", Date().timeIntervalSince(since), why, bluetoothDeliveriesThisWake))
        completeOnce(task)
        heldBluetoothTask = nil
        heldBluetoothTaskSince = nil
        bluetoothDeliveriesThisWake = 0
    }
}
