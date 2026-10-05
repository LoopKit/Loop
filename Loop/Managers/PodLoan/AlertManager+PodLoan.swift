//
//  AlertManager+PodLoan.swift
//  Loop
//
//  The Loop-Failure ladder during a loan: cleared at the grant, gated while the phone's loop
//  is idle (`loopNotRunningSuppressionGate`), swept each minute, re-armed at the reclaim.
//  Also the watch's alert records, added to the phone's `AlertStore` when a loan closes.
//

import CoreData
import Foundation
import LoopKit
import UserNotifications

extension AlertManager {

    /// Removes and logs any Loop-Failure rung found pending during a loan, once a minute.
    func sweepLoopNotRunningNotificationsDuringLoan() {
        guard loopNotRunningSuppressionGate?() == true else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let prefix = LoopNotificationCategory.loopNotRunning.rawValue
            let ids = await center.pendingNotificationRequests()
                .filter { $0.identifier.hasPrefix(prefix) }
                .map(\.identifier)
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            PhoneLog.event("deadman", "swept \(ids.count) stale phone Loop-Failure rung(s) mid-loan — these escaped the grant clear and the gate [deadman-sweep]")
        }
    }

    /// The watch has the pod, so the phone's silence is expected; clears the persisted list too.
    func clearLoopNotRunningNotificationsForLoanGrant() {
        UserDefaults.appGroup?.loopNotRunningNotifications = []
        Task { await clearLoopNotRunningNotifications() }
    }
}

// MARK: - Alerts recorded on another device

extension AlertStore {
    /// Adds the records another device's `AlertStore` kept, with their own sync identifiers and
    /// dates: one record per sync identifier, so a copy delivered again adds nothing, and a later
    /// copy fills in the acknowledgement or retraction an earlier one lacked. Returns how many
    /// records were added or changed.
    public func recordAlerts(fromAnotherDevice alerts: [SyncAlertObject]) async throws -> Int {
        let changed: Int = try await managedObjectContext.perform {
            var changed = 0
            for object in alerts {
                let request: NSFetchRequest<StoredAlert> = StoredAlert.fetchRequest()
                request.predicate = NSPredicate(format: "syncIdentifier == %@", object.syncIdentifier as NSUUID)
                request.fetchLimit = 1
                if let stored = try self.managedObjectContext.fetch(request).first {
                    var updated = false
                    if stored.acknowledgedDate == nil, let date = object.acknowledgedDate {
                        stored.acknowledgedDate = date
                        updated = true
                    }
                    if stored.retractedDate == nil, let date = object.retractedDate {
                        stored.retractedDate = date
                        updated = true
                    }
                    changed += updated ? 1 : 0
                } else if let backgroundContent = object.backgroundContent {
                    let alert = Alert(identifier: object.identifier, foregroundContent: object.foregroundContent,
                                      backgroundContent: backgroundContent, trigger: object.trigger,
                                      interruptionLevel: object.interruptionLevel, sound: object.sound, metadata: object.metadata)
                    let stored = StoredAlert(from: alert, context: self.managedObjectContext,
                                             issuedDate: object.issuedDate, syncIdentifier: object.syncIdentifier)
                    stored.acknowledgedDate = object.acknowledgedDate
                    stored.retractedDate = object.retractedDate
                    changed += 1
                }
            }
            if self.managedObjectContext.hasChanges {
                try self.managedObjectContext.save()
            }
            return changed
        }
        alertStoreLog.default("Recorded %d alerts from another device", changed)
        if changed > 0 {
            await delegate?.alertStoreHasUpdatedAlertData(self)
        }
        return changed
    }
}

/// `AlertStore`'s own log is private to its file; same category.
private let alertStoreLog = DiagnosticLog(category: "AlertStore")
