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

    static let expiryInterval: TimeInterval = 24 /* hours */ * 60 /* minutes */ * 60 /* seconds */
    static let historicDate = Date(timeIntervalSinceNow: -expiryInterval + TimeInterval.hours(4))  // Within default 24 hour expiration
    
    static let identifier1 = Alert.Identifier(managerIdentifier: "managerIdentifier1", alertIdentifier: "alertIdentifier1")
    let alert1 = Alert(identifier: identifier1, foregroundContent: nil, backgroundContent: nil, trigger: .immediate, sound: nil)
    static let identifier2 = Alert.Identifier(managerIdentifier: "managerIdentifier2", alertIdentifier: "alertIdentifier2")
    static let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label", isCritical: true)
    let alert2 = Alert(identifier: identifier2, foregroundContent: content, backgroundContent: content, trigger: .immediate, sound: .sound(name: "soundName"))
    static let delayedAlertDelay = 30.0 // seconds
    static let delayedAlertIdentifier = Alert.Identifier(managerIdentifier: "managerIdentifier3", alertIdentifier: "alertIdentifier3")
    let delayedAlert = Alert(identifier: delayedAlertIdentifier, foregroundContent: nil, backgroundContent: nil, trigger: .delayed(interval: delayedAlertDelay), sound: nil)
    static let repeatingAlertDelay = 30.0 // seconds
    static let repeatingAlertIdentifier = Alert.Identifier(managerIdentifier: "managerIdentifier4", alertIdentifier: "alertIdentifier4")
    let repeatingAlert = Alert(identifier: repeatingAlertIdentifier, foregroundContent: nil, backgroundContent: nil, trigger: .repeating(repeatInterval: repeatingAlertDelay), sound: nil)

    override func setUp() {
        alertStore = AlertStore(expireAfter: Self.expiryInterval)
    }
    
    override func tearDown() {
        alertStore = nil
    }
    
    func testTriggerTypeIntervalConversion() {
        let immediate = Alert.Trigger.immediate
        let delayed = Alert.Trigger.delayed(interval: 1.0)
        let repeating = Alert.Trigger.repeating(repeatInterval: 2.0)
        XCTAssertEqual(immediate, try? Alert.Trigger(storedType: immediate.storedType, storedInterval: immediate.storedInterval))
        XCTAssertEqual(delayed, try? Alert.Trigger(storedType: delayed.storedType, storedInterval: delayed.storedInterval))
        XCTAssertEqual(repeating, try? Alert.Trigger(storedType: repeating.storedType, storedInterval: repeating.storedInterval))
        XCTAssertNil(immediate.storedInterval)
    }
    
    func testTriggerTypeIntervalConversionAdjustedForStorageTime() {
        let immediate = Alert.Trigger.immediate
        let delayed = Alert.Trigger.delayed(interval: 10.0)
        let repeating = Alert.Trigger.repeating(repeatInterval: 20.0)
        XCTAssertEqual(immediate, try? Alert.Trigger(storedType: immediate.storedType, storedInterval: immediate.storedInterval, storageDate: Self.historicDate))
        XCTAssertEqual(immediate, try? Alert.Trigger(storedType: delayed.storedType, storedInterval: delayed.storedInterval, storageDate: Self.historicDate))
        XCTAssertEqual(immediate, try? Alert.Trigger(storedType: delayed.storedType, storedInterval: delayed.storedInterval, storageDate: Date(timeIntervalSinceNow: -10.0.nextUp)))
        XCTAssertEqual(Alert.Trigger.delayed(interval: 10.0), try? Alert.Trigger(storedType: delayed.storedType, storedInterval: delayed.storedInterval, storageDate: Date(timeIntervalSinceNow: 5.0)))
        let adjustedTrigger = try? Alert.Trigger(storedType: delayed.storedType, storedInterval: delayed.storedInterval, storageDate: Date(timeIntervalSinceNow: -5.0))
        switch adjustedTrigger {
        case .delayed(let interval): XCTAssertLessThanOrEqual(interval, 5.0) // The new delay interval value may be close to, but no more than 5, but not exact
        default: XCTFail("Wrong trigger")
        }
        XCTAssertEqual(repeating, try? Alert.Trigger(storedType: repeating.storedType, storedInterval: repeating.storedInterval, storageDate: Self.historicDate))
        XCTAssertNil(immediate.storedInterval)
    }
    
    func testStoredAlertSerialization() {
        let object = StoredAlert(from: alert2, context: alertStore.managedObjectContext, issuedDate: Self.historicDate)
        XCTAssertNil(object.acknowledgedDate)
        XCTAssertNil(object.retractedDate)
        XCTAssertEqual("{\"body\":\"body\",\"isCritical\":true,\"title\":\"title\",\"acknowledgeActionButtonLabel\":\"label\"}", object.backgroundContent)
        XCTAssertEqual("{\"body\":\"body\",\"isCritical\":true,\"title\":\"title\",\"acknowledgeActionButtonLabel\":\"label\"}", object.foregroundContent)
        XCTAssertEqual("managerIdentifier2.alertIdentifier2", object.identifier.value)
        XCTAssertEqual(true, object.isCritical)
        XCTAssertEqual(Self.historicDate, object.issuedDate)
        XCTAssertEqual(1, object.modificationCounter)
        XCTAssertEqual("{\"sound\":{\"name\":\"soundName\"}}", object.sound)
        XCTAssertEqual(Alert.Trigger.immediate, object.trigger)
    }
    
    func testQueryAnchorSerialization() {
        let anchor = AlertStore.QueryAnchor<AlertStore.NoFilter>(modificationCounter: 999, filter: nil)
        let newAnchor = AlertStore.QueryAnchor<AlertStore.NoFilter>(rawValue: anchor.rawValue)
        XCTAssertEqual(anchor, newAnchor)
        XCTAssertEqual(999, newAnchor?.modificationCounter)
    }
    
    func testRecordIssued() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.fetch(identifier: Self.identifier1, completion: self.expectSuccess { storedAlerts in
                XCTAssertEqual(1, storedAlerts.count)
                XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                XCTAssertEqual(Self.historicDate, storedAlerts.first?.issuedDate)
                XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                XCTAssertNil(storedAlerts.first?.retractedDate)
                expect.fulfill()
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordIssuedTwo() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.recordIssued(alert: self.alert1, at: Self.historicDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.identifier1, completion: self.expectSuccess { storedAlerts in
                    self.assertEqual([self.alert1, self.alert1], storedAlerts)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordAcknowledged() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let acknowledgedDate = issuedDate.addingTimeInterval(1)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.recordAcknowledgement(of: Self.identifier1, at: acknowledgedDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.identifier1, completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(1, storedAlerts.count)
                    XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                    XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
                    XCTAssertEqual(acknowledgedDate, storedAlerts.first?.acknowledgedDate)
                    XCTAssertNil(storedAlerts.first?.retractedDate)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordAcknowledgedOfInvalid() {
        let expect = self.expectation(description: #function)
        self.alertStore.recordAcknowledgement(of: Self.identifier1, at: Self.historicDate) {
            switch $0 {
            case .failure: break
            case .success: XCTFail("Unexpected success")
            }
            expect.fulfill()
        }
        wait(for: [expect], timeout: 1)
    }

    func testRecordRetracted() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate.addingTimeInterval(2)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.identifier1, completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(1, storedAlerts.count)
                    XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                    XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
                    XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
                    XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordIssuedExpiresOld() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Date.distantPast, completion: self.expectSuccess {
            self.alertStore.recordIssued(alert: self.alert1, at: Self.historicDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.identifier1, completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(1, storedAlerts.count)
                    XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                    XCTAssertEqual(Self.historicDate, storedAlerts.first?.issuedDate)
                    XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                    XCTAssertNil(storedAlerts.first?.retractedDate)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordAcknowledgedExpiresOld() {
        //  TODO: Not quite sure how to do this yet.
    }
    
    func testRecordRetractedExpiresOld() {
        //  TODO: Not quite sure how to do this yet.
    }

    func testRecordRetractedBeforeDelayShouldDelete() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.delayedAlertDelay - 1.0
        alertStore.recordIssued(alert: delayedAlert, at: issuedDate, completion: self.expectSuccess {
            self.alertStore.recordRetraction(of: Self.delayedAlertIdentifier, at: retractedDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.delayedAlertIdentifier, completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(0, storedAlerts.count)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordRetractedBeforeRepeatDelayShouldDelete() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.repeatingAlertDelay - 1.0
        alertStore.recordIssued(alert: repeatingAlert, at: issuedDate, completion: self.expectSuccess {
            self.alertStore.recordRetraction(of: Self.repeatingAlertIdentifier, at: retractedDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.repeatingAlertIdentifier, completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(0, storedAlerts.count)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordRetractedExactlyAtDelayShouldDelete() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.delayedAlertDelay
        alertStore.recordIssued(alert: delayedAlert, at: issuedDate, completion: self.expectSuccess {
            self.alertStore.recordRetraction(of: Self.delayedAlertIdentifier, at: retractedDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.delayedAlertIdentifier, completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(0, storedAlerts.count)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }

    func testRecordRetractedExactlyAtRepeatDelayShouldDelete() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.repeatingAlertDelay
        alertStore.recordIssued(alert: repeatingAlert, at: issuedDate, completion: self.expectSuccess {
            self.alertStore.recordRetraction(of: Self.repeatingAlertIdentifier, at: retractedDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.repeatingAlertIdentifier, completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(0, storedAlerts.count)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    

    func testRecordRetractedAfterDelayShouldRetract() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.delayedAlertDelay + 1.0
        alertStore.recordIssued(alert: delayedAlert, at: issuedDate, completion: self.expectSuccess {
            self.alertStore.recordRetraction(of: Self.delayedAlertIdentifier, at: retractedDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.delayedAlertIdentifier, completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(1, storedAlerts.count)
                    XCTAssertEqual(Self.delayedAlertIdentifier, storedAlerts.first?.identifier)
                    XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
                    XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
                    XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordRetractedAfterRepeatDelayShouldRetract() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.repeatingAlertDelay + 1.0
        alertStore.recordIssued(alert: repeatingAlert, at: issuedDate, completion: self.expectSuccess {
            self.alertStore.recordRetraction(of: Self.repeatingAlertIdentifier, at: retractedDate, completion: self.expectSuccess {
                self.alertStore.fetch(identifier: Self.repeatingAlertIdentifier, completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(1, storedAlerts.count)
                    XCTAssertEqual(Self.repeatingAlertIdentifier, storedAlerts.first?.identifier)
                    XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
                    XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
                    XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    // These next two tests are admittedly weird corner cases, but theoretically they might be race conditions,
    // and so are allowed
    func testRecordRetractedThenAcknowledged() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate.addingTimeInterval(2)
        let acknowledgedDate = issuedDate.addingTimeInterval(4)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate, completion: self.expectSuccess {
                self.alertStore.recordAcknowledgement(of: Self.identifier1, at: acknowledgedDate, completion: self.expectSuccess {
                    self.alertStore.fetch(identifier: Self.identifier1, completion: self.expectSuccess { storedAlerts in
                        XCTAssertEqual(1, storedAlerts.count)
                        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                        XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
                        XCTAssertEqual(acknowledgedDate, storedAlerts.first?.acknowledgedDate)
                        XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
                        expect.fulfill()
                    })
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testRecordAcknowledgedThenRetracted() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate.addingTimeInterval(2)
        let acknowledgedDate = issuedDate.addingTimeInterval(4)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.recordAcknowledgement(of: Self.identifier1, at: acknowledgedDate, completion: self.expectSuccess {
                self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate, completion: self.expectSuccess {
                    self.alertStore.fetch(identifier: Self.identifier1, completion: self.expectSuccess { storedAlerts in
                        XCTAssertEqual(1, storedAlerts.count)
                        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                        XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
                        XCTAssertEqual(acknowledgedDate, storedAlerts.first?.acknowledgedDate)
                        XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
                        expect.fulfill()
                    })
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testEmptyQuery() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.executeQuery(since: Date.distantPast, limit: 0, completion: self.expectSuccess { _, storedAlerts in
                XCTAssertTrue(storedAlerts.isEmpty)
                expect.fulfill()
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testSimpleQuery() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.executeQuery(since: Date.distantPast, limit: 100, completion: self.expectSuccess { anchor, storedAlerts in
                XCTAssertEqual(1, anchor.modificationCounter)
                XCTAssertEqual(1, storedAlerts.count)
                XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                XCTAssertEqual(Self.historicDate, storedAlerts.first?.issuedDate)
                XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                XCTAssertNil(storedAlerts.first?.retractedDate)
                expect.fulfill()
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testSimpleQueryThenRetraction() {
        let expect = self.expectation(description: #function)
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate.addingTimeInterval(2)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.executeQuery(since: Date.distantPast, limit: 100, completion: self.expectSuccess { anchor, storedAlerts in
                XCTAssertEqual(1, anchor.modificationCounter)
                XCTAssertEqual(1, storedAlerts.count)
                XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                XCTAssertEqual(Self.historicDate, storedAlerts.first?.issuedDate)
                XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                XCTAssertNil(storedAlerts.first?.retractedDate)
                self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate, completion: self.expectSuccess {
                    self.alertStore.executeQuery(since: Date.distantPast, limit: 100, completion: self.expectSuccess { anchor, storedAlerts in
                        XCTAssertEqual(2, anchor.modificationCounter)
                        XCTAssertEqual(1, storedAlerts.count)
                        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                        XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
                        XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
                        XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                        expect.fulfill()
                    })
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testQueryByDate() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            let now = Date()
            self.alertStore.recordIssued(alert: self.alert2, at: now, completion: self.expectSuccess {
                self.alertStore.executeQuery(since: now, limit: 100, completion: self.expectSuccess { anchor, storedAlerts in
                    XCTAssertEqual(2, anchor.modificationCounter)
                    XCTAssertEqual(1, storedAlerts.count)
                    XCTAssertEqual(Self.identifier2, storedAlerts.first?.identifier)
                    XCTAssertEqual(now, storedAlerts.first?.issuedDate)
                    XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                    XCTAssertNil(storedAlerts.first?.retractedDate)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testQueryByDateExcludingFutureDelayed() {
        let expect = self.expectation(description: #function)
        let now = Date()
        alertStore.recordIssued(alert: alert1, at: now, completion: self.expectSuccess {
            self.alertStore.recordIssued(alert: self.delayedAlert, at: now, completion: self.expectSuccess {
                self.alertStore.executeQuery(since: now, limit: 100, completion: self.expectSuccess { anchor, storedAlerts in
                    XCTAssertEqual(1, anchor.modificationCounter)
                    XCTAssertEqual(1, storedAlerts.count)
                    XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                    XCTAssertEqual(now, storedAlerts.first?.issuedDate)
                    XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                    XCTAssertNil(storedAlerts.first?.retractedDate)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testQueryByDateExcludingFutureRepeating() {
        let expect = self.expectation(description: #function)
        let now = Date()
        alertStore.recordIssued(alert: alert1, at: now, completion: self.expectSuccess {
            self.alertStore.recordIssued(alert: self.repeatingAlert, at: now, completion: self.expectSuccess {
                self.alertStore.executeQuery(since: now, limit: 100, completion: self.expectSuccess { anchor, storedAlerts in
                    XCTAssertEqual(1, anchor.modificationCounter)
                    XCTAssertEqual(1, storedAlerts.count)
                    XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                    XCTAssertEqual(now, storedAlerts.first?.issuedDate)
                    XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                    XCTAssertNil(storedAlerts.first?.retractedDate)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }

    func testQueryByDateNotExcludingFutureDelayed() {
        let expect = self.expectation(description: #function)
        let now = Date()
        alertStore.recordIssued(alert: alert1, at: now, completion: self.expectSuccess {
            self.alertStore.recordIssued(alert: self.delayedAlert, at: now, completion: self.expectSuccess {
                self.alertStore.executeQuery(since: now, excludingFutureAlerts: false, limit: 100, completion: self.expectSuccess { anchor, storedAlerts in
                    XCTAssertEqual(2, anchor.modificationCounter)
                    self.assertEqual([self.alert1, self.delayedAlert], storedAlerts)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }

    func testQueryWithLimit() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: self.expectSuccess {
            self.alertStore.recordIssued(alert: self.alert2, at: Date(), completion: self.expectSuccess {
                self.alertStore.executeQuery(since: Date.distantPast, limit: 1, completion: self.expectSuccess { anchor, storedAlerts in
                    XCTAssertEqual(1, anchor.modificationCounter)
                    XCTAssertEqual(1, storedAlerts.count)
                    XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
                    XCTAssertEqual(Self.historicDate, storedAlerts.first?.issuedDate)
                    XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                    XCTAssertNil(storedAlerts.first?.retractedDate)
                    expect.fulfill()
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
        
    func testQueryThenContinue() {
        let expect = self.expectation(description: #function)
        alertStore.recordIssued(alert: alert1, at: Self.historicDate, completion: expectSuccess {
            let now = Date()
            self.alertStore.recordIssued(alert: self.alert2, at: now, completion: self.expectSuccess {
                self.alertStore.executeQuery(since: Date.distantPast, limit: 1, completion: self.expectSuccess { anchor, _ in
                    self.alertStore.continueQuery(from: anchor, limit: 1, completion: self.expectSuccess { anchor, storedAlerts in
                        XCTAssertEqual(2, anchor.modificationCounter)
                        XCTAssertEqual(1, storedAlerts.count)
                        XCTAssertEqual(Self.identifier2, storedAlerts.first?.identifier)
                        XCTAssertEqual(now, storedAlerts.first?.issuedDate)
                        XCTAssertNil(storedAlerts.first?.acknowledgedDate)
                        XCTAssertNil(storedAlerts.first?.retractedDate)
                        expect.fulfill()
                    })
                })
            })
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testAcknowledgeFindsCorrectOne() {
        let expect = self.expectation(description: #function)
        let now = Date()
        fillWith(startDate: Self.historicDate, data: [
            (alert1, true, false),
            (alert2, false, false),
            (alert1, false, false)
        ]) {
            self.alertStore.recordAcknowledgement(of: self.alert1.identifier, at: now, completion: self.expectSuccess {
                self.alertStore.fetch(completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(3, storedAlerts.count)
                    // Last one is last-modified
                    XCTAssertNotNil(storedAlerts.last)
                    if let last = storedAlerts.last {
                        XCTAssertEqual(Self.identifier1, last.identifier)
                        XCTAssertEqual(Self.historicDate + 4, last.issuedDate)
                        XCTAssertEqual(now, last.acknowledgedDate)
                        XCTAssertNil(last.retractedDate)
                    }
                    expect.fulfill()
                })
            })
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testAcknowledgeMultiple() {
        let expect = self.expectation(description: #function)
        let now = Date()
        fillWith(startDate: Self.historicDate, data: [
            (alert1, false, false),
            (alert2, false, false),
            (alert1, false, false)
        ]) {
            self.alertStore.recordAcknowledgement(of: self.alert1.identifier, at: now, completion: self.expectSuccess {
                self.alertStore.fetch(completion: self.expectSuccess { storedAlerts in
                    XCTAssertEqual(3, storedAlerts.count)
                    for alert in storedAlerts where alert.identifier == Self.identifier1 {
                        XCTAssertEqual(now, alert.acknowledgedDate)
                        XCTAssertNil(alert.retractedDate)
                    }
                    expect.fulfill()
                })
            })
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testLookupAllUnacknowledgedEmpty() {
        let expect = self.expectation(description: #function)
        alertStore.lookupAllUnacknowledged(completion: expectSuccess { alerts in
            XCTAssertTrue(alerts.isEmpty)
            expect.fulfill()
        })
        wait(for: [expect], timeout: 1)
    }
    
    func testLookupAllUnacknowledgedOne() {
        let expect = self.expectation(description: #function)
        fillWith(startDate: Self.historicDate, data: [(alert1, false, false)]) {
            self.alertStore.lookupAllUnacknowledged(completion: self.expectSuccess { alerts in
                self.assertEqual([self.alert1], alerts)
                expect.fulfill()
            })
        }
        wait(for: [expect], timeout: 1)
    }
    
    
    func testLookupAllUnacknowledgedOneAcknowledged() {
        let expect = self.expectation(description: #function)
        fillWith(startDate: Self.historicDate, data: [(alert1, true, false)]) {
            self.alertStore.lookupAllUnacknowledged(completion: self.expectSuccess { alerts in
                self.assertEqual([], alerts)
                expect.fulfill()
            })
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testLookupAllUnacknowledgedSomeNot() {
        let expect = self.expectation(description: #function)
        fillWith(startDate: Self.historicDate, data: [
            (alert1, true, false),
            (alert2, false, false),
            (alert1, false, false),
        ]) {
            self.alertStore.lookupAllUnacknowledged(completion: self.expectSuccess { alerts in
                self.assertEqual([self.alert2, self.alert1], alerts)
                expect.fulfill()
            })
        }
        wait(for: [expect], timeout: 1)
    }
    
    func testLookupAllUnacknowledgedSomeRetracted() {
        let expect = self.expectation(description: #function)
        fillWith(startDate: Self.historicDate, data: [
            (alert1, false, true),
            (alert2, false, false),
            (alert1, false, true)
        ]) {
            self.alertStore.lookupAllUnacknowledged(completion: self.expectSuccess { alerts in
                self.assertEqual([self.alert2], alerts)
                expect.fulfill()
            })
        }
        wait(for: [expect], timeout: 1)
    }

    private func fillWith(startDate: Date, data: [(alert: Alert, acknowledged: Bool, retracted: Bool)], _ completion: @escaping () -> Void) {
        let increment = 1.0
        if let value = data.first {
            alertStore.recordIssued(alert: value.alert, at: startDate, completion: self.expectSuccess {
                var next = startDate.addingTimeInterval(increment)
                self.maybeRecordAcknowledge(acknowledged: value.acknowledged, identifier: value.alert.identifier, at: next) {
                    next = next.addingTimeInterval(increment)
                    self.maybeRecordRetracted(retracted: value.retracted, identifier: value.alert.identifier, at: next) {
                        self.fillWith(startDate: startDate.addingTimeInterval(increment).addingTimeInterval(increment), data: data.suffix(data.count - 1), completion)
                    }
                }
            })
        } else {
            completion()
        }
    }
    
    private func maybeRecordAcknowledge(acknowledged: Bool, identifier: Alert.Identifier, at date: Date, _ completion: @escaping () -> Void) {
        if acknowledged {
            self.alertStore.recordAcknowledgement(of: identifier, at: date, completion: self.expectSuccess(completion))
        } else {
            completion()
        }
    }
    
    private func maybeRecordRetracted(retracted: Bool, identifier: Alert.Identifier, at date: Date, _ completion: @escaping () -> Void) {
        if retracted {
            self.alertStore.recordRetraction(of: identifier, at: date, completion: self.expectSuccess(completion))
        } else {
            completion()
        }
    }

    private func assertEqual(_ alerts: [Alert], _ storedAlerts: [StoredAlert], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(alerts.count, storedAlerts.count, file: file, line: line)
        if alerts.count == storedAlerts.count {
            for (index, alert) in alerts.enumerated() {
                XCTAssertEqual(alert.identifier, storedAlerts[index].identifier, file: file, line: line)
            }
        }
    }
    
    private func expectSuccess<T>(file: StaticString = #file, line: UInt = #line, _ completion: @escaping (T) -> Void) -> ((Result<T, Error>) -> Void) {
        return {
            switch $0 {
            case .failure(let error): XCTFail("Unexpected \(error)", file: file, line: line)
            case .success(let value): completion(value)
            }
        }
    }
}

class AlertStoreLogCriticalEventLogTests: XCTestCase {
    var alertStore: AlertStore!
    var outputStream: MockOutputStream!
    var progress: Progress!
    
    override func setUp() {
        super.setUp()

        let alerts = [AlertStore.DatedAlert(date: dateFormatter.date(from: "2100-01-02T03:08:00Z")!, alert: Alert(identifier: Alert.Identifier(managerIdentifier: "m1", alertIdentifier: "a1"), foregroundContent: nil, backgroundContent: nil, trigger: .immediate)),
                      AlertStore.DatedAlert(date: dateFormatter.date(from: "2100-01-02T03:10:00Z")!, alert: Alert(identifier: Alert.Identifier(managerIdentifier: "m2", alertIdentifier: "a2"), foregroundContent: nil, backgroundContent: nil, trigger: .immediate)),
                      AlertStore.DatedAlert(date: dateFormatter.date(from: "2100-01-02T03:04:00Z")!, alert: Alert(identifier: Alert.Identifier(managerIdentifier: "m3", alertIdentifier: "a3"), foregroundContent: nil, backgroundContent: nil, trigger: .immediate)),
                      AlertStore.DatedAlert(date: dateFormatter.date(from: "2100-01-02T03:06:00Z")!, alert: Alert(identifier: Alert.Identifier(managerIdentifier: "m4", alertIdentifier: "a4"), foregroundContent: nil, backgroundContent: nil, trigger: .immediate)),
                      AlertStore.DatedAlert(date: dateFormatter.date(from: "2100-01-02T03:02:00Z")!, alert: Alert(identifier: Alert.Identifier(managerIdentifier: "m5", alertIdentifier: "a5"), foregroundContent: nil, backgroundContent: nil, trigger: .immediate))]

        alertStore = AlertStore()
        XCTAssertNil(alertStore.addAlerts(alerts: alerts))

        outputStream = MockOutputStream()
        progress = Progress()
    }

    override func tearDown() {
        alertStore = nil

        super.tearDown()
    }
    
    func testExportProgressTotalUnitCount() {
        switch alertStore.exportProgressTotalUnitCount(startDate: dateFormatter.date(from: "2100-01-02T03:03:00Z")!,
                                                       endDate: dateFormatter.date(from: "2100-01-02T03:09:00Z")!) {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let progressTotalUnitCount):
            XCTAssertEqual(progressTotalUnitCount, 3 * 1)
        }
    }
    
    func testExportProgressTotalUnitCountEmpty() {
        switch alertStore.exportProgressTotalUnitCount(startDate: dateFormatter.date(from: "2100-01-02T03:00:00Z")!,
                                                       endDate: dateFormatter.date(from: "2100-01-02T03:01:00Z")!) {
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .success(let progressTotalUnitCount):
            XCTAssertEqual(progressTotalUnitCount, 0)
        }
    }

    func testExport() {
        XCTAssertNil(alertStore.export(startDate: dateFormatter.date(from: "2100-01-02T03:03:00Z")!,
                                       endDate: dateFormatter.date(from: "2100-01-02T03:09:00Z")!,
                                       to: outputStream,
                                       progress: progress))
        XCTAssertEqual(outputStream.string, """
[
{"acknowledgedDate":"2100-01-02T03:08:00.000Z","alertIdentifier":"a1","isCritical":false,"issuedDate":"2100-01-02T03:08:00.000Z","managerIdentifier":"m1","modificationCounter":1,"triggerType":0},
{"acknowledgedDate":"2100-01-02T03:04:00.000Z","alertIdentifier":"a3","isCritical":false,"issuedDate":"2100-01-02T03:04:00.000Z","managerIdentifier":"m3","modificationCounter":3,"triggerType":0},
{"acknowledgedDate":"2100-01-02T03:06:00.000Z","alertIdentifier":"a4","isCritical":false,"issuedDate":"2100-01-02T03:06:00.000Z","managerIdentifier":"m4","modificationCounter":4,"triggerType":0}
]
"""
        )
        XCTAssertEqual(progress.completedUnitCount, 3 * 1)
    }

    func testExportEmpty() {
        XCTAssertNil(alertStore.export(startDate: dateFormatter.date(from: "2100-01-02T03:00:00Z")!,
                                       endDate: dateFormatter.date(from: "2100-01-02T03:01:00Z")!,
                                       to: outputStream,
                                       progress: progress))
        XCTAssertEqual(outputStream.string, "[]")
        XCTAssertEqual(progress.completedUnitCount, 0)
    }

    func testExportCancelled() {
        progress.cancel()
        XCTAssertEqual(alertStore.export(startDate: dateFormatter.date(from: "2100-01-02T03:03:00Z")!,
                                         endDate: dateFormatter.date(from: "2100-01-02T03:09:00Z")!,
                                         to: outputStream,
                                         progress: progress) as? CriticalEventLogError, CriticalEventLogError.cancelled)
    }

    private let dateFormatter = ISO8601DateFormatter()
}
