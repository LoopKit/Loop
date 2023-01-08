//
//  UserNotificationAlertSchedulerTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import XCTest
@testable import Loop

class UserNotificationAlertSchedulerTests: XCTestCase {
    
    var userNotificationAlertScheduler: UserNotificationAlertScheduler!
    
    let alertIdentifier = Alert.Identifier(managerIdentifier: "foo", alertIdentifier: "bar")
    let foregroundContent = Alert.Content(title: "FOREGROUND", body: "foreground", acknowledgeActionButtonLabel: "")
    let backgroundContent = Alert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "")

    var mockUserNotificationCenter: MockUserNotificationCenter!
    
    override func setUp() {
        mockUserNotificationCenter = MockUserNotificationCenter()
        userNotificationAlertScheduler =
            UserNotificationAlertScheduler(userNotificationCenter: mockUserNotificationCenter)
    }

    func testIssueImmediateAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        userNotificationAlertScheduler.scheduleAlert(alert, timestamp: Date.distantPast)

        waitOnMain()
        
        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertEqual(UNNotificationSound.default, request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier,
            ], request.content.userInfo as? [String: String])
            XCTAssertNil(request.trigger)
        }
    }
    
    func testIssueImmediateCriticalAlert() {
        let backgroundContent = Alert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "")
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate, interruptionLevel: .critical)
        userNotificationAlertScheduler.scheduleAlert(alert, timestamp: Date.distantPast)

        waitOnMain()
        
        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertEqual(UNNotificationSound.defaultCritical, request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier,
            ], request.content.userInfo as? [String: String])
            XCTAssertNil(request.trigger)
        }
    }
    
    func testIssueDelayedAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        userNotificationAlertScheduler.scheduleAlert(alert, timestamp: Date.distantPast)

        waitOnMain()
        
        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertEqual(UNNotificationSound.default, request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier,
            ], request.content.userInfo as? [String: String])
            XCTAssertEqual(0.1, (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval)
            XCTAssertEqual(false, (request.trigger as? UNTimeIntervalNotificationTrigger)?.repeats)
        }
    }
    
    func testIssueRepeatingAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .repeating(repeatInterval: 100))
        userNotificationAlertScheduler.scheduleAlert(alert, timestamp: Date.distantPast)

        waitOnMain()
        
        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertEqual(UNNotificationSound.default, request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier,
            ], request.content.userInfo as? [String: String])
            XCTAssertEqual(100, (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval)
            XCTAssertEqual(true, (request.trigger as? UNTimeIntervalNotificationTrigger)?.repeats)
        }
    }
    
    func testRetractAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        userNotificationAlertScheduler.scheduleAlert(alert)

        waitOnMain()
        mockUserNotificationCenter.deliverAll()
        
        userNotificationAlertScheduler.unscheduleAlert(identifier: alert.identifier)
        
        waitOnMain()
        XCTAssertTrue(mockUserNotificationCenter.pendingRequests.isEmpty)
        XCTAssertTrue(mockUserNotificationCenter.deliveredRequests.isEmpty)
    }

    func testIssueMutedAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        userNotificationAlertScheduler.scheduleAlert(alert, timestamp: Date.distantPast, muted: true)

        waitOnMain()

        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertNil(request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier,
            ], request.content.userInfo as? [String: String])
            XCTAssertNil(request.trigger)
        }
    }

    func testIssueMutedCriticalAlert() {
        let backgroundContent = Alert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "")
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate, interruptionLevel: .critical)
        userNotificationAlertScheduler.scheduleAlert(alert, timestamp: Date.distantPast, muted: true)

        waitOnMain()

        XCTAssertEqual(1, mockUserNotificationCenter.pendingRequests.count)
        if let request = mockUserNotificationCenter.pendingRequests.first {
            XCTAssertEqual(self.backgroundContent.title, request.content.title)
            XCTAssertEqual(self.backgroundContent.body, request.content.body)
            XCTAssertEqual(UNNotificationSound.defaultCriticalSound(withAudioVolume: 0), request.content.sound)
            XCTAssertEqual(alertIdentifier.value, request.content.threadIdentifier)
            XCTAssertEqual([
                LoopNotificationUserInfoKey.managerIDForAlert.rawValue: alertIdentifier.managerIdentifier,
                LoopNotificationUserInfoKey.alertTypeID.rawValue: alertIdentifier.alertIdentifier,
            ], request.content.userInfo as? [String: String])
            XCTAssertNil(request.trigger)
        }
    }
}
