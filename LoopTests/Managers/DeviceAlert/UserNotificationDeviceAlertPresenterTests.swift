//
//  UserNotificationDeviceAlertPresenterTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import XCTest
@testable import Loop

class UserNotificationDeviceAlertPresenterTests: XCTestCase {

    class MockUserNotificationCenter: UserNotificationCenter {
        
        var pendingRequests = [UNNotificationRequest]()
        var deliveredRequests = [UNNotificationRequest]()
                
        func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {
            pendingRequests.append(request)
        }
        
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
            identifiers.forEach { identifier in
                pendingRequests.removeAll { $0.identifier == identifier }
            }
        }

        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
            identifiers.forEach { identifier in
                deliveredRequests.removeAll { $0.identifier == identifier }
            }
        }
        
        func deliverAll() {
            deliveredRequests = pendingRequests
            pendingRequests = []
        }
    }
    
    var userNotificationDeviceAlertPresenter: UserNotificationDeviceAlertPresenter!
    
    let alertIdentifier = DeviceAlert.Identifier(managerIdentifier: "foo", alertIdentifier: "bar")
    let foregroundContent = DeviceAlert.Content(title: "FOREGROUND", body: "foreground", acknowledgeActionButtonLabel: "")
    let backgroundContent = DeviceAlert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "")

    var mockUserNotificationCenter: MockUserNotificationCenter!
    
    override func setUp() {
        mockUserNotificationCenter = MockUserNotificationCenter()
        userNotificationDeviceAlertPresenter =
            UserNotificationDeviceAlertPresenter(userNotificationCenter: mockUserNotificationCenter)
    }

    func testIssueImmediateAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        userNotificationDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        
        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertEqual(UNNotificationSound.default, request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier
            ], request.content.userInfo as? [String: String])
            XCTAssertNil(request.trigger)
        }
    }
    
    func testIssueImmediateCriticalAlert() {
        let backgroundContent = DeviceAlert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "", isCritical: true)
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        userNotificationDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        
        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertEqual(UNNotificationSound.defaultCritical, request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier
            ], request.content.userInfo as? [String: String])
            XCTAssertNil(request.trigger)
        }
    }
    
    func testIssueDelayedAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        userNotificationDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        
        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertEqual(UNNotificationSound.default, request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier
            ], request.content.userInfo as? [String: String])
            XCTAssertEqual(0.1, (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval)
            XCTAssertEqual(false, (request.trigger as? UNTimeIntervalNotificationTrigger)?.repeats)
        }
    }
    
    func testIssueRepeatingAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .repeating(repeatInterval: 100))
        userNotificationDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        
        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertEqual(UNNotificationSound.default, request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier
            ], request.content.userInfo as? [String: String])
            XCTAssertEqual(100, (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval)
            XCTAssertEqual(true, (request.trigger as? UNTimeIntervalNotificationTrigger)?.repeats)
        }
    }
    
    func testRemovePendingAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        userNotificationDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        userNotificationDeviceAlertPresenter.removePendingAlert(identifier: alert.identifier)
        
        waitOnMain()
        XCTAssertTrue(mockUserNotificationCenter.pendingRequests.isEmpty)
    }
    
    func testRemoveDeliveredAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        userNotificationDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        mockUserNotificationCenter.deliverAll()
        
        userNotificationDeviceAlertPresenter.removeDeliveredAlert(identifier: alert.identifier)
        
        waitOnMain()
        XCTAssertTrue(mockUserNotificationCenter.pendingRequests.isEmpty)
        XCTAssertTrue(mockUserNotificationCenter.deliveredRequests.isEmpty)
    }

    
    func testDoesNotShowIfNoBackgroundContent() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: nil, trigger: .immediate)
        userNotificationDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        
        XCTAssertTrue(mockUserNotificationCenter.pendingRequests.isEmpty)
    }
}
