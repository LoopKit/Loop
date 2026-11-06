//
//  SmartwatchPermissions.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// What the user allowed a watch plugin to do, and the history the rate limits
/// need. The bolus checks themselves are LoopKit's `SmartwatchBolusPolicy`.
extension Notification.Name {
    /// A Watch Permissions toggle changed, so the snapshot's `permittedActions` did.
    static let WatchPermissionsChanged = Notification.Name("com.loopkit.Loop.WatchPermissionsChanged")
}

extension UserDefaults {
    /// Whether boluses requested from a watch plugin may be delivered. Off by default.
    static let allowWatchBolusKey = "com.loopkit.Loop.allowWatchBolus"
    private static let watchBolusDeliveriesKey = "com.loopkit.Loop.watchBolusDeliveries"

    var allowWatchBolus: Bool {
        get { bool(forKey: Self.allowWatchBolusKey) }
        set { set(newValue, forKey: Self.allowWatchBolusKey) }
    }

    /// Whether a watch plugin with `.remoteCarbs` may add carb entries. Off by default.
    static let allowWatchCarbsKey = "com.loopkit.Loop.allowWatchCarbs"
    private static let lastWatchCarbEntryKey = "com.loopkit.Loop.lastWatchCarbEntry"

    var allowWatchCarbs: Bool {
        get { bool(forKey: Self.allowWatchCarbsKey) }
        set { set(newValue, forKey: Self.allowWatchCarbsKey) }
    }

    /// When the last carb entry from the watch was added, for its rate limit.
    var lastWatchCarbEntry: Date? {
        get { object(forKey: Self.lastWatchCarbEntryKey) as? Date }
        set { set(newValue, forKey: Self.lastWatchCarbEntryKey) }
    }

    /// Whether a watch plugin with `.remoteMute` may mute Loop's alerts. Off by default.
    static let allowWatchMuteKey = "com.loopkit.Loop.allowWatchMute"

    var allowWatchMute: Bool {
        get { bool(forKey: Self.allowWatchMuteKey) }
        set { set(newValue, forKey: Self.allowWatchMuteKey) }
    }

    /// Whether a watch plugin with `.remoteOverride` may start and end override presets. Off by default.
    static let allowWatchOverridesKey = "com.loopkit.Loop.allowWatchOverrides"

    var allowWatchOverrides: Bool {
        get { bool(forKey: Self.allowWatchOverridesKey) }
        set { set(newValue, forKey: Self.allowWatchOverridesKey) }
    }

    /// The remote actions among `capabilities` whose toggle is on, for the
    /// snapshot's `permittedActions`.
    func permittedWatchActions(within capabilities: SmartwatchCapabilities) -> SmartwatchCapabilities {
        var permitted: SmartwatchCapabilities = []
        if allowWatchBolus { permitted.insert(.remoteBolus) }
        if allowWatchCarbs { permitted.insert(.remoteCarbs) }
        if allowWatchMute { permitted.insert(.remoteMute) }
        if allowWatchOverrides { permitted.insert(.remoteOverride) }
        return permitted.intersection(capabilities)
    }

    /// Turns off every Watch Permissions toggle. Called when the watch plugin is
    /// removed or replaced, so a new plugin never inherits what the user granted
    /// another one. The rate-limit history is kept.
    func resetWatchPermissions() {
        allowWatchBolus = false
        allowWatchCarbs = false
        allowWatchMute = false
        allowWatchOverrides = false
    }

    /// Watch boluses delivered in the last 24 hours, kept across launches for the rate limits.
    var watchBolusDeliveries: [SmartwatchBolusPolicy.Delivery] {
        get {
            data(forKey: Self.watchBolusDeliveriesKey).flatMap { try? JSONDecoder().decode([SmartwatchBolusPolicy.Delivery].self, from: $0) } ?? []
        }
        set {
            let dayStart = Date().addingTimeInterval(-24 * 60 * 60)
            set(try? JSONEncoder().encode(newValue.filter { $0.date > dayStart }), forKey: Self.watchBolusDeliveriesKey)
        }
    }
}
