//
//  SmartwatchPermissionsTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import Loop

final class SmartwatchPermissionsTests: XCTestCase {
    func testResettingWatchPermissionsTurnsEveryToggleOffAndKeepsTheRateLimitHistory() throws {
        let suiteName = "SmartwatchPermissionsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.allowWatchBolus = true
        defaults.allowWatchCarbs = true
        defaults.allowWatchMute = true
        defaults.allowWatchOverrides = true
        let lastCarbEntry = Date()
        defaults.lastWatchCarbEntry = lastCarbEntry

        defaults.resetWatchPermissions()

        XCTAssertFalse(defaults.allowWatchBolus)
        XCTAssertFalse(defaults.allowWatchCarbs)
        XCTAssertFalse(defaults.allowWatchMute)
        XCTAssertFalse(defaults.allowWatchOverrides)
        XCTAssertEqual(defaults.lastWatchCarbEntry, lastCarbEntry)
    }
}
