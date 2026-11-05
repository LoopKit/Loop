//
//  AlertManager+PodLoan.swift
//  Loop
//
//  The Loop-Failure warnings while this phone has released the pump: removed at the release,
//  not scheduled while released (`loopNotRunningSuppressionGate`), scheduled again at the take-back.
//  Also the watch's alert records, added to the phone's `AlertStore` when a loan closes.
//

import CoreData
import Foundation
import LoopKit
import UserNotifications

extension AlertManager {

    /// The pump was released: this phone's silence is expected. Removes the warnings still to
    /// fire as well as any delivered, and clears the saved list so none is recorded as issued.
    func removeLoopNotRunningNotificationsForReleasedPump() {
        UserDefaults.appGroup?.loopNotRunningNotifications = []
        Task {
            let center = UNUserNotificationCenter.current()
            let category = LoopNotificationCategory.loopNotRunning.rawValue
            let pending = await center.pendingNotificationRequests()
                .filter { $0.content.categoryIdentifier == category }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: pending)
            let delivered = await center.deliveredNotifications()
                .filter { $0.request.content.categoryIdentifier == category }.map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: delivered)
            PhoneLog.event("deadman", "pump released: removed \(pending.count) pending and \(delivered.count) delivered Loop Failure warnings")
        }
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
        if changed > 0 {
            await delegate?.alertStoreHasUpdatedAlertData(self)
        }
        return changed
    }
}
