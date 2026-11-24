//
//  AlertMocks.swift
//  LoopTests
//
//  Created by Pete Schwamb on 10/31/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit
@testable import Loop
import XCTest

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

class MockModalAlertScheduler: InAppModalAlertScheduler {
    var scheduledAlert: Alert?
    
    var alertScheduledExpectation: XCTestExpectation?
    var alertUnscheduledExpectation: XCTestExpectation?

    override func scheduleAlert(_ alert: Alert) {
        scheduledAlert = alert
        alertScheduledExpectation?.fulfill()
    }
    var unscheduledAlertIdentifier: Alert.Identifier?

    override func unscheduleAlert(identifier: Alert.Identifier) async {
        unscheduledAlertIdentifier = identifier
        alertUnscheduledExpectation?.fulfill()
    }
}

class MockUserNotificationAlertScheduler: UserNotificationAlertScheduler {
    var scheduledAlert: Alert?
    var muted: Bool?

    override func scheduleAlert(_ alert: Alert, muted: Bool) {
        scheduledAlert = alert
        self.muted = muted
    }
    var unscheduledAlertIdentifier: Alert.Identifier?
    override func unscheduleAlert(identifier: Alert.Identifier) {
        unscheduledAlertIdentifier = identifier
    }
}

class MockResponder: AlertResponder {

    var acknowledged: [Alert.AlertIdentifier: Bool] = [:]
    func acknowledgeAlert(alertIdentifier: LoopKit.Alert.AlertIdentifier) async throws {
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

class MockPresenter: AlertPresenter {
    var presentedViewController: UIViewController?

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool) async {
        presentedViewController = viewControllerToPresent
    }
    func dismissTopMost(animated: Bool) async {
        presentedViewController = nil
    }
    func dismissAlert(_ alertToDismiss: UIAlertController, animated: Bool) async {
        presentedViewController = nil
    }
}

class MockAlertManagerResponder: AlertManagerResponder {
    func userDidSelectAction(alertIdentifier: LoopKit.Alert.Identifier, actionIdentifier: String) async throws { }
    func acknowledgeAlert(identifier: LoopKit.Alert.Identifier) async { }
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
    override public func recordIssued(alert: Alert, at date: Date = Date()) async {
        issuedAlert = alert
    }

    var retractedAlert: Alert?
    var retractedAlertDate: Date?
    override public func recordRetractedAlert(_ alert: Alert, at date: Date) async throws {
        retractedAlert = alert
        retractedAlertDate = date
    }

    var acknowledgedAlertIdentifier: Alert.Identifier?
    var acknowledgedAlertDate: Date?
    override public func recordAcknowledgement(of identifier: Alert.Identifier, at date: Date = Date()) async throws {
        acknowledgedAlertIdentifier = identifier
        acknowledgedAlertDate = date
    }

    var retractededAlertIdentifier: Alert.Identifier?
    override public func recordRetraction(of identifier: Alert.Identifier, at date: Date = Date()) async throws {
        retractededAlertIdentifier = identifier
        retractedAlertDate = date
    }

    var storedAlerts = [StoredAlert]()
    override public func lookupAllUnacknowledgedUnretracted(managerIdentifier: String? = nil, filteredByTriggers triggersStoredType: [AlertTriggerStoredType]? = nil) async throws -> [StoredAlert]
    {
        return storedAlerts
    }

    override public func lookupAllUnretracted(managerIdentifier: String?) async -> [StoredAlert] {
        return storedAlerts
    }
}

class MockUserNotificationCenter: UserNotificationCenter {

    var pendingRequests = [UNNotificationRequest]()
    var deliveredRequests = [UNNotificationRequest]()
    var addError: Error?

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {
        if addError == nil {
            pendingRequests.removeAll { $0.identifier == request.identifier }
            pendingRequests.append(request)
        }
        completionHandler?(addError)
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
