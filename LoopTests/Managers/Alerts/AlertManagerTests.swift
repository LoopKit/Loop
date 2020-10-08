//
//  AlertManagerTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import UserNotifications
import XCTest
@testable import Loop

class AlertManagerTests: XCTestCase {
    
    class MockPresenter: AlertPresenter {
        var issuedAlert: Alert?
        func issueAlert(_ alert: Alert) {
            issuedAlert = alert
        }
        var retractedAlertIdentifier: Alert.Identifier?
        func retractAlert(identifier: Alert.Identifier) {
            retractedAlertIdentifier = identifier
        }
    }
    
    class MockResponder: AlertResponder {
        var acknowledged: [Alert.AlertIdentifier: Bool] = [:]
        func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier) {
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
        override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
            return []
        }
    }
    
    class MockSoundVendor: AlertSoundVendor {
        func getSoundBaseURL() -> URL? {
            // Hm.  It's not easy to make a "fake" URL, so we'll use this one:
            return Bundle.main.resourceURL
        }
        
        func getSounds() -> [Alert.Sound] {
            return [.sound(name: "doesntExist"), .sound(name: "existsNewer"), .sound(name: "existsOlder")]
        }
    }
    
    class MockAlertStore: AlertStore {
        
        var issuedAlert: Alert?
        override public func recordIssued(alert: Alert, at date: Date = Date(), completion: ((Result<Void, Error>) -> Void)? = nil) {
            issuedAlert = alert
            completion?(.success)
        }
        
        var acknowledgedAlertIdentifier: Alert.Identifier?
        var acknowledgedAlertDate: Date?
        override public func recordAcknowledgement(of identifier: Alert.Identifier, at date: Date = Date(),
                                                   completion: ((Result<Void, Error>) -> Void)? = nil) {
            acknowledgedAlertIdentifier = identifier
            acknowledgedAlertDate = date
            completion?(.success)
        }
        
        var retractededAlertIdentifier: Alert.Identifier?
        var retractedAlertDate: Date?
        override public func recordRetraction(of identifier: Alert.Identifier, at date: Date = Date(),
                                              completion: ((Result<Void, Error>) -> Void)? = nil) {
            retractededAlertIdentifier = identifier
            retractedAlertDate = date
            completion?(.success)
        }

        var storedAlerts = [StoredAlert]()
        override public func lookupAllUnacknowledged(completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
            completion(.success(storedAlerts))
        }
    }
    
    static let mockManagerIdentifier = "mockManagerIdentifier"
    static let mockTypeIdentifier = "mockTypeIdentifier"
    static let mockIdentifier = Alert.Identifier(managerIdentifier: mockManagerIdentifier, alertIdentifier: mockTypeIdentifier)
    let mockAlert = Alert(identifier: mockIdentifier, foregroundContent: nil, backgroundContent: nil, trigger: .immediate)
    
    var mockFileManager: MockFileManager!
    var mockPresenter: MockPresenter!
    var mockUserNotificationCenter: MockUserNotificationCenter!
    var mockAlertStore: MockAlertStore!
    var alertManager: AlertManager!
    var isInBackground = true
    
    override class func setUp() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    
    override func setUp() {
        mockFileManager = MockFileManager()
        mockPresenter = MockPresenter()
        mockUserNotificationCenter = MockUserNotificationCenter()
        mockAlertStore = MockAlertStore()
        alertManager = AlertManager(rootViewController: UIViewController(),
                                    handlers: [mockPresenter],
                                    userNotificationCenter: mockUserNotificationCenter,
                                    fileManager: mockFileManager,
                                    alertStore: mockAlertStore)
    }

    override func tearDown() {
        mockAlertStore = nil
    }
    
    func testIssueAlertOnHandlerCalled() {
        alertManager.issueAlert(mockAlert)
        XCTAssertEqual(mockAlert.identifier, mockPresenter.issuedAlert?.identifier)
        XCTAssertNil(mockPresenter.retractedAlertIdentifier)
    }
    
    func testRetractAlertOnHandlerCalled() {
        alertManager.retractAlert(identifier: mockAlert.identifier)
        XCTAssertNil(mockPresenter.issuedAlert)
        XCTAssertEqual(mockAlert.identifier, mockPresenter.retractedAlertIdentifier)
    }
    
    func testAlertResponderAcknowledged() {
        let responder = MockResponder()
        alertManager.addAlertResponder(managerIdentifier: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        alertManager.acknowledgeAlert(identifier: Self.mockIdentifier)
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == true)
    }
    
    func testAlertResponderNotAcknowledgedIfWrongManagerIdentifier() {
        let responder = MockResponder()
        alertManager.addAlertResponder(managerIdentifier: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        alertManager.acknowledgeAlert(identifier: Alert.Identifier(managerIdentifier: "foo", alertIdentifier: Self.mockTypeIdentifier))
        XCTAssertTrue(responder.acknowledged.isEmpty)
    }
    
    func testRemovedAlertResponderDoesntAcknowledge() {
        let responder = MockResponder()
        alertManager.addAlertResponder(managerIdentifier: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        alertManager.acknowledgeAlert(identifier: Self.mockIdentifier)
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == true)
        
        responder.acknowledged[AlertManagerTests.mockTypeIdentifier] = false
        alertManager.removeAlertResponder(managerIdentifier: AlertManagerTests.mockManagerIdentifier)
        alertManager.acknowledgeAlert(identifier: Self.mockIdentifier)
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == false)
    }
    
    func testAcknowledgedAlertsRemovedFromUserNotificationCenter() {
        alertManager.acknowledgeAlert(identifier: Self.mockIdentifier)
    }
    
    func testSoundVendorInitialization() {
        let soundVendor = MockSoundVendor()
        alertManager.addAlertSoundVendor(managerIdentifier: Self.mockManagerIdentifier, soundVendor: soundVendor)
        XCTAssertEqual("Sounds", mockFileManager.createdDirURL?.lastPathComponent)
        XCTAssertEqual(["\(Self.mockManagerIdentifier)-existsOlder"], mockFileManager.removedURLs.map { $0.lastPathComponent })
        XCTAssertEqual(["doesntExist", "existsOlder"], mockFileManager.copiedSrcURLs.map { $0.lastPathComponent })
        XCTAssertEqual(["\(Self.mockManagerIdentifier)-doesntExist", "\(Self.mockManagerIdentifier)-existsOlder"], mockFileManager.copiedDstURLs.map { $0.lastPathComponent })
    }
        
    func testPlaybackPendingImmediateAlert() {
        let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
        let alert = Alert(identifier: Self.mockIdentifier,
                          foregroundContent: content, backgroundContent: content, trigger: .immediate)
        mockAlertStore.storedAlerts = [StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)]
        
        alertManager = AlertManager(rootViewController: UIViewController(),
                                    handlers: [mockPresenter],
                                    userNotificationCenter: mockUserNotificationCenter,
                                    fileManager: mockFileManager,
                                    alertStore: mockAlertStore)
        XCTAssertEqual(alert, mockPresenter.issuedAlert)
    }
    
    func testPlaybackPendingExpiredDelayedNotification() {
        let date = Date.distantPast
        let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
        let alert = Alert(identifier: Self.mockIdentifier,
                          foregroundContent: content, backgroundContent: content, trigger: .delayed(interval: 30.0))
        let storedAlert = StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)
        storedAlert.issuedDate = date
        mockAlertStore.storedAlerts = [storedAlert]
        alertManager = AlertManager(rootViewController: UIViewController(),
                                    handlers: [mockPresenter],
                                    userNotificationCenter: mockUserNotificationCenter,
                                    fileManager: mockFileManager,
                                    alertStore: mockAlertStore)
        let expected = Alert(identifier: Self.mockIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate)
        XCTAssertEqual(expected, mockPresenter.issuedAlert)
    }
    
    func testPlaybackPendingDelayedNotification() {
        let date = Date().addingTimeInterval(-15.0) // Pretend the 30-second-delayed alert was issued 15 seconds ago
        let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
        let alert = Alert(identifier: Self.mockIdentifier,
                          foregroundContent: content, backgroundContent: content, trigger: .delayed(interval: 30.0))
        let storedAlert = StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)
        storedAlert.issuedDate = date
        mockAlertStore.storedAlerts = [storedAlert]
        alertManager = AlertManager(rootViewController: UIViewController(),
                                    handlers: [mockPresenter],
                                    userNotificationCenter: mockUserNotificationCenter,
                                    fileManager: mockFileManager,
                                    alertStore: mockAlertStore)

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
        let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
        let alert = Alert(identifier: Self.mockIdentifier,
                          foregroundContent: content, backgroundContent: content, trigger: .repeating(repeatInterval: 60.0))
        let storedAlert = StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)
        storedAlert.issuedDate = date
        mockAlertStore.storedAlerts = [storedAlert]
        alertManager = AlertManager(rootViewController: UIViewController(),
                                    handlers: [mockPresenter],
                                    userNotificationCenter: mockUserNotificationCenter,
                                    fileManager: mockFileManager,
                                    alertStore: mockAlertStore)

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

