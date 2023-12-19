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

@MainActor
class AlertManagerTests: XCTestCase {

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
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
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
