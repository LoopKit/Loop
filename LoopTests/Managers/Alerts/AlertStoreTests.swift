//
//  AlertStoreTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 5/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import CoreData
import LoopKit
import XCTest
@testable import Loop

class AlertStoreTests: XCTestCase {
    
    var alertStore: AlertStore!
    
    static let identifier1 = DeviceAlert.Identifier(managerIdentifier: "managerIdentifier1", alertIdentifier: "alertIdentifier1")
    let alert1 = DeviceAlert(identifier: identifier1, foregroundContent: nil, backgroundContent: nil, trigger: .immediate, sound: nil)
    static let identifier2 = DeviceAlert.Identifier(managerIdentifier: "managerIdentifier2", alertIdentifier: "alertIdentifier2")
    static let content = DeviceAlert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label", isCritical: true)
    let alert2 = DeviceAlert(identifier: identifier2, foregroundContent: content, backgroundContent: content, trigger: .immediate, sound: .sound(name: "soundName"))

    override func setUp() {
        alertStore = AlertStore()
    }
    
    override func tearDown() {
        alertStore = nil
    }
    
    func testTriggerTypeIntervalConversion() {
        let immediate = DeviceAlert.Trigger.immediate
        let delayed = DeviceAlert.Trigger.delayed(interval: 1.0)
        let repeating = DeviceAlert.Trigger.repeating(repeatInterval: 2.0)
        XCTAssertEqual(immediate, try? DeviceAlert.Trigger(storedType: immediate.storedType, storedInterval: immediate.storedInterval))
        XCTAssertEqual(delayed, try? DeviceAlert.Trigger(storedType: delayed.storedType, storedInterval: delayed.storedInterval))
        XCTAssertEqual(repeating, try? DeviceAlert.Trigger(storedType: repeating.storedType, storedInterval: repeating.storedInterval))
        XCTAssertNil(immediate.storedInterval)
    }
    
    func testStoredAlertSerialization() {
        let object = StoredAlert(from: alert2, context: alertStore.managedObjectContext, issuedDate: Date.distantPast)
        XCTAssertNil(object.acknowledgedDate)
        XCTAssertNil(object.retractedDate)
        XCTAssertEqual("{\"body\":\"body\",\"isCritical\":true,\"title\":\"title\",\"acknowledgeActionButtonLabel\":\"label\"}", object.backgroundContent)
        XCTAssertEqual("{\"body\":\"body\",\"isCritical\":true,\"title\":\"title\",\"acknowledgeActionButtonLabel\":\"label\"}", object.foregroundContent)
        XCTAssertEqual("managerIdentifier2.alertIdentifier2", object.identifier.value)
        XCTAssertEqual(true, object.isCritical)
        XCTAssertEqual(Date.distantPast, object.issuedDate)
        XCTAssertEqual(0, object.modificationCounter)
        XCTAssertEqual("{\"sound\":{\"name\":\"soundName\"}}", object.sound)
        XCTAssertEqual(DeviceAlert.Trigger.immediate, object.trigger)
    }
    
