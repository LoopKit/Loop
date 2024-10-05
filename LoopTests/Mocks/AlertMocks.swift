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
    override func scheduleAlert(_ alert: Alert) {
        scheduledAlert = alert
    }
    var unscheduledAlertIdentifier: Alert.Identifier?
    override func unscheduleAlert(identifier: Alert.Identifier) {
        unscheduledAlertIdentifier = identifier
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
    func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
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
    func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)?) { completion?() }
    func dismissTopMost(animated: Bool, completion: (() -> Void)?) { completion?() }
    func dismissAlert(_ alertToDismiss: UIAlertController, animated: Bool, completion: (() -> Void)?) { completion?() }
}

class MockAlertManagerResponder: AlertManagerResponder {
    func acknowledgeAlert(identifier: LoopKit.Alert.Identifier) { }
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

    var retractedAlert: Alert?
    var retractedAlertDate: Date?
    override public func recordRetractedAlert(_ alert: Alert, at date: Date, completion: ((Result<Void, Error>) -> Void)? = nil) {
        retractedAlert = alert
        retractedAlertDate = date
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
    override public func recordRetraction(of identifier: Alert.Identifier, at date: Date = Date(),
                                          completion: ((Result<Void, Error>) -> Void)? = nil) {
        retractededAlertIdentifier = identifier
        retractedAlertDate = date
        completion?(.success)
    }

    var storedAlerts = [StoredAlert]()
    override public func lookupAllUnacknowledgedUnretracted(managerIdentifier: String? = nil, filteredByTriggers triggersStoredType: [AlertTriggerStoredType]? = nil, completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        completion(.success(storedAlerts))
    }

    override public func lookupAllUnretracted(managerIdentifier: String?, completion: @escaping (Result<[StoredAlert], Error>) -> Void) {
        completion(.success(storedAlerts))
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
