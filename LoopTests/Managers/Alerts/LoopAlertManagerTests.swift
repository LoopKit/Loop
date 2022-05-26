//
//  LoopAlertManagerTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 5/20/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

import XCTest
import LoopKit
@testable import Loop

class LoopAlertManagerTests: XCTestCase {

    class MockBluetoothProvider: BluetoothProvider {
        var bluetoothAuthorization: BluetoothAuthorization = .authorized

        var bluetoothState: BluetoothState = .poweredOn

        func authorizeBluetooth(_ completion: @escaping (BluetoothAuthorization) -> Void) {
            completion(bluetoothAuthorization)
        }

        func addBluetoothObserver(_ observer: BluetoothObserver, queue: DispatchQueue) {
        }

        func removeBluetoothObserver(_ observer: BluetoothObserver) {
        }
    }

    var mockFileManager = AlertManagerTests.MockFileManager()
    var mockPresenter = AlertManagerTests.MockPresenter()
    var mockIssuer = AlertManagerTests.MockIssuer()
    var mockUserNotificationCenter = MockUserNotificationCenter()
    var mockAlertStore = AlertManagerTests.MockAlertStore()
    var mockBluetoothProvider = MockBluetoothProvider()
    var alertManager: AlertManager!
    var loopAlertsManager: LoopAlertsManager!

    override class func setUp() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    override func setUp() {
        alertManager = AlertManager(alertPresenter: mockPresenter,
                                    handlers: [mockIssuer],
                                    userNotificationCenter: mockUserNotificationCenter,
                                    fileManager: mockFileManager,
                                    alertStore: mockAlertStore)

        self.loopAlertsManager = LoopAlertsManager(alertManager: alertManager,
                                                   bluetoothProvider: mockBluetoothProvider)



    }

    override func tearDown() {
        UserDefaults.appGroup?.loopNotRunningNotifications = []
        mockAlertStore.issuedAlert = nil
    }

    func testLoopDidCompleteRecordsNotifications() {
        loopAlertsManager.loopDidComplete()
        XCTAssertEqual(4, UserDefaults.appGroup?.loopNotRunningNotifications.count)
    }

    func testLoopFailureFor10MinutesDoesNotRecordAlert() {
        loopAlertsManager.loopDidComplete()
        XCTAssertNil(mockAlertStore.issuedAlert)
        loopAlertsManager.getCurrentDate = { return Date().addingTimeInterval(.minutes(10))}
        loopAlertsManager.inferDeliveredLoopNotRunningNotifications()
        XCTAssertNil(mockAlertStore.issuedAlert)
    }

    func testLoopFailureFor30MinutesRecordsTimeSensitiveAlert() {
        loopAlertsManager.loopDidComplete()
        XCTAssertNil(mockAlertStore.issuedAlert)
        loopAlertsManager.getCurrentDate = { return Date().addingTimeInterval(.minutes(30))}
        loopAlertsManager.inferDeliveredLoopNotRunningNotifications()
        XCTAssertEqual(3, UserDefaults.appGroup?.loopNotRunningNotifications.count)
        XCTAssertNotNil(mockAlertStore.issuedAlert)
        XCTAssertEqual(.timeSensitive, mockAlertStore.issuedAlert!.interruptionLevel)
    }

    func testLoopFailureFor65MinutesRecordsCriticalAlert() {
        loopAlertsManager.loopDidComplete()
        loopAlertsManager.getCurrentDate = { return Date().addingTimeInterval(.minutes(65))}
        loopAlertsManager.inferDeliveredLoopNotRunningNotifications()
        XCTAssertEqual(1, UserDefaults.appGroup?.loopNotRunningNotifications.count)
        XCTAssertNotNil(mockAlertStore.issuedAlert)
        XCTAssertEqual(.critical, mockAlertStore.issuedAlert!.interruptionLevel)
    }
}