    func testRecordIssued() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast) {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)")
            case .success:
                self.alertStore.fetch(identifier: Self.identifier1) {
                    switch $0 {
                        case .failure(let error): XCTFail("Unexpected \(error)")
                        case .success(let storedAlerts):
                            XCTAssertEqual(1, storedAlerts.count)
                            XCTAssertEqual(Self.identifier1, storedAlerts[0].identifier)
                            XCTAssertEqual(Date.distantPast, storedAlerts[0].issuedDate)
                            XCTAssertNil(storedAlerts[0].acknowledgedDate)
                            XCTAssertNil(storedAlerts[0].retractedDate)
                    }
                    expect.fulfill()
                }
            }
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordAcknowledged() {
        let expect = self.expectation(description: #function)
        let issuedDate = Date.distantPast
        let acknowledgedDate = issuedDate.addingTimeInterval(1)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast) {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)")
            case .success:
                self.alertStore.recordAcknowledgement(of: Self.identifier1, at: acknowledgedDate) {
                    switch $0 {
                    case .failure(let error): XCTFail("Unexpected \(error)")
                    case .success:
                        self.alertStore.fetch(identifier: Self.identifier1) {
                            switch $0 {
                            case .failure(let error): XCTFail("Unexpected \(error)")
                            case .success(let storedAlerts):
                                XCTAssertEqual(1, storedAlerts.count)
                                XCTAssertEqual(Self.identifier1, storedAlerts[0].identifier)
                                XCTAssertEqual(issuedDate, storedAlerts[0].issuedDate)
                                XCTAssertEqual(acknowledgedDate, storedAlerts[0].acknowledgedDate)
                                XCTAssertNil(storedAlerts[0].retractedDate)
                            }
                            expect.fulfill()
                        }
                    }
                }
            }
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordRetracted() {
        let expect = self.expectation(description: #function)
        let issuedDate = Date.distantPast
        let retractedDate = issuedDate.addingTimeInterval(2)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast) {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)")
            case .success:
                self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate) {
                    switch $0 {
                    case .failure(let error): XCTFail("Unexpected \(error)")
                    case .success:
                        self.alertStore.fetch(identifier: Self.identifier1) {
                            switch $0 {
                            case .failure(let error): XCTFail("Unexpected \(error)")
                            case .success(let storedAlerts):
                                XCTAssertEqual(1, storedAlerts.count)
                                XCTAssertEqual(Self.identifier1, storedAlerts[0].identifier)
                                XCTAssertEqual(issuedDate, storedAlerts[0].issuedDate)
                                XCTAssertEqual(retractedDate, storedAlerts[0].retractedDate)
                                XCTAssertNil(storedAlerts[0].acknowledgedDate)
                            }
                            expect.fulfill()
                        }
                    }
                }
            }
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testEmptyQuery() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast) {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)")
            case .success:
                self.alertStore.executeQuery(since: Date.distantPast, limit: 0) {
                    switch $0 {
                    case .failure(let error): XCTFail("Unexpected \(error)")
                    case .success(let (_, storedAlerts)):
                        XCTAssertTrue(storedAlerts.isEmpty)
                        expect.fulfill()
                    }
                }
            }
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testSimpleQuery() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast) {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)")
            case .success:
                self.alertStore.executeQuery(since: Date.distantPast, limit: 100) {
                    switch $0 {
                    case .failure(let error): XCTFail("Unexpected \(error)")
                    case .success(let (anchor, storedAlerts)):
                        XCTAssertEqual(1, anchor.modificationCounter)
                        XCTAssertEqual(1, storedAlerts.count)
                        XCTAssertEqual(Self.identifier1, storedAlerts[0].identifier)
                        XCTAssertEqual(Date.distantPast, storedAlerts[0].issuedDate)
                        XCTAssertNil(storedAlerts[0].acknowledgedDate)
                        XCTAssertNil(storedAlerts[0].retractedDate)
                        expect.fulfill()
                    }
                }
            }
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testSimpleQueryThenRetraction() {
        let expect = self.expectation(description: #function)
        let issuedDate = Date.distantPast
        let retractedDate = issuedDate.addingTimeInterval(2)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast) {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)")
            case .success:
                self.alertStore.executeQuery(since: Date.distantPast, limit: 100) {
                    switch $0 {
                    case .failure(let error): XCTFail("Unexpected \(error)")
                    case .success(let (anchor, storedAlerts)):
                        XCTAssertEqual(1, anchor.modificationCounter)
                        XCTAssertEqual(1, storedAlerts.count)
                        XCTAssertEqual(Self.identifier1, storedAlerts[0].identifier)
                        XCTAssertEqual(Date.distantPast, storedAlerts[0].issuedDate)
                        XCTAssertNil(storedAlerts[0].acknowledgedDate)
                        XCTAssertNil(storedAlerts[0].retractedDate)
                        self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate) {
                            switch $0 {
                            case .failure(let error): XCTFail("Unexpected \(error)")
                            case .success:
                                self.alertStore.executeQuery(since: Date.distantPast, limit: 100) {
                                    switch $0 {
                                    case .failure(let error): XCTFail("Unexpected \(error)")
                                    case .success(let (anchor, storedAlerts)):
                                        XCTAssertEqual(2, anchor.modificationCounter)
                                        XCTAssertEqual(1, storedAlerts.count)
                                        XCTAssertEqual(Self.identifier1, storedAlerts[0].identifier)
                                        XCTAssertEqual(issuedDate, storedAlerts[0].issuedDate)
                                        XCTAssertEqual(retractedDate, storedAlerts[0].retractedDate)
                                        XCTAssertNil(storedAlerts[0].acknowledgedDate)
                                    }
                                    expect.fulfill()
                                }
                            }
                        }
                    }
                }
            }
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testQueryByDate() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast) {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)")
            case .success:
                let now = Date()
                self.alertStore.recordIssued(alert: self.alert2, at: now) {
                    switch $0 {
                    case .failure(let error): XCTFail("Unexpected \(error)")
                    case .success:
                        self.alertStore.executeQuery(since: now, limit: 100) {
                            switch $0 {
                            case .failure(let error): XCTFail("Unexpected \(error)")
                            case .success(let (anchor, storedAlerts)):
                                XCTAssertEqual(2, anchor.modificationCounter)
                                XCTAssertEqual(1, storedAlerts.count)
                                XCTAssertEqual(Self.identifier2, storedAlerts[0].identifier)
                                XCTAssertEqual(now, storedAlerts[0].issuedDate)
                                XCTAssertNil(storedAlerts[0].acknowledgedDate)
                                XCTAssertNil(storedAlerts[0].retractedDate)
                                expect.fulfill()
                            }
                        }
                    }
                }
            }
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testQueryWithLimit() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast) {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)")
            case .success:
                self.alertStore.recordIssued(alert: self.alert2, at: Date()) {
                    switch $0 {
                    case .failure(let error): XCTFail("Unexpected \(error)")
                    case .success:
                        self.alertStore.executeQuery(since: Date.distantPast, limit: 1) {
                            switch $0 {
                            case .failure(let error): XCTFail("Unexpected \(error)")
                            case .success(let (anchor, storedAlerts)):
                                XCTAssertEqual(1, anchor.modificationCounter)
                                XCTAssertEqual(1, storedAlerts.count)
                                XCTAssertEqual(Self.identifier1, storedAlerts[0].identifier)
                                XCTAssertEqual(Date.distantPast, storedAlerts[0].issuedDate)
                                XCTAssertNil(storedAlerts[0].acknowledgedDate)
                                XCTAssertNil(storedAlerts[0].retractedDate)
                                expect.fulfill()
                            }
                        }
                    }
                }
            }
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testQueryThenContinue() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast) {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)")
            case .success:
                let now = Date()
                self.alertStore.recordIssued(alert: self.alert2, at: now) {
                    switch $0 {
                    case .failure(let error): XCTFail("Unexpected \(error)")
                    case .success:
                        self.alertStore.executeQuery(since: Date.distantPast, limit: 1) {
                            switch $0 {
                            case .failure(let error): XCTFail("Unexpected \(error)")
                            case .success(let (anchor, _)):
                                self.alertStore.continueQuery(from: anchor, limit: 1) {
                                    switch $0 {
                                    case .failure(let error): XCTFail("Unexpected \(error)")
                                    case .success(let (anchor, storedAlerts)):
                                        XCTAssertEqual(2, anchor.modificationCounter)
                                        XCTAssertEqual(1, storedAlerts.count)
                                        XCTAssertEqual(Self.identifier2, storedAlerts[0].identifier)
                                        XCTAssertEqual(now, storedAlerts[0].issuedDate)
                                        XCTAssertNil(storedAlerts[0].acknowledgedDate)
                                        XCTAssertNil(storedAlerts[0].retractedDate)
                                        expect.fulfill()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        wait(for: [expect], timeout: 1)
    }

}
