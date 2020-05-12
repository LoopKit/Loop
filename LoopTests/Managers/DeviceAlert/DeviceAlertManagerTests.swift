//
//  DeviceAlertManagerTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import UserNotifications
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

    class MockFileManager: FileManager {
        
        var fileExists = true
        let newer = Date()
        let older = Date.distantPast
        
        var createdDirURL: URL?
        override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
            createdDirURL = url
        }
        override func fileExists(atPath path: String) -> Bool {
            return !path.contains("doesntExist")
        }
        override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey : Any] {
            return path.contains("Sounds") ? path.contains("existsNewer") ? [.creationDate: newer] : [.creationDate: older] :
                 [.creationDate: newer]
        }
        var removedURLs = [URL]()
        override func removeItem(at URL: URL) throws {
            removedURLs.append(URL)
        }
        var copiedSrcURLs = [URL]()
        var copiedDstURLs = [URL]()
        override func copyItem(at srcURL: URL, to dstURL: URL) throws {
            copiedSrcURLs.append(srcURL)
            copiedDstURLs.append(dstURL)
        }
    }

    class MockSoundVendor: DeviceAlertSoundVendor {
        func getSoundBaseURL() -> URL? {
            // Hm.  It's not easy to make a "fake" URL, so we'll use this one:
            return Bundle.main.resourceURL
        }
        
        func getSounds() -> [DeviceAlert.Sound] {
            return [.sound(name: "doesntExist"), .sound(name: "existsNewer"), .sound(name: "existsOlder")]
        }
    }
    
    static let mockManagerIdentifier = "mockManagerIdentifier"
    static let mockTypeIdentifier = "mockTypeIdentifier"
    static let mockIdentifier = DeviceAlert.Identifier(managerIdentifier: mockManagerIdentifier, alertIdentifier: mockTypeIdentifier)
    let mockDeviceAlert = DeviceAlert(identifier: mockIdentifier, foregroundContent: nil, backgroundContent: nil, trigger: .immediate)
    
    var mockFileManager: MockFileManager!
    var mockPresenter: MockPresenter!
    var mockUserNotificationCenter: MockUserNotificationCenter!
    var deviceAlertManager: DeviceAlertManager!
    var isInBackground = true
    
    override class func setUp() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    
    override func setUp() {
        mockFileManager = MockFileManager()
        mockPresenter = MockPresenter()
        mockUserNotificationCenter = MockUserNotificationCenter()
        deviceAlertManager = DeviceAlertManager(rootViewController: UIViewController(),
                                                handlers: [mockPresenter],
                                                userNotificationCenter: mockUserNotificationCenter,
                                                fileManager: mockFileManager)
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
        deviceAlertManager.addAlertResponder(managerIdentifier: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        deviceAlertManager.acknowledgeDeviceAlert(identifier: Self.mockIdentifier)
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == true)
    }
    
    func testAlertResponderNotAcknowledgedIfWrongManagerIdentifier() {
        let responder = MockResponder()
        deviceAlertManager.addAlertResponder(managerIdentifier: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        deviceAlertManager.acknowledgeDeviceAlert(identifier: DeviceAlert.Identifier(managerIdentifier: "foo", alertIdentifier: Self.mockTypeIdentifier))
        XCTAssertTrue(responder.acknowledged.isEmpty)
    }
    
    func testRemovedAlertResponderDoesntAcknowledge() {
        let responder = MockResponder()
        deviceAlertManager.addAlertResponder(managerIdentifier: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        deviceAlertManager.acknowledgeDeviceAlert(identifier: Self.mockIdentifier)
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == true)
        
        responder.acknowledged[DeviceAlertManagerTests.mockTypeIdentifier] = false
        deviceAlertManager.removeAlertResponder(managerIdentifier: DeviceAlertManagerTests.mockManagerIdentifier)
        deviceAlertManager.acknowledgeDeviceAlert(identifier: Self.mockIdentifier)
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == false)
    }
    
    func testAcknowledgedAlertsRemovedFromUserNotificationCenter() {
        deviceAlertManager.acknowledgeDeviceAlert(identifier: Self.mockIdentifier)
    }
    
    func testSoundVendorInitialization() {
        let soundVendor = MockSoundVendor()
        deviceAlertManager.addAlertSoundVendor(managerIdentifier: Self.mockManagerIdentifier, soundVendor: soundVendor)
        XCTAssertEqual("Sounds", mockFileManager.createdDirURL?.lastPathComponent)
        XCTAssertEqual(["\(Self.mockManagerIdentifier)-existsOlder"], mockFileManager.removedURLs.map { $0.lastPathComponent })
        XCTAssertEqual(["doesntExist", "existsOlder"], mockFileManager.copiedSrcURLs.map { $0.lastPathComponent })
        XCTAssertEqual(["\(Self.mockManagerIdentifier)-doesntExist", "\(Self.mockManagerIdentifier)-existsOlder"], mockFileManager.copiedDstURLs.map { $0.lastPathComponent })
    }
    
    // Unfortunately, it is not very easy to test playback of delivered notifications, because we
    // can't construct UNNotifications.  Hopefully, the code footprint in `DeviceAlertManager.playbackDeliveredNotification` is small enough, because it calls common code under test.
    
    func testPlaybackPendingImmediateNotification() {
        let date = Date()
        let content = DeviceAlert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
        let alert = DeviceAlert(identifier: Self.mockIdentifier,
                                foregroundContent: content, backgroundContent: content, trigger: .immediate)

        mockUserNotificationCenter.pendingRequests = [ try! UNNotificationRequest(from: alert, timestamp: date) ]
        deviceAlertManager = DeviceAlertManager(rootViewController: UIViewController(),
                                                handlers: [mockPresenter],
                                                userNotificationCenter: mockUserNotificationCenter,
                                                fileManager: mockFileManager)
        XCTAssertEqual(alert, mockPresenter.issuedAlert)
    }
    
    func testPlaybackPendingExpiredDelayedNotification() {
        let date = Date.distantPast
        let content = DeviceAlert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
        let alert = DeviceAlert(identifier: Self.mockIdentifier,
                                foregroundContent: content, backgroundContent: content, trigger: .delayed(interval: 30.0))

        mockUserNotificationCenter.pendingRequests = [ try! UNNotificationRequest(from: alert, timestamp: date) ]
        deviceAlertManager = DeviceAlertManager(rootViewController: UIViewController(),
                                                handlers: [mockPresenter],
                                                userNotificationCenter: mockUserNotificationCenter,
                                                fileManager: mockFileManager)
        let expected = DeviceAlert(identifier: Self.mockIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate)
        XCTAssertEqual(expected, mockPresenter.issuedAlert)
    }
    
    func testPlaybackPendingDelayedNotification() {
        let date = Date().addingTimeInterval(-15.0) // Pretend the 30-second-delayed alert was issued 15 seconds ago
        let content = DeviceAlert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
        let alert = DeviceAlert(identifier: Self.mockIdentifier,
                                foregroundContent: content, backgroundContent: content, trigger: .delayed(interval: 30.0))

        mockUserNotificationCenter.pendingRequests = [ try! UNNotificationRequest(from: alert, timestamp: date) ]
        deviceAlertManager = DeviceAlertManager(rootViewController: UIViewController(),
                                                handlers: [mockPresenter],
                                                userNotificationCenter: mockUserNotificationCenter,
                                                fileManager: mockFileManager)
        // The trigger for this should be `.delayed` by "something less than 15 seconds",
        // but the exact value depends on the speed of executing this test.
        // As long as it is <= 15 seconds, we call it good.
        XCTAssertNotNil(mockPresenter.issuedAlert)
        switch mockPresenter.issuedAlert?.trigger {
        case .some(.delayed(let interval)):
            XCTAssertLessThanOrEqual(interval, 15.0)
        default:
            XCTFail("Wrong trigger \(String(describing: mockPresenter.issuedAlert?.trigger))")
        }
    }
    
    func testPlaybackPendingRepeatingNotification() {
        let date = Date.distantPast
        let content = DeviceAlert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
        let alert = DeviceAlert(identifier: Self.mockIdentifier,
                                foregroundContent: content, backgroundContent: content, trigger: .repeating(repeatInterval: 60.0))

        mockUserNotificationCenter.pendingRequests = [ try! UNNotificationRequest(from: alert, timestamp: date) ]
        deviceAlertManager = DeviceAlertManager(rootViewController: UIViewController(),
                                                handlers: [mockPresenter],
                                                userNotificationCenter: mockUserNotificationCenter,
                                                fileManager: mockFileManager)
        XCTAssertEqual(alert, mockPresenter.issuedAlert)
    }
}

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
    
    func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) {
        // Sadly, we can't create UNNotifications.
        completionHandler([])
    }
    
    func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) {
        completionHandler(pendingRequests)
    }
}

