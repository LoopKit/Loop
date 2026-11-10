//
//  WatchPluginManagerTests.swift
//  WatchAppTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  The watch app carries the device kits without linking them, and loads them at run time.
//

import XCTest
import LoopKit
@testable import WatchApp

final class WatchPluginManagerTests: XCTestCase {
    func testTheWatchFindsItsDeviceKitsByTheirIdentifiers() {
        let plugins = WatchPluginManager()
        XCTAssertEqual(plugins.pluginBundles.count, 2, "only the kits are plugins, not the other frameworks")
        XCTAssertEqual(plugins.pumpManagerType(withIdentifier: "Omni").map { String(describing: $0) }, "OmniPumpManager")
        XCTAssertEqual(plugins.cgmManagerType(withIdentifier: "G7CGMManager").map { String(describing: $0) }, "G7CGMManager")
    }

    func testAnUnknownIdentifierGivesNoManager() {
        let plugins = WatchPluginManager()
        XCTAssertNil(plugins.pumpManagerType(withIdentifier: "G7CGMManager"), "a CGM's identifier is not a pump's")
        XCTAssertNil(plugins.cgmManagerType(withIdentifier: "Unknown"))
    }
}
