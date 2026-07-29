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
    
    func testIssueAlertOnHandlerCalled() async {
        await alertManager.issueAlert(mockAlert)
        XCTAssertEqual(mockAlert.identifier, mockModalScheduler.scheduledAlert?.identifier)
        XCTAssertEqual(mockAlert.identifier, mockUserNotificationScheduler.scheduledAlert?.identifier)
        XCTAssertNil(mockModalScheduler.unscheduledAlertIdentifier)
        XCTAssertNil(mockUserNotificationScheduler.unscheduledAlertIdentifier)
    }
    
    func testRetractAlertOnHandlerCalled() async {
        await alertManager.retractAlert(identifier: mockAlert.identifier)
        XCTAssertNil(mockModalScheduler.scheduledAlert)
        XCTAssertNil(mockUserNotificationScheduler.scheduledAlert)
        XCTAssertEqual(mockAlert.identifier, mockModalScheduler.unscheduledAlertIdentifier)
        XCTAssertEqual(mockAlert.identifier, mockUserNotificationScheduler.unscheduledAlertIdentifier)
    }
    
    func testAlertResponderAcknowledged() async throws {
        let responder = MockResponder()
        alertManager.addAlertResponder(managerIdentifier: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        try await alertManager.acknowledgeAlert(identifier: Self.mockIdentifier)
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == true)
    }
    
    func testAlertResponderNotAcknowledgedIfWrongManagerIdentifier() async throws {
        let responder = MockResponder()
        alertManager.addAlertResponder(managerIdentifier: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        try await alertManager.acknowledgeAlert(identifier: Alert.Identifier(managerIdentifier: "foo", alertIdentifier: Self.mockTypeIdentifier))
        XCTAssertTrue(responder.acknowledged.isEmpty)
    }
    
    func testRemovedAlertResponderDoesntAcknowledge() async throws {
        let responder = MockResponder()
        alertManager.addAlertResponder(managerIdentifier: Self.mockManagerIdentifier, alertResponder: responder)
        XCTAssertTrue(responder.acknowledged.isEmpty)
        try await alertManager.acknowledgeAlert(identifier: Self.mockIdentifier)
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == true)
        
        responder.acknowledged[AlertManagerTests.mockTypeIdentifier] = false
        alertManager.removeAlertResponder(managerIdentifier: AlertManagerTests.mockManagerIdentifier)
        try await alertManager.acknowledgeAlert(identifier: Self.mockIdentifier)
        XCTAssert(responder.acknowledged[Self.mockTypeIdentifier] == false)
    }
    
    func testAcknowledgedAlertsRemovedFromUserNotificationCenter() async throws {
        try await alertManager.acknowledgeAlert(identifier: Self.mockIdentifier)
    }
    
    func testSoundVendorInitialization() {
        let soundVendor = MockSoundVendor()
        alertManager.addAlertSoundVendor(managerIdentifier: Self.mockManagerIdentifier, soundVendor: soundVendor)
        XCTAssertEqual("Sounds", mockFileManager.createdDirURL?.lastPathComponent)
        XCTAssertEqual(["\(Self.mockManagerIdentifier)-existsOlder"], mockFileManager.removedURLs.map { $0.lastPathComponent })
        XCTAssertEqual(["doesntExist", "existsOlder"], mockFileManager.copiedSrcURLs.map { $0.lastPathComponent })
        XCTAssertEqual(["\(Self.mockManagerIdentifier)-doesntExist", "\(Self.mockManagerIdentifier)-existsOlder"], mockFileManager.copiedDstURLs.map { $0.lastPathComponent })
    }
        
    func testPlaybackPendingImmediateAlert() async {
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
        mockModalScheduler.alertScheduledExpectation = expectation(description: "alert scheduled")
        await alertManager.playbackAlertsFromPersistence()
        await fulfillment(of: [mockModalScheduler.alertScheduledExpectation!])
        XCTAssertEqual(alert, mockModalScheduler.scheduledAlert)
        XCTAssertNil(mockUserNotificationScheduler.scheduledAlert)
    }
    
    func testPlaybackPendingExpiredDelayedNotification() async {
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
        await alertManager.playbackAlertsFromPersistence()
        let expected = Alert(identifier: Self.mockIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate)
        XCTAssertEqual(expected, mockModalScheduler.scheduledAlert)
        XCTAssertNil(mockUserNotificationScheduler.scheduledAlert)
    }
    
    func testPlaybackPendingDelayedNotification() async {
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
        await alertManager.playbackAlertsFromPersistence()

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
    
    func testPlaybackPendingRepeatingNotification() async {
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
        await alertManager.playbackAlertsFromPersistence()

        XCTAssertEqual(alert, mockModalScheduler.scheduledAlert)
        XCTAssertNil(mockUserNotificationScheduler.scheduledAlert)
    }
    
    func testPersistedAlertStoreLookupAllUnretracted() async throws {
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
        let alerts = try await alertManager.lookupAllUnretracted(managerIdentifier: Self.mockManagerIdentifier)
        XCTAssertEqual([PersistedAlert(alert: alert, issuedDate: date, retractedDate: nil, acknowledgedDate: nil)], alerts)
    }

    func testPersistedAlertStoreLookupAllUnacknowledgedUnretracted() async throws {
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
        let alerts = try await alertManager.lookupAllUnacknowledgedUnretracted(managerIdentifier: Self.mockManagerIdentifier)
        XCTAssertEqual([PersistedAlert(alert: alert, issuedDate: date, retractedDate: nil, acknowledgedDate: nil)], alerts)
    }

    func testPersistedAlertStoreDoesIssuedAlertExist() async throws {
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
        let result = try await alertManager.doesIssuedAlertExist(identifier: identifierExists)
        XCTAssertEqual(true, result)
        let result2 = try await alertManager.doesIssuedAlertExist(identifier: identifierDoesNotExist)
        XCTAssertEqual(false, result2)
    }

    func testReportRetractedAlert() async throws {
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
        try await alertManager.recordRetractedAlert(alert, at: now)
        XCTAssertEqual(mockAlertStore.retractedAlert, alert)
        XCTAssertEqual(mockAlertStore.retractedAlertDate, now)
    }

    func testLoopDidCompleteRecordsNotifications() async {
        await alertManager.loopDidComplete()
        XCTAssertEqual(4, UserDefaults.appGroup?.loopNotRunningNotifications.count)
    }

    func testLoopFailureFor10MinutesDoesNotRecordAlert() async {
        await alertManager.loopDidComplete()
        XCTAssertNil(mockAlertStore.issuedAlert)
        alertManager.getCurrentDate = { return Date().addingTimeInterval(.minutes(10))}
        await alertManager.inferDeliveredLoopNotRunningNotifications()
        XCTAssertNil(mockAlertStore.issuedAlert)
    }

    func testLoopFailureFor30MinutesRecordsTimeSensitiveAlert() async {
        await alertManager.loopDidComplete()
        XCTAssertNil(mockAlertStore.issuedAlert)
        alertManager.getCurrentDate = { return Date().addingTimeInterval(.minutes(30))}
        await alertManager.inferDeliveredLoopNotRunningNotifications()
        XCTAssertEqual(3, UserDefaults.appGroup?.loopNotRunningNotifications.count)
        XCTAssertNotNil(mockAlertStore.issuedAlert)
        XCTAssertEqual(.timeSensitive, mockAlertStore.issuedAlert!.interruptionLevel)
    }

    func testLoopFailureFor65MinutesRecordsCriticalAlert() async {
        await alertManager.loopDidComplete()
        alertManager.getCurrentDate = { return Date().addingTimeInterval(.minutes(65))}
        await alertManager.inferDeliveredLoopNotRunningNotifications()
        XCTAssertEqual(1, UserDefaults.appGroup?.loopNotRunningNotifications.count)
        XCTAssertNotNil(mockAlertStore.issuedAlert)
        XCTAssertEqual(.critical, mockAlertStore.issuedAlert!.interruptionLevel)
    }

    func testRescheduleMutedLoopNotLoopingAlerts() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        let lastLoopDate = Date()
        await alertManager.loopDidComplete(lastLoopDate)

        // Turn on muting, then reschedule the loop-not-running alerts as muted.
        // In production this reschedule is driven asynchronously by the
        // alertMuter.$configuration sink (RunLoop.main hop + a detached Task), so
        // await it directly here rather than racing that pipeline.
        alertManager.alertMuter.configuration = AlertMuter.Configuration(startTime: Date(), duration: .hours(4))
        await alertManager.rescheduleLoopNotRunningNotifications(lastLoopDate)

        let loopNotRunningRequests = await UNUserNotificationCenter.current().pendingNotificationRequests().filter({
            $0.content.categoryIdentifier == LoopNotificationCategory.loopNotRunning.rawValue
        })
        XCTAssertNil(loopNotRunningRequests.first(where: { $0.content.interruptionLevel == .timeSensitive })?.content.sound)
        if let request = loopNotRunningRequests.first(where: { $0.content.interruptionLevel == .critical }) {
            XCTAssertEqual(request.content.sound, .defaultCriticalSound(withAudioVolume: 0))
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
