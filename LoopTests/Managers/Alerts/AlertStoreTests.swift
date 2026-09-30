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

    static let defaultTimeout: TimeInterval = 1.5
    static let expiryInterval: TimeInterval = 24 /* hours */ * 60 /* minutes */ * 60 /* seconds */
    static let historicDate = Date(timeIntervalSinceNow: -expiryInterval + TimeInterval.hours(4))  // Within default 24 hour expiration

    static let identifier1 = Alert.Identifier(managerIdentifier: "managerIdentifier1", alertIdentifier: "alertIdentifier1")
    static let backgroundContent = Alert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "OK")
    let alert1 = Alert(identifier: identifier1, foregroundContent: nil, backgroundContent: backgroundContent, trigger: .immediate, sound: nil)
    static let identifier2 = Alert.Identifier(managerIdentifier: "managerIdentifier2", alertIdentifier: "alertIdentifier2")
    static let content = Alert.Content(title: "title", body: "body", acknowledgeActionButtonLabel: "label")
    let alert2 = Alert(identifier: identifier2, foregroundContent: content, backgroundContent: content, trigger: .immediate, interruptionLevel: .critical, sound: .sound(name: "soundName"))
    static let delayedAlertDelay = 30.0 // seconds
    static let delayedAlertIdentifier = Alert.Identifier(managerIdentifier: "managerIdentifier3", alertIdentifier: "alertIdentifier3")
    let delayedAlert = Alert(identifier: delayedAlertIdentifier, foregroundContent: nil, backgroundContent: backgroundContent, trigger: .delayed(interval: delayedAlertDelay), sound: nil)
    static let repeatingAlertDelay = 30.0 // seconds
    static let repeatingAlertIdentifier = Alert.Identifier(managerIdentifier: "managerIdentifier4", alertIdentifier: "alertIdentifier4")
    let repeatingAlert = Alert(identifier: repeatingAlertIdentifier, foregroundContent: nil, backgroundContent: backgroundContent, trigger: .repeating(repeatInterval: repeatingAlertDelay), sound: nil)

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
        alertStore.managedObjectContext.performAndWait {
            let object = StoredAlert(from: alert2, context: alertStore.managedObjectContext, issuedDate: Self.historicDate)
            XCTAssertNil(object.acknowledgedDate)
            XCTAssertNil(object.retractedDate)
            XCTAssertEqual("{\"actions\":[{\"identifier\":\"acknowledge\",\"label\":\"label\",\"style\":0}],\"body\":\"body\",\"title\":\"title\"}", object.backgroundContent)
            XCTAssertEqual("{\"actions\":[{\"identifier\":\"acknowledge\",\"label\":\"label\",\"style\":0}],\"body\":\"body\",\"title\":\"title\"}", object.foregroundContent)
            XCTAssertEqual("managerIdentifier2.alertIdentifier2", object.identifier.value)
            XCTAssertEqual(Self.historicDate, object.issuedDate)
            XCTAssertEqual(1, object.modificationCounter)
            XCTAssertEqual("{\"sound\":{\"name\":\"soundName\"}}", object.sound)
            XCTAssertEqual(Alert.Trigger.immediate, object.trigger)
            XCTAssertEqual(Alert.InterruptionLevel.critical, object.interruptionLevel)
        }
    }

    func testQueryAnchorSerialization() {
        var anchor = AlertStore.QueryAnchor()
        anchor.modificationCounter = 999
        let newAnchor = AlertStore.QueryAnchor(rawValue: anchor.rawValue)
        XCTAssertEqual(anchor, newAnchor)
        XCTAssertEqual(999, newAnchor?.modificationCounter)
    }

    func testRecordIssued() async throws {
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.identifier1)
        XCTAssertEqual(1, storedAlerts.count)
        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
        XCTAssertEqual(Self.historicDate, storedAlerts.first?.issuedDate)
        XCTAssertNil(storedAlerts.first?.acknowledgedDate)
        XCTAssertNil(storedAlerts.first?.retractedDate)
    }

    func testRecordIssuedTwo() async throws {
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        await alertStore.recordIssued(alert: self.alert1, at: Self.historicDate)
        let storedAlerts = try await alertStore.fetch(identifier: Self.identifier1)
        self.assertEqual([self.alert1, self.alert1], storedAlerts)
    }

    func testLookupRecentReturnsMostRecentFirst() async throws {
        let now = Self.historicDate
        await alertStore.recordIssued(alert: alert1, at: now.addingTimeInterval(-120))
        await alertStore.recordIssued(alert: alert2, at: now.addingTimeInterval(-60))
        await alertStore.recordIssued(alert: delayedAlert, at: now)

        let entries = try await alertStore.lookupRecent(limit: 10)
        XCTAssertEqual(3, entries.count)
        XCTAssertEqual([Self.delayedAlertIdentifier, Self.identifier2, Self.identifier1], entries.map { $0.identifier })
        XCTAssertEqual("title", entries[1].title)
        XCTAssertEqual(.critical, entries[1].interruptionLevel)
        XCTAssertEqual(.active, entries[0].status)
    }

    func testLookupRecentRespectsLimitAndPaging() async throws {
        let now = Self.historicDate
        await alertStore.recordIssued(alert: alert1, at: now.addingTimeInterval(-120))
        await alertStore.recordIssued(alert: alert2, at: now.addingTimeInterval(-60))
        await alertStore.recordIssued(alert: delayedAlert, at: now)

        let firstPage = try await alertStore.lookupRecent(limit: 2)
        XCTAssertEqual(2, firstPage.count)
        XCTAssertEqual([Self.delayedAlertIdentifier, Self.identifier2], firstPage.map { $0.identifier })

        let secondPage = try await alertStore.lookupRecent(before: firstPage.last!.issuedDate, limit: 2)
        XCTAssertEqual(1, secondPage.count)
        XCTAssertEqual(Self.identifier1, secondPage.first?.identifier)
    }

    func testRecordAcknowledged() async throws {
        let issuedDate = Self.historicDate
        let acknowledgedDate = issuedDate.addingTimeInterval(1)
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        try await alertStore.recordAcknowledgement(of: Self.identifier1, at: acknowledgedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.identifier1)
        XCTAssertEqual(1, storedAlerts.count)
        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
        XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
        XCTAssertEqual(acknowledgedDate, storedAlerts.first?.acknowledgedDate)
        XCTAssertNil(storedAlerts.first?.retractedDate)
    }

    func testRecordAcknowledgedOfInvalid() async throws {
        do {
            try await self.alertStore.recordAcknowledgement(of: Self.identifier1, at: Self.historicDate)
            XCTFail("Unexpected success")
        } catch {
            return
        }
    }

    func testRecordRetracted() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate.addingTimeInterval(2)
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        try await self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.identifier1)
        XCTAssertEqual(1, storedAlerts.count)
        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
        XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
        XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
        XCTAssertNil(storedAlerts.first?.acknowledgedDate)
    }

    func testRecordIssuedExpiresOld() async throws {
        await alertStore.recordIssued(alert: alert1, at: Date.distantPast)
        await self.alertStore.recordIssued(alert: self.alert1, at: Self.historicDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.identifier1)
        XCTAssertEqual(1, storedAlerts.count)
        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
        XCTAssertEqual(Self.historicDate, storedAlerts.first?.issuedDate)
        XCTAssertNil(storedAlerts.first?.acknowledgedDate)
        XCTAssertNil(storedAlerts.first?.retractedDate)
    }

    func testRecordAcknowledgedExpiresOld() {
        //  TODO: Not quite sure how to do this yet.
    }

    func testRecordRetractedExpiresOld() {
        //  TODO: Not quite sure how to do this yet.
    }

    func testRecordRetractedBeforeDelayShouldDelete() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.delayedAlertDelay - 1.0
        await alertStore.recordIssued(alert: delayedAlert, at: issuedDate)
        try await self.alertStore.recordRetraction(of: Self.delayedAlertIdentifier, at: retractedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.delayedAlertIdentifier)
        XCTAssertEqual(0, storedAlerts.count)
    }

    func testRecordRetractedBeforeRepeatDelayShouldDelete() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.repeatingAlertDelay - 1.0
        await alertStore.recordIssued(alert: repeatingAlert, at: issuedDate)
        try await self.alertStore.recordRetraction(of: Self.repeatingAlertIdentifier, at: retractedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.repeatingAlertIdentifier)
        XCTAssertEqual(0, storedAlerts.count)
    }

    func testRecordRetractedExactlyAtDelayShouldDelete() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.delayedAlertDelay
        await alertStore.recordIssued(alert: delayedAlert, at: issuedDate)
        try await self.alertStore.recordRetraction(of: Self.delayedAlertIdentifier, at: retractedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.delayedAlertIdentifier)
        XCTAssertEqual(0, storedAlerts.count)
    }

    func testRecordRetractedExactlyAtRepeatDelayShouldDelete() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.repeatingAlertDelay
        await alertStore.recordIssued(alert: repeatingAlert, at: issuedDate)
        try await self.alertStore.recordRetraction(of: Self.repeatingAlertIdentifier, at: retractedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.repeatingAlertIdentifier)
        XCTAssertEqual(0, storedAlerts.count)
    }

    func testRecordRetractedAfterDelayShouldRetract() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.delayedAlertDelay + 1.0
        await alertStore.recordIssued(alert: delayedAlert, at: issuedDate)
        try await self.alertStore.recordRetraction(of: Self.delayedAlertIdentifier, at: retractedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.delayedAlertIdentifier)
        XCTAssertEqual(1, storedAlerts.count)
        XCTAssertEqual(Self.delayedAlertIdentifier, storedAlerts.first?.identifier)
        XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
        XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
        XCTAssertNil(storedAlerts.first?.acknowledgedDate)
    }

    func testRecordRetractedAfterRepeatDelayShouldRetract() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate + Self.repeatingAlertDelay + 1.0
        await alertStore.recordIssued(alert: repeatingAlert, at: issuedDate)
        try await self.alertStore.recordRetraction(of: Self.repeatingAlertIdentifier, at: retractedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.repeatingAlertIdentifier)
        XCTAssertEqual(1, storedAlerts.count)
        XCTAssertEqual(Self.repeatingAlertIdentifier, storedAlerts.first?.identifier)
        XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
        XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
        XCTAssertNil(storedAlerts.first?.acknowledgedDate)
    }

    // These next two tests are admittedly weird corner cases, but theoretically they might be race conditions,
    // and so are allowed
    func testRecordRetractedThenAcknowledged() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate.addingTimeInterval(2)
        let acknowledgedDate = issuedDate.addingTimeInterval(4)
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        try await self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate)
        try await self.alertStore.recordAcknowledgement(of: Self.identifier1, at: acknowledgedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.identifier1)
        XCTAssertEqual(1, storedAlerts.count)
        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
        XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
        XCTAssertEqual(acknowledgedDate, storedAlerts.first?.acknowledgedDate)
        XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
    }

    func testRecordAcknowledgedThenRetracted() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate.addingTimeInterval(2)
        let acknowledgedDate = issuedDate.addingTimeInterval(4)
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        try await self.alertStore.recordAcknowledgement(of: Self.identifier1, at: acknowledgedDate)
        try await self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.identifier1)
        XCTAssertEqual(1, storedAlerts.count)
        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
        XCTAssertEqual(issuedDate, storedAlerts.first?.issuedDate)
        XCTAssertEqual(acknowledgedDate, storedAlerts.first?.acknowledgedDate)
        XCTAssertEqual(retractedDate, storedAlerts.first?.retractedDate)
    }

    func testRecordRetractedAlert() async throws {
        let alertDate = Self.historicDate
        try await alertStore.recordRetractedAlert(alert1, at: alertDate)
        let storedAlerts = try await self.alertStore.fetch(identifier: Self.identifier1)
        XCTAssertEqual(1, storedAlerts.count)
        XCTAssertEqual(Self.identifier1, storedAlerts.first?.identifier)
        XCTAssertEqual(alertDate, storedAlerts.first?.issuedDate)
        XCTAssertNil(storedAlerts.first?.acknowledgedDate)
        XCTAssertEqual(alertDate, storedAlerts.first?.retractedDate)
    }

    func testEmptyQuery() async throws {
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        let (_, objects) = try await self.alertStore.executeQuery(since: Date.distantPast, limit: 0)
        XCTAssertTrue(objects.isEmpty)
    }

    func testSimpleQuery() async throws {
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        let (anchor, objects) = try await self.alertStore.executeQuery(since: Date.distantPast, limit: 100)
        XCTAssertEqual(1, anchor.modificationCounter)
        XCTAssertEqual(1, objects.count)
        XCTAssertEqual(Self.identifier1, objects.first?.identifier)
        XCTAssertEqual(Self.historicDate, objects.first?.issuedDate)
        XCTAssertNil(objects.first?.acknowledgedDate)
        XCTAssertNil(objects.first?.retractedDate)
    }

    func testSimpleQueryThenRetraction() async throws {
        let issuedDate = Self.historicDate
        let retractedDate = issuedDate.addingTimeInterval(2)
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        let (anchor, objects) = try await self.alertStore.executeQuery(since: Date.distantPast, limit: 100)
        XCTAssertEqual(1, anchor.modificationCounter)
        XCTAssertEqual(1, objects.count)
        XCTAssertEqual(Self.identifier1, objects.first?.identifier)
        XCTAssertEqual(Self.historicDate, objects.first?.issuedDate)
        XCTAssertNil(objects.first?.acknowledgedDate)
        XCTAssertNil(objects.first?.retractedDate)
        try await self.alertStore.recordRetraction(of: Self.identifier1, at: retractedDate)
        let (anchor2, objects2) = try await self.alertStore.executeQuery(since: Date.distantPast, limit: 100)
        XCTAssertEqual(2, anchor2.modificationCounter)
        XCTAssertEqual(1, objects2.count)
        XCTAssertEqual(Self.identifier1, objects2.first?.identifier)
        XCTAssertEqual(issuedDate, objects2.first?.issuedDate)
        XCTAssertEqual(retractedDate, objects2.first?.retractedDate)
        XCTAssertNil(objects2.first?.acknowledgedDate)
    }

    func testQueryByDate() async throws {
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        let now = Date()
        await self.alertStore.recordIssued(alert: self.alert2, at: now)
        let (anchor, objects) = try await self.alertStore.executeQuery(since: now, limit: 100)
        XCTAssertEqual(2, anchor.modificationCounter)
        XCTAssertEqual(1, objects.count)
        XCTAssertEqual(Self.identifier2, objects.first?.identifier)
        XCTAssertEqual(now, objects.first?.issuedDate)
        XCTAssertNil(objects.first?.acknowledgedDate)
        XCTAssertNil(objects.first?.retractedDate)
    }

    func testQueryByDateExcludingFutureDelayed() async throws {
        let now = Date()
        await alertStore.recordIssued(alert: alert1, at: now)
        await self.alertStore.recordIssued(alert: self.delayedAlert, at: now)
        let (anchor, objects) = try await self.alertStore.executeQuery(since: now, limit: 100)
        XCTAssertEqual(1, anchor.modificationCounter)
        XCTAssertEqual(1, objects.count)
        XCTAssertEqual(Self.identifier1, objects.first?.identifier)
        XCTAssertEqual(now, objects.first?.issuedDate)
        XCTAssertNil(objects.first?.acknowledgedDate)
        XCTAssertNil(objects.first?.retractedDate)
    }

    func testQueryByDateExcludingFutureRepeating() async throws {
        let now = Date()
        await alertStore.recordIssued(alert: alert1, at: now)
        await self.alertStore.recordIssued(alert: self.repeatingAlert, at: now)
        let (anchor, objects) = try await self.alertStore.executeQuery(since: now, limit: 100)
        XCTAssertEqual(1, anchor.modificationCounter)
        XCTAssertEqual(1, objects.count)
        XCTAssertEqual(Self.identifier1, objects.first?.identifier)
        XCTAssertEqual(now, objects.first?.issuedDate)
        XCTAssertNil(objects.first?.acknowledgedDate)
        XCTAssertNil(objects.first?.retractedDate)
    }

    func testQueryByDateNotExcludingFutureDelayed() async throws {
        let now = Date()
        await alertStore.recordIssued(alert: alert1, at: now)
        await self.alertStore.recordIssued(alert: self.delayedAlert, at: now)
        let (anchor, objects) = try await self.alertStore.executeQuery(since: now, excludingFutureAlerts: false, limit: 100)
        XCTAssertEqual(2, anchor.modificationCounter)
        self.assertEqual([self.alert1, self.delayedAlert], objects)
    }

    func testQueryWithLimit() async throws {
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        await self.alertStore.recordIssued(alert: self.alert2, at: Date())
        let (anchor, objects) = try await self.alertStore.executeQuery(since: Date.distantPast, limit: 1)
        XCTAssertEqual(1, anchor.modificationCounter)
        XCTAssertEqual(1, objects.count)
        XCTAssertEqual(Self.identifier1, objects.first?.identifier)
        XCTAssertEqual(Self.historicDate, objects.first?.issuedDate)
        XCTAssertNil(objects.first?.acknowledgedDate)
        XCTAssertNil(objects.first?.retractedDate)
    }

    func testQueryThenContinue() async throws {
        await alertStore.recordIssued(alert: alert1, at: Self.historicDate)
        let now = Date()
        await self.alertStore.recordIssued(alert: self.alert2, at: now)
        let (anchor, _) = try await self.alertStore.executeQuery(since: Date.distantPast, limit: 1)
        let (anchor2, objects) = try await self.alertStore.executeQuery(fromQueryAnchor: anchor, since: Date.distantPast, limit: 1)
        XCTAssertEqual(2, anchor2.modificationCounter)
        XCTAssertEqual(1, objects.count)
        XCTAssertEqual(Self.identifier2, objects.first?.identifier)
        XCTAssertEqual(now, objects.first?.issuedDate)
        XCTAssertNil(objects.first?.acknowledgedDate)
        XCTAssertNil(objects.first?.retractedDate)
    }

    func testAcknowledgeFindsCorrectOne() async throws {
        let now = Date()
        await fillWith(startDate: Self.historicDate, data: [
            (alert1, true, false),
            (alert2, false, false),
            (alert1, false, false)
        ])
        try await self.alertStore.recordAcknowledgement(of: self.alert1.identifier, at: now)
        let storedAlerts = try await self.alertStore.fetch()
        XCTAssertEqual(3, storedAlerts.count)
        // Last one is last-modified
        XCTAssertNotNil(storedAlerts.last)
        if let last = storedAlerts.last {
            XCTAssertEqual(Self.identifier1, last.identifier)
            XCTAssertEqual(Self.historicDate + 4, last.issuedDate)
            XCTAssertEqual(now, last.acknowledgedDate)
            XCTAssertNil(last.retractedDate)
        }
    }

    func testAcknowledgeMultiple() async throws {
        let now = Date()
        await fillWith(startDate: Self.historicDate, data: [
            (alert1, false, false),
            (alert2, false, false),
            (alert1, false, false)
        ])
        try await self.alertStore.recordAcknowledgement(of: self.alert1.identifier, at: now)
        let storedAlerts = try await self.alertStore.fetch()
        XCTAssertEqual(3, storedAlerts.count)
        for alert in storedAlerts where alert.identifier == Self.identifier1 {
            XCTAssertEqual(now, alert.acknowledgedDate)
            XCTAssertNil(alert.retractedDate)
        }
    }

    func testLookupAllUnacknowledgedUnretractedEmpty() async throws {
        let alerts = try await alertStore.lookupAllUnacknowledgedUnretracted()
        XCTAssertTrue(alerts.isEmpty)
    }

    func testLookupAllUnacknowledgedUnretractedOne() async throws {
        await fillWith(startDate: Self.historicDate, data: [(alert1, false, false)])
        let alerts = try await self.alertStore.lookupAllUnacknowledgedUnretracted()
        self.assertEqual([self.alert1], alerts)
    }

    func testLookupAllUnacknowledgedUnretractedOneAcknowledged() async throws {
        await fillWith(startDate: Self.historicDate, data: [(alert1, true, false)])
        let alerts = try await self.alertStore.lookupAllUnacknowledgedUnretracted()
        self.assertEqual([], alerts)
    }

    func testLookupAllUnacknowledgedUnretractedSomeNot() async throws {
        await fillWith(startDate: Self.historicDate, data: [
            (alert1, true, false),
            (alert2, false, false),
            (alert1, false, false),
        ])
        let alerts = try await self.alertStore.lookupAllUnacknowledgedUnretracted()
        self.assertEqual([self.alert2, self.alert1], alerts)
    }

    func testLookupAllUnacknowledgedUnretractedSomeRetracted() async throws {
        await fillWith(startDate: Self.historicDate, data: [
            (alert1, false, true),
            (alert2, false, false),
            (alert1, false, true)
        ])
        let alerts = try await self.alertStore.lookupAllUnacknowledgedUnretracted()
        self.assertEqual([self.alert2], alerts)
    }

    func testLookupAllUnretractedEmpty() async throws {
        let alerts = try await alertStore.lookupAllUnretracted()
        XCTAssertTrue(alerts.isEmpty)
    }

    func testLookupAllUnretractedOne() async throws {
        await fillWith(startDate: Self.historicDate, data: [(alert1, false, false)])
        let alerts = try await self.alertStore.lookupAllUnretracted()
        self.assertEqual([self.alert1], alerts)
    }

    func testLookupAllUnretractedOneAcknowledged() async throws {
        await fillWith(startDate: Self.historicDate, data: [(alert1, true, false)])
        let alerts = try await self.alertStore.lookupAllUnretracted()
        self.assertEqual([self.alert1], alerts)
    }

    func testLookupAllUnretractedSomeAcknowledgedSomeNot() async throws {
        await fillWith(startDate: Self.historicDate, data: [
            (alert1, true, false),
            (alert2, false, false),
            (alert1, false, false),
        ])
        let alerts = try await self.alertStore.lookupAllUnretracted()
        self.assertEqual([self.alert1, self.alert2, self.alert1], alerts)
    }

    func testLookupAllUnretractedSomeRetracted() async throws {
        await fillWith(startDate: Self.historicDate, data: [
            (alert1, false, true),
            (alert2, false, false),
            (alert1, false, true)
        ])
        let alerts = try await self.alertStore.lookupAllUnretracted()
        self.assertEqual([self.alert2], alerts)
    }

    func testLookupAllAcknowledgedUnretractedRepeatingAlertsAll() async throws {
        await fillWith(startDate: Self.historicDate, data: [
            (repeatingAlert, true, false),
            (repeatingAlert, true, false)
        ])
        let alerts = try await self.alertStore.lookupAllAcknowledgedUnretractedRepeatingAlerts()
        XCTAssertEqual(alerts.count, 2)
        self.assertEqual([self.repeatingAlert, self.repeatingAlert], alerts)
    }

    func testLookupAllAcknowledgedUnretractedRepeatingAlertsEmpty() async throws {
        let alerts = try await alertStore.lookupAllAcknowledgedUnretractedRepeatingAlerts()
        XCTAssertTrue(alerts.isEmpty)
    }

    func testLookupAllAcknowledgedUnretractedRepeatingAlertsSome() async throws {
        await fillWith(startDate: Self.historicDate, data: [
            (repeatingAlert, true, true),
            (repeatingAlert, true, false),
            (alert1, true, false)
        ])
        let alerts = try await self.alertStore.lookupAllAcknowledgedUnretractedRepeatingAlerts()
        XCTAssertEqual(alerts.count, 1)
        self.assertEqual([self.repeatingAlert], alerts)
    }

    func testLookUpAllMatching() async throws {
        await fillWith(startDate: Self.historicDate, data: [
            (alert1, true, false),
            (repeatingAlert, true, false)
        ])
        let alerts = try await self.alertStore.lookupAllMatching(identifier: AlertStoreTests.repeatingAlertIdentifier)
        XCTAssertEqual(alerts.count, 1)
        self.assertEqual([self.repeatingAlert], alerts)
    }

    private func fillWith(startDate: Date, data: [(alert: Alert, acknowledged: Bool, retracted: Bool)]) async {
        let increment = 1.0
        for (index, value) in data.enumerated() {
            let issuedDate = startDate.addingTimeInterval(Double(index) * increment * 2)
            await alertStore.recordIssued(alert: value.alert, at: issuedDate)

            if value.acknowledged {
                let acknowledgedDate = issuedDate.addingTimeInterval(increment)
                try? await self.alertStore.recordAcknowledgement(of: value.alert.identifier, at: acknowledgedDate)
            }

            if value.retracted {
                let retractedDate = issuedDate.addingTimeInterval(increment)
                try? await self.alertStore.recordRetraction(of: value.alert.identifier, at: retractedDate)
            }
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

    private func assertEqual(_ alerts: [Alert], _ syncAlertObjects: [SyncAlertObject], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(alerts.count, syncAlertObjects.count, file: file, line: line)
        if alerts.count == syncAlertObjects.count {
            for (index, alert) in alerts.enumerated() {
                XCTAssertEqual(alert.identifier, syncAlertObjects[index].identifier, file: file, line: line)
            }
        }
    }
}
