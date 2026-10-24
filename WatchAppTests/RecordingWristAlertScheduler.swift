//
//  RecordingWristAlertScheduler.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import UserNotifications
@testable import WatchApp

/// Records alert requests synchronously, modelling the one platform rule the tests need:
/// re-adding an identifier replaces it.
final class RecordingWristAlertScheduler: WristAlertScheduling {

    /// Pending requests, newest write wins per identifier, insertion order preserved.
    private(set) var pending: [UNNotificationRequest] = []

    /// Identifiers passed to the delivered-notification removal, which production calls alongside
    /// the pending removal on every disarm. Kept separate so a test can tell the two apart.
    private(set) var deliveredRemovals: [String] = []

    func add(_ request: UNNotificationRequest) {
        if let existing = pending.firstIndex(where: { $0.identifier == request.identifier }) {
            pending[existing] = request      // replacement, exactly as watchOS does
        } else {
            pending.append(request)
        }
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) {
        deliveredRemovals.append(contentsOf: identifiers)
    }

    // MARK: - Reading

    func interval(of request: UNNotificationRequest) -> TimeInterval? {
        (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
    }

    var identifiers: Set<String> { Set(pending.map(\.identifier)) }
}
