//
//  VersionCheckServicesManagerTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 9/10/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
import LoopKit
@testable import Loop

class VersionCheckServicesManagerTests: XCTestCase {

    class MockVersionCheckService: VersionCheckService {
        var mockResult: Result<VersionUpdate?, Error> = .success(.noneNeeded)
        func checkVersion(bundleIdentifier: String, currentVersion: String, completion: @escaping (Result<VersionUpdate?, Error>) -> Void) {
            completion(mockResult)
        }
        convenience init() { self.init(rawState: [:])! }
        static var localizedTitle = "MockVersionCheckService"
        static var serviceIdentifier = "MockVersionCheckService"
        var serviceDelegate: ServiceDelegate?
        required init?(rawState: RawStateValue) { }
        var rawState: RawStateValue = [:]
        var isOnboarded: Bool = false
    }
    
    var versionCheckServicesManager: VersionCheckServicesManager!
    var mockVersionCheckService: MockVersionCheckService!
    
    override func setUp() {
        versionCheckServicesManager = VersionCheckServicesManager()
        mockVersionCheckService = MockVersionCheckService()
        versionCheckServicesManager.addService(mockVersionCheckService)
    }
    
    func testVersionCheckOneService() throws {
        XCTAssertEqual(.noneNeeded, versionCheckServicesManager.checkVersion(currentVersion: ""))
        mockVersionCheckService.mockResult = .success(.criticalNeeded)
        XCTAssertEqual(.criticalNeeded, versionCheckServicesManager.checkVersion(currentVersion: ""))
    }
    
    enum MockError: Error { case nothing }
    func testVersionCheckOneServiceError() throws {
        // Error doesn't really do anything but log
        mockVersionCheckService.mockResult = .failure(MockError.nothing)
        XCTAssertEqual(.noneNeeded, versionCheckServicesManager.checkVersion(currentVersion: ""))
    }

    func testVersionCheckMultipleServices() throws {
        let anotherService = MockVersionCheckService()
        versionCheckServicesManager.addService(anotherService)
        XCTAssertEqual(.noneNeeded, versionCheckServicesManager.checkVersion(currentVersion: ""))
        anotherService.mockResult = .success(.criticalNeeded)
        XCTAssertEqual(.criticalNeeded, versionCheckServicesManager.checkVersion(currentVersion: ""))
        mockVersionCheckService.mockResult = .success(.supportedNeeded)
        XCTAssertEqual(.criticalNeeded, versionCheckServicesManager.checkVersion(currentVersion: ""))
    }
}
