//
//  RecordingWristAlertScheduler.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import UserNotifications
@testable import WatchApp

/// Records what the dead-man alerts ask for, instead of asking the notification daemon.
///
/// It models the ONE platform behaviour these tests depend on: adding a request whose identifier
/// already exists REPLACES it rather than stacking. That is the mechanism the whole suite is about
/// — every completed loop cycle re-adds under the same identifier, so a healthy loop perpetually
/// defers its own alarm — and modelling it here is what lets the identifier assertions mean
/// something without a live daemon.
///
/// Deliberately synchronous. The real API is async because a separate process owns the store; that
/// asynchrony is what forced the old suite's `pending()` / `settledPending()` polling helpers, and
/// it bought nothing but flakiness once the daemon was answering from an unauthorized app with an
/// empty array.
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
