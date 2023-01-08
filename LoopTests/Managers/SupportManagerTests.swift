//
//  SupportManagerTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 9/10/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
import LoopKitUI
import SwiftUI
@testable import Loop

class SupportManagerTests: XCTestCase {
    enum MockError: Error { case nothing }

    class Mixin {
        func supportMenuItem(supportInfoProvider: SupportInfoProvider, urlHandler: @escaping (URL) -> Void) -> AnyView? {
            nil
        }
        func softwareUpdateView(bundleIdentifier: String, currentVersion: String, guidanceColors: GuidanceColors, openAppStore: (() -> Void)?) -> AnyView? {
            nil
        }
        var mockResult: Result<VersionUpdate?, Error> = .success(.default)
        func checkVersion(bundleIdentifier: String, currentVersion: String, completion: @escaping (Result<VersionUpdate?, Error>) -> Void) {
            completion(mockResult)
        }
        weak var delegate: SupportUIDelegate?
    }
    class MockSupport: Mixin, SupportUI {
        func configurationMenuItems() -> [AnyView] { return [] }
        static var supportIdentifier: String { "SupportManagerTestsMockSupport" }
        override init() { super.init() }
        required init?(rawState: RawStateValue) { super.init() }
        var rawState: RawStateValue = [:]
    }
    class AnotherMockSupport: Mixin, SupportUI {
        func configurationMenuItems() -> [AnyView] { return [] }
        static var supportIdentifier: String { "SupportManagerTestsAnotherMockSupport" }
        override init() { super.init() }
        required init?(rawState: RawStateValue) { super.init() }
        var rawState: RawStateValue = [:]
    }
    
    class MockAlertIssuer: AlertIssuer {
        func issueAlert(_ alert: LoopKit.Alert) {
        }
        
        func retractAlert(identifier: LoopKit.Alert.Identifier) {
        }
    }
    
    var supportManager: SupportManager!
    var mockSupport: SupportManagerTests.MockSupport!
    var mockAlertIssuer: MockAlertIssuer!

    override func setUp() {
        mockAlertIssuer = MockAlertIssuer()
        supportManager = SupportManager(staticSupportTypes: [], alertIssuer: mockAlertIssuer)
        mockSupport = SupportManagerTests.MockSupport()
        supportManager.addSupport(mockSupport)
    }
    
    func getVersion(fn: String = #function) -> VersionUpdate? {
        let e = expectation(description: fn)
        var result: VersionUpdate?
        supportManager.checkVersion {
            result = $0
            e.fulfill()
        }
        wait(for: [e], timeout: 1.0)
        return result
    }
    
    func testVersionCheckOneService() throws {
        XCTAssertEqual(VersionUpdate.none, getVersion())
        mockSupport.mockResult = .success(.required)
        XCTAssertEqual(.required, getVersion())
    }
    
    func testVersionCheckOneServiceError() throws {
        // Error doesn't really do anything but log
        mockSupport.mockResult = .failure(MockError.nothing)
        XCTAssertEqual(VersionUpdate.none, getVersion())
    }
    
    func testVersionCheckMultipleServices() throws {
        let anotherSupport = AnotherMockSupport()
        supportManager.addSupport(anotherSupport)
        XCTAssertEqual(VersionUpdate.none, getVersion())
        anotherSupport.mockResult = .success(.required)
        XCTAssertEqual(.required, getVersion())
        mockSupport.mockResult = .success(.recommended)
        XCTAssertEqual(.required, getVersion())
    }
    
}
