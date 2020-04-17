//
//  DeviceAlertManagerTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import XCTest
@testable import Loop

class DeviceAlertManagerTests: XCTestCase {
    
    class MockPresenter: DeviceAlertPresenter {
        var issuedAlert: DeviceAlert?
        func issueAlert(_ alert: DeviceAlert) {
            issuedAlert = alert
        }
        var removedPendingAlertIdentifier: DeviceAlert.Identifier?
        func removePendingAlert(identifier: DeviceAlert.Identifier) {
            removedPendingAlertIdentifier = identifier
        }
        var removeDeliveredAlertIdentifier: DeviceAlert.Identifier?
        func removeDeliveredAlert(identifier: DeviceAlert.Identifier) {
            removeDeliveredAlertIdentifier = identifier
        }
    }
    
    class MockResponder: DeviceAlertResponder {
        var acknowledged: [DeviceAlert.AlertIdentifier: Bool] = [:]
        func acknowledgeAlert(alertIdentifier: DeviceAlert.AlertIdentifier) {
            acknowledged[alertIdentifier] = true
        }
    }
    
    static let mockManagerIdentifier = "mockManagerIdentifier"
    static let mockTypeIdentifier = "mockTypeIdentifier"
    let mockDeviceAlert = DeviceAlert(identifier: DeviceAlert.Identifier(managerIdentifier: mockManagerIdentifier, alertIdentifier: mockTypeIdentifier), foregroundContent: nil, backgroundContent: nil, trigger: .immediate)
    
    var mockPresenter: MockPresenter!
    var deviceAlertManager: DeviceAlertManager!
    var isInBackground = true
    
    override func setUp() {
        mockPresenter = MockPresenter()
        deviceAlertManager = DeviceAlertManager(rootViewController: UIViewController(),
                                                isAppInBackgroundFunc: { return self.isInBackground },
                                                handlers: [mockPresenter])
    }
    
    func testIssueAlertOnHandlerCalled() {
        deviceAlertManager.issueAlert(mockDeviceAlert)
        XCTAssertEqual(mockDeviceAlert.identifier, mockPresenter.issuedAlert?.identifier)
        XCTAssertNil(mockPresenter.removeDeliveredAlertIdentifier)
        XCTAssertNil(mockPresenter.removedPendingAlertIdentifier)
    }
    
    func testRemovePendingAlertOnHandlerCalled() {
        deviceAlertManager.removePendingAlert(identifier: mockDeviceAlert.identifier)
        XCTAssertNil(mockPresenter.issuedAlert)
        XCTAssertEqual(mockDeviceAlert.identifier, mockPresenter.removedPendingAlertIdentifier)
        XCTAssertNil(mockPresenter.removeDeliveredAlertIdentifier)
    }
    
    func testRemoveDeliveredAlertOnHandlerCalled() {
        deviceAlertManager.removeDeliveredAlert(identifier: mockDeviceAlert.identifier)
        XCTAssertNil(mockPresenter.issuedAlert)
        XCTAssertNil(mockPresenter.removedPendingAlertIdentifier)
        XCTAssertEqual(mockDeviceAlert.identifier, mockPresenter.removeDeliveredAlertIdentifier)
    }

    func testAlertResponderAcknowledged() {
        let responder = MockResponder()
        deviceAlertManager.addAlertResponder(key: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        deviceAlertManager.acknowledgeDeviceAlert(identifier: DeviceAlert.Identifier(managerIdentifier: Self.mockManagerIdentifier, alertIdentifier: Self.mockTypeIdentifier))
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == true)
    }
    
    func testAlertResponderNotAcknowledgedIfWrongManagerIdentifier() {
        let responder = MockResponder()
        deviceAlertManager.addAlertResponder(key: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        deviceAlertManager.acknowledgeDeviceAlert(identifier: DeviceAlert.Identifier(managerIdentifier: "foo", alertIdentifier: Self.mockTypeIdentifier))
        XCTAssertTrue(responder.acknowledged.isEmpty)
    }
    
    func testRemovedAlertResponderDoesntAcknowledge() {
        let responder = MockResponder()
        deviceAlertManager.addAlertResponder(key: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        deviceAlertManager.acknowledgeDeviceAlert(identifier: DeviceAlert.Identifier(managerIdentifier: Self.mockManagerIdentifier, alertIdentifier: Self.mockTypeIdentifier))
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == true)
        
        responder.acknowledged[DeviceAlertManagerTests.mockTypeIdentifier] = false
        deviceAlertManager.removeAlertResponder(key: DeviceAlertManagerTests.mockManagerIdentifier)
        deviceAlertManager.acknowledgeDeviceAlert(identifier: DeviceAlert.Identifier(managerIdentifier: Self.mockManagerIdentifier, alertIdentifier: Self.mockTypeIdentifier))
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == false)
    }
}
