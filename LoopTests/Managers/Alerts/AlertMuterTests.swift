//
//  AlertMuterTests.swift
//  LoopTests
//
//  Created by Nathaniel Hamming on 2022-09-29.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import XCTest
import Combine
import LoopKit
@testable import Loop

final class AlertMuterTests: XCTestCase {

    func testInitialization() {
        var alertMuter = AlertMuter(duration: AlertMuter.allowedDurations[1])
        XCTAssertFalse(alertMuter.configuration.shouldMute)
        XCTAssertEqual(alertMuter.configuration.duration, AlertMuter.allowedDurations[1])
        XCTAssertNil(alertMuter.configuration.startTime)

        let now = Date()
        alertMuter = AlertMuter(startTime: now)
        XCTAssertTrue(alertMuter.configuration.shouldMute)
        XCTAssertEqual(alertMuter.configuration.duration, AlertMuter.allowedDurations[0])
        XCTAssertEqual(alertMuter.configuration.startTime, now)
    }

    func testPublishingUpdateDuration() {
        var cancellables: Set<AnyCancellable> = []
        let alertMuter = AlertMuter()
        var receivedConfiguration: AlertMuter.Configuration?
        let testExpection = expectation(description: #function)
        testExpection.assertForOverFulfill = false
        alertMuter.$configuration
            .sink { configuration in
                receivedConfiguration = configuration
                testExpection.fulfill()
            }
            .store(in: &cancellables)

        alertMuter.configuration.duration = .minutes(30)
        wait(for: [testExpection], timeout: 1)
        XCTAssertEqual(receivedConfiguration, alertMuter.configuration)
    }

    func testPublishingUpdateStartTime() {
        var cancellables: Set<AnyCancellable> = []
        let alertMuter = AlertMuter()
        var receivedConfiguration: AlertMuter.Configuration?
        let testExpection = expectation(description: #function)
        testExpection.assertForOverFulfill = false
        alertMuter.$configuration
            .sink { configuration in
                receivedConfiguration = configuration
                testExpection.fulfill()
            }
            .store(in: &cancellables)

        alertMuter.configuration.startTime = Date()
        wait(for: [testExpection], timeout: 1)
        XCTAssertEqual(receivedConfiguration, alertMuter.configuration)
    }

    func testPublishingMutePeriodEnded() {
        var cancellables: Set<AnyCancellable> = []
        let alertMuter = AlertMuter()
        var receivedConfiguration: AlertMuter.Configuration?
        let testExpection = expectation(description: #function)
        testExpection.assertForOverFulfill = false
        alertMuter.configuration.startTime = Date()
        alertMuter.configuration.duration = .seconds(0.5)

        alertMuter.$configuration
            .sink { configuration in
                receivedConfiguration = configuration
                testExpection.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [testExpection], timeout: 1)
        XCTAssertEqual(receivedConfiguration, alertMuter.configuration)
    }

    func testShouldMuteAlertIssuedFromNow() {
        let alertMuter = AlertMuter()
        XCTAssertFalse(alertMuter.shouldMuteAlert())
        XCTAssertFalse(alertMuter.shouldMuteAlert(scheduledAt: -1))

        let duration = TimeInterval.minutes(45)
        alertMuter.configuration.duration = duration
        alertMuter.configuration.startTime = Date()
        XCTAssertTrue(alertMuter.shouldMuteAlert())
        XCTAssertFalse(alertMuter.shouldMuteAlert(scheduledAt: duration))
    }

    func testShouldMuteAlert() {
        let duration = TimeInterval.seconds(10)
        let now = Date()
        let durationExpired = now.addingTimeInterval(duration)
        let alertMuter = AlertMuter(startTime: now, duration: duration)
        let immediateAlert = LoopKit.Alert(identifier: Alert.Identifier(managerIdentifier: "test", alertIdentifier: "test"), foregroundContent: nil, backgroundContent: Alert.Content(title: "test", body: "test", acknowledgeActionButtonLabel: "OK"), trigger: .immediate)
        XCTAssertTrue(alertMuter.shouldMuteAlert(immediateAlert))
        XCTAssertTrue(alertMuter.shouldMuteAlert(immediateAlert, issuedDate: now, now: now))
        XCTAssertFalse(alertMuter.shouldMuteAlert(immediateAlert, issuedDate: durationExpired, now: now))

        let delayedAlert = LoopKit.Alert(identifier: Alert.Identifier(managerIdentifier: "test", alertIdentifier: "test"), foregroundContent: nil, backgroundContent: Alert.Content(title: "test", body: "test", acknowledgeActionButtonLabel: "OK"), trigger: .delayed(interval: duration/5))
        XCTAssertTrue(alertMuter.shouldMuteAlert(delayedAlert, issuedDate: now, now: now))
        XCTAssertFalse(alertMuter.shouldMuteAlert(delayedAlert, issuedDate: durationExpired, now: now))

        let repeatedAlert = LoopKit.Alert(identifier: Alert.Identifier(managerIdentifier: "test", alertIdentifier: "test"), foregroundContent: nil, backgroundContent: Alert.Content(title: "test", body: "test", acknowledgeActionButtonLabel: "OK"), trigger: .repeating(repeatInterval: duration/2))
        XCTAssertTrue(alertMuter.shouldMuteAlert(repeatedAlert, issuedDate: now, now: now))
        XCTAssertFalse(alertMuter.shouldMuteAlert(repeatedAlert, issuedDate: durationExpired, now: now))
    }

    // MARK: Configuration Tests

    func testRawValue() {
        let now = Date()
        let alertMuter = AlertMuter(startTime: now)
        let rawValue = alertMuter.configuration.rawValue
        XCTAssertEqual(rawValue["duration"] as? TimeInterval, alertMuter.configuration.duration)
        XCTAssertEqual(rawValue["startTime"] as? Date, alertMuter.configuration.startTime)
    }

    func testInitFromRawValue() {
        let duration = TimeInterval.minutes(30)
        let now = Date()
        let rawValue: [String: Any] = ["duration": duration, "startTime": now]

        let configuration = AlertMuter.Configuration(rawValue: rawValue)
        XCTAssertEqual(duration, configuration?.duration)
        XCTAssertEqual(now, configuration?.startTime)
    }

    func testInitFromRawValueNil() {
        let rawValue = ["startTime": Date()]
        XCTAssertNil(AlertMuter.Configuration(rawValue: rawValue))
    }

    func testShouldMute() {
        var configuration = AlertMuter.Configuration()
        XCTAssertFalse(configuration.shouldMute)

        configuration.startTime = Date()
        XCTAssertTrue(configuration.shouldMute)

        let duration = TimeInterval.minutes(45)
        configuration.duration = duration
        configuration.startTime = Date().addingTimeInterval(-(duration+1))
        XCTAssertFalse(configuration.shouldMute)
    }

    func testMutingEndTime() {
        var configuration = AlertMuter.Configuration()
        XCTAssertNil(configuration.mutingEndTime)

        let duration = TimeInterval.minutes(45)
        configuration.duration = duration
        let now = Date()
        configuration.startTime = now
        XCTAssertEqual(configuration.mutingEndTime, now.addingTimeInterval(duration))
    }

    func testShouldMuteAlertScheduledAt() {
        var configuration = AlertMuter.Configuration()
        XCTAssertFalse(configuration.shouldMuteAlert())
        XCTAssertFalse(configuration.shouldMuteAlert(scheduledAt: -1))

        let duration = TimeInterval.minutes(45)
        configuration.duration = duration
        configuration.startTime = Date()
        XCTAssertTrue(configuration.shouldMuteAlert())
        XCTAssertFalse(configuration.shouldMuteAlert(scheduledAt: duration))
    }
}
