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
    
    static let mockManagerIdentifier = "mockManagerIdentifier"
    static let mockTypeIdentifier = "mockTypeIdentifier"
    static let mockIdentifier = Alert.Identifier(managerIdentifier: mockManagerIdentifier, alertIdentifier: mockTypeIdentifier)
    static let backgroundContent = Alert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "")
    let mockAlert = Alert(identifier: mockIdentifier, foregroundContent: nil, backgroundContent: backgroundContent, trigger: .immediate)
    
    var mockFileManager: MockFileManager!
    var mockPresenter: MockPresenter!
    var mockModalScheduler: MockModalAlertScheduler!
    var mockUserNotificationScheduler: MockUserNotificationAlertScheduler!
    var mockAlertStore: MockAlertStore!
    var alertManager: AlertManager!
    var isInBackground = true
    
    override func setUp() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        mockFileManager = MockFileManager()
        mockPresenter = MockPresenter()
        mockModalScheduler = MockModalAlertScheduler(alertPresenter: mockPresenter, alertManagerResponder: MockAlertManagerResponder())
        mockUserNotificationScheduler = MockUserNotificationAlertScheduler(userNotificationCenter: MockUserNotificationCenter())
        mockAlertStore = MockAlertStore()
        alertManager = AlertManager(alertPresenter: mockPresenter,
                                    modalAlertScheduler: mockModalScheduler,
                                    userNotificationAlertScheduler: mockUserNotificationScheduler,
                                    fileManager: mockFileManager,
                                    alertStore: mockAlertStore,
                                    bluetoothProvider: MockBluetoothProvider(),
                                    analyticsServicesManager: AnalyticsServicesManager(),
                                    preventIssuanceBeforePlayback: false)
    }

    override func tearDown() {
        mockAlertStore = nil
    }
    
    func testIssueAlertOnHandlerCalled() {
        alertManager.issueAlert(mockAlert)
        XCTAssertEqual(mockAlert.identifier, mockModalScheduler.scheduledAlert?.identifier)
        XCTAssertEqual(mockAlert.identifier, mockUserNotificationScheduler.scheduledAlert?.identifier)
        XCTAssertNil(mockModalScheduler.unscheduledAlertIdentifier)
        XCTAssertNil(mockUserNotificationScheduler.unscheduledAlertIdentifier)
    }
    
    func testRetractAlertOnHandlerCalled() {
        alertManager.retractAlert(identifier: mockAlert.identifier)
        XCTAssertNil(mockModalScheduler.scheduledAlert)
        XCTAssertNil(mockUserNotificationScheduler.scheduledAlert)
        XCTAssertEqual(mockAlert.identifier, mockModalScheduler.unscheduledAlertIdentifier)
        XCTAssertEqual(mockAlert.identifier, mockUserNotificationScheduler.unscheduledAlertIdentifier)
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
        mockAlertStore.managedObjectContext.performAndWait {
            let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
            let alert = Alert(identifier: Self.mockIdentifier,
                              foregroundContent: content, backgroundContent: content, trigger: .immediate)
            mockAlertStore.storedAlerts = [StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)]

            alertManager = AlertManager(alertPresenter: mockPresenter,
                                        modalAlertScheduler: mockModalScheduler,
                                        userNotificationAlertScheduler: mockUserNotificationScheduler,
                                        fileManager: mockFileManager,
                                        alertStore: mockAlertStore,
                                        bluetoothProvider: MockBluetoothProvider(),
                                        analyticsServicesManager: AnalyticsServicesManager())
            alertManager.playbackAlertsFromPersistence()
            XCTAssertEqual(alert, mockModalScheduler.scheduledAlert)
            XCTAssertNil(mockUserNotificationScheduler.scheduledAlert)
        }
    }
    
    func testPlaybackPendingExpiredDelayedNotification() {
        mockAlertStore.managedObjectContext.performAndWait {
            let date = Date.distantPast
            let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
            let alert = Alert(identifier: Self.mockIdentifier,
                              foregroundContent: content, backgroundContent: content, trigger: .delayed(interval: 30.0))
            let storedAlert = StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)
            storedAlert.issuedDate = date
            mockAlertStore.storedAlerts = [storedAlert]
            alertManager = AlertManager(alertPresenter: mockPresenter,
                                        modalAlertScheduler: mockModalScheduler,
                                        userNotificationAlertScheduler: mockUserNotificationScheduler,
                                        fileManager: mockFileManager,
                                        alertStore: mockAlertStore,
                                        bluetoothProvider: MockBluetoothProvider(),
                                        analyticsServicesManager: AnalyticsServicesManager())
            alertManager.playbackAlertsFromPersistence()
            let expected = Alert(identifier: Self.mockIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate)
            XCTAssertEqual(expected, mockModalScheduler.scheduledAlert)
            XCTAssertNil(mockUserNotificationScheduler.scheduledAlert)
        }
    }
    
    func testPlaybackPendingDelayedNotification() {
        mockAlertStore.managedObjectContext.performAndWait {
            let date = Date().addingTimeInterval(-15.0) // Pretend the 30-second-delayed alert was issued 15 seconds ago
            let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
            let alert = Alert(identifier: Self.mockIdentifier,
                              foregroundContent: content, backgroundContent: content, trigger: .delayed(interval: 30.0))
            let storedAlert = StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)
            storedAlert.issuedDate = date
            mockAlertStore.storedAlerts = [storedAlert]
            alertManager = AlertManager(alertPresenter: mockPresenter,
                                        modalAlertScheduler: mockModalScheduler,
                                        userNotificationAlertScheduler: mockUserNotificationScheduler,
                                        fileManager: mockFileManager,
                                        alertStore: mockAlertStore,
                                        bluetoothProvider: MockBluetoothProvider(),
                                        analyticsServicesManager: AnalyticsServicesManager())
            alertManager.playbackAlertsFromPersistence()

            // The trigger for this should be `.delayed` by "something less than 15 seconds",
            // but the exact value depends on the speed of executing this test.
            // As long as it is <= 15 seconds, we call it good.
            XCTAssertNotNil(mockModalScheduler.scheduledAlert)
            switch mockModalScheduler.scheduledAlert?.trigger {
            case .some(.delayed(let interval)):
                XCTAssertLessThanOrEqual(interval, 15.0)
            default:
                XCTFail("Wrong trigger \(String(describing: mockModalScheduler.scheduledAlert?.trigger))")
            }
        }
    }
    
    func testPlaybackPendingRepeatingNotification() {
        mockAlertStore.managedObjectContext.performAndWait {
            let date = Date.distantPast
            let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
            let alert = Alert(identifier: Self.mockIdentifier,
                              foregroundContent: content, backgroundContent: content, trigger: .repeating(repeatInterval: 60.0))
            let storedAlert = StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)
            storedAlert.issuedDate = date
            mockAlertStore.storedAlerts = [storedAlert]
            alertManager = AlertManager(alertPresenter: mockPresenter,
                                        modalAlertScheduler: mockModalScheduler,
                                        userNotificationAlertScheduler: mockUserNotificationScheduler,
                                        fileManager: mockFileManager,
                                        alertStore: mockAlertStore,
                                        bluetoothProvider: MockBluetoothProvider(),
                                        analyticsServicesManager: AnalyticsServicesManager())
            alertManager.playbackAlertsFromPersistence()

            XCTAssertEqual(alert, mockModalScheduler.scheduledAlert)
            XCTAssertNil(mockUserNotificationScheduler.scheduledAlert)
        }
    }
    
    func testPersistedAlertStoreLookupAllUnretracted() throws {
        mockAlertStore.managedObjectContext.performAndWait {
            let date = Date.distantPast
            let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
            let alert = Alert(identifier: Self.mockIdentifier,
                              foregroundContent: content, backgroundContent: content, trigger: .repeating(repeatInterval: 60.0))
            let storedAlert = StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)
            storedAlert.issuedDate = date
            mockAlertStore.storedAlerts = [storedAlert]
            alertManager = AlertManager(alertPresenter: mockPresenter,
                                        modalAlertScheduler: mockModalScheduler,
                                        userNotificationAlertScheduler: mockUserNotificationScheduler,
                                        fileManager: mockFileManager,
                                        alertStore: mockAlertStore,
                                        bluetoothProvider: MockBluetoothProvider(),
                                        analyticsServicesManager: AnalyticsServicesManager())
            alertManager.lookupAllUnretracted(managerIdentifier: Self.mockManagerIdentifier) { result in
                try? XCTAssertEqual([PersistedAlert(alert: alert, issuedDate: date, retractedDate: nil, acknowledgedDate: nil)],
                                    XCTUnwrap(result.successValue))
            }
        }
    }

    func testPersistedAlertStoreLookupAllUnacknowledgedUnretracted() throws {
        mockAlertStore.managedObjectContext.performAndWait {
            let date = Date.distantPast
            let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
            let alert = Alert(identifier: Self.mockIdentifier,
                              foregroundContent: content, backgroundContent: content, trigger: .repeating(repeatInterval: 60.0))
            let storedAlert = StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)
            storedAlert.issuedDate = date
            mockAlertStore.storedAlerts = [storedAlert]
            alertManager = AlertManager(alertPresenter: mockPresenter,
                                        modalAlertScheduler: mockModalScheduler,
                                        userNotificationAlertScheduler: mockUserNotificationScheduler,
                                        fileManager: mockFileManager,
                                        alertStore: mockAlertStore,
                                        bluetoothProvider: MockBluetoothProvider(),
                                        analyticsServicesManager: AnalyticsServicesManager())
            alertManager.lookupAllUnacknowledgedUnretracted(managerIdentifier: Self.mockManagerIdentifier) { result in
                try? XCTAssertEqual([PersistedAlert(alert: alert, issuedDate: date, retractedDate: nil, acknowledgedDate: nil)],
                                    XCTUnwrap(result.successValue))
            }
        }
    }

    func testPersistedAlertStoreDoesIssuedAlertExist() throws {
        mockAlertStore.managedObjectContext.performAndWait {
            let date = Date.distantPast
            let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
            let alert = Alert(identifier: Self.mockIdentifier,
                              foregroundContent: content, backgroundContent: content, trigger: .repeating(repeatInterval: 60.0))
            let storedAlert = StoredAlert(from: alert, context: mockAlertStore.managedObjectContext)
            storedAlert.issuedDate = date
            mockAlertStore.storedAlerts = [storedAlert]
            alertManager = AlertManager(alertPresenter: mockPresenter,
                                        modalAlertScheduler: mockModalScheduler,
                                        userNotificationAlertScheduler: mockUserNotificationScheduler,
                                        fileManager: mockFileManager,
                                        alertStore: mockAlertStore,
                                        bluetoothProvider: MockBluetoothProvider(),
                                        analyticsServicesManager: AnalyticsServicesManager())
            let identifierExists = Self.mockIdentifier
            let identifierDoesNotExist = Alert.Identifier(managerIdentifier: "TestManagerIdentifier", alertIdentifier: "TestAlertIdentifier")
            alertManager.doesIssuedAlertExist(identifier: identifierExists) { result in
                try? XCTAssertEqual(true, XCTUnwrap(result.successValue))
            }
            alertManager.doesIssuedAlertExist(identifier: identifierDoesNotExist) { result in
                try? XCTAssertEqual(false, XCTUnwrap(result.successValue))
            }
        }
    }

    func testReportRetractedAlert() throws {
        mockAlertStore.managedObjectContext.performAndWait {
            let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
            let alert = Alert(identifier: Self.mockIdentifier,
                              foregroundContent: content, backgroundContent: content, trigger: .repeating(repeatInterval: 60.0))
            mockAlertStore.storedAlerts = []
            alertManager = AlertManager(alertPresenter: mockPresenter,
                                        modalAlertScheduler: mockModalScheduler,
                                        userNotificationAlertScheduler: mockUserNotificationScheduler,
                                        fileManager: mockFileManager,
                                        alertStore: mockAlertStore,
                                        bluetoothProvider: MockBluetoothProvider(),
                                        analyticsServicesManager: AnalyticsServicesManager())
            let now = Date()
            alertManager.recordRetractedAlert(alert, at: now)
            XCTAssertEqual(mockAlertStore.retractedAlert, alert)
            XCTAssertEqual(mockAlertStore.retractedAlertDate, now)
        }
    }

    func testScheduleAlertForWorkoutReminder() {
        alertManager.presetActivated(context: .legacyWorkout, duration: .indefinite)
        XCTAssertEqual(AlertManager.workoutOverrideReminderAlertIdentifier, mockModalScheduler.scheduledAlert?.identifier)
        XCTAssertEqual(AlertManager.workoutOverrideReminderAlertIdentifier, mockUserNotificationScheduler.scheduledAlert?.identifier)
        XCTAssertEqual(AlertManager.workoutOverrideReminderAlertIdentifier, mockAlertStore.issuedAlert?.identifier)

        alertManager.presetDeactivated(context: .legacyWorkout)
        XCTAssertEqual(AlertManager.workoutOverrideReminderAlertIdentifier, mockModalScheduler.unscheduledAlertIdentifier)
        XCTAssertEqual(AlertManager.workoutOverrideReminderAlertIdentifier, mockUserNotificationScheduler.unscheduledAlertIdentifier)
        XCTAssertEqual(AlertManager.workoutOverrideReminderAlertIdentifier, mockAlertStore.retractededAlertIdentifier)
    }

    func testLoopDidCompleteRecordsNotifications() {
        alertManager.loopDidComplete()
        XCTAssertEqual(4, UserDefaults.appGroup?.loopNotRunningNotifications.count)
    }

    func testLoopFailureFor10MinutesDoesNotRecordAlert() {
        alertManager.loopDidComplete()
        XCTAssertNil(mockAlertStore.issuedAlert)
        alertManager.getCurrentDate = { return Date().addingTimeInterval(.minutes(10))}
        alertManager.inferDeliveredLoopNotRunningNotifications()
        XCTAssertNil(mockAlertStore.issuedAlert)
    }

    func testLoopFailureFor30MinutesRecordsTimeSensitiveAlert() {
        alertManager.loopDidComplete()
        XCTAssertNil(mockAlertStore.issuedAlert)
        alertManager.getCurrentDate = { return Date().addingTimeInterval(.minutes(30))}
        alertManager.inferDeliveredLoopNotRunningNotifications()
        XCTAssertEqual(3, UserDefaults.appGroup?.loopNotRunningNotifications.count)
        XCTAssertNotNil(mockAlertStore.issuedAlert)
        XCTAssertEqual(.timeSensitive, mockAlertStore.issuedAlert!.interruptionLevel)
    }

    func testLoopFailureFor65MinutesRecordsCriticalAlert() {
        alertManager.loopDidComplete()
        alertManager.getCurrentDate = { return Date().addingTimeInterval(.minutes(65))}
        alertManager.inferDeliveredLoopNotRunningNotifications()
        XCTAssertEqual(1, UserDefaults.appGroup?.loopNotRunningNotifications.count)
        XCTAssertNotNil(mockAlertStore.issuedAlert)
        XCTAssertEqual(.critical, mockAlertStore.issuedAlert!.interruptionLevel)
    }

    func testRescheduleMutedLoopNotLoopingAlerts() {
        let lastLoopDate = Date()
        alertManager.loopDidComplete(lastLoopDate)
        alertManager.alertMuter.configuration.startTime = Date()
        alertManager.alertMuter.configuration.duration = .hours(4)
        waitOnMain()
        
        let testExpectation = expectation(description: #function)
        var loopNotRunningRequests: [UNNotificationRequest] = []
        UNUserNotificationCenter.current().getPendingNotificationRequests() { notificationRequests in
            loopNotRunningRequests = notificationRequests.filter({
                $0.content.categoryIdentifier == LoopNotificationCategory.loopNotRunning.rawValue
            })
            testExpectation.fulfill()
        }

        wait(for: [testExpectation], timeout: 1)
        if #available(iOS 15.0, *) {
            XCTAssertNil(loopNotRunningRequests.first(where: { $0.content.interruptionLevel == .timeSensitive })?.content.sound)
            if let request = loopNotRunningRequests.first(where: { $0.content.interruptionLevel == .critical }) {
                XCTAssertEqual(request.content.sound, .defaultCriticalSound(withAudioVolume: 0))
            }
        } else if FeatureFlags.criticalAlertsEnabled {
            for request in loopNotRunningRequests {
                let sound = request.content.sound
                XCTAssertTrue(sound == nil || sound == .defaultCriticalSound(withAudioVolume: 0.0))
            }
        } else {
            for request in loopNotRunningRequests {
                XCTAssertNil(request.content.sound)
            }
        }
    }
}

extension Swift.Result {
    var successValue: Success? {
        switch self {
        case .failure: return nil
        case .success(let s): return s
        }
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
