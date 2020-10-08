//
//  StoredAlertTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 8/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import CoreData
import LoopKit
@testable import Loop

class StoredAlertEncodableTests: XCTestCase {
    private var persistentContainer: NSPersistentContainer!
    private var managedObjectContext: NSManagedObjectContext!

    override func setUp() {
        super.setUp()

        let persistentStoreDescription = NSPersistentStoreDescription()
        persistentStoreDescription.type = NSInMemoryStoreType

        persistentContainer = NSPersistentContainer(name: "AlertStore")
        persistentContainer.persistentStoreDescriptions = [persistentStoreDescription]
        persistentContainer.loadPersistentStores { (_, _) in }

        managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        managedObjectContext.automaticallyMergesChangesFromParent = true
        managedObjectContext.persistentStoreCoordinator = persistentContainer.persistentStoreCoordinator
    }

    override func tearDown() {
        managedObjectContext = nil
        persistentContainer = nil

        super.tearDown()
    }

    func testEncodable() throws {
        managedObjectContext.performAndWait {
            let storedAlert = StoredAlert(context: managedObjectContext)
            storedAlert.acknowledgedDate = dateFormatter.date(from: "2020-05-14T22:38:14Z")!
            storedAlert.alertIdentifier = "Alert Identifier 1"
            storedAlert.backgroundContent = "Background Content 1"
            storedAlert.foregroundContent = "Foreground Content 1"
            storedAlert.isCritical = false
            storedAlert.issuedDate = dateFormatter.date(from: "2020-05-14T21:00:12Z")!
            storedAlert.managerIdentifier = "Manager Identifier 1"
            storedAlert.modificationCounter = 123
            storedAlert.retractedDate = dateFormatter.date(from: "2020-05-14T23:34:07Z")!
            storedAlert.sound = "Sound 1"
            storedAlert.triggerInterval = 900
            storedAlert.triggerType = Alert.Trigger.delayed(interval: .minutes(15)).storedType
            try! assertStoredAlertEncodable(storedAlert, encodesJSON: """
{
  "acknowledgedDate" : "2020-05-14T22:38:14Z",
  "alertIdentifier" : "Alert Identifier 1",
  "backgroundContent" : "Background Content 1",
  "foregroundContent" : "Foreground Content 1",
  "isCritical" : false,
  "issuedDate" : "2020-05-14T21:00:12Z",
  "managerIdentifier" : "Manager Identifier 1",
  "modificationCounter" : 123,
  "retractedDate" : "2020-05-14T23:34:07Z",
  "sound" : "Sound 1",
  "triggerInterval" : 900,
  "triggerType" : 1
}
"""
            )
        }
    }

    func testEncodableOptional() throws {
        managedObjectContext.performAndWait {
            let storedAlert = StoredAlert(context: managedObjectContext)
            storedAlert.alertIdentifier = "Alert Identifier 2"
            storedAlert.isCritical = false
            storedAlert.issuedDate = dateFormatter.date(from: "2020-05-14T21:00:12Z")!
            storedAlert.managerIdentifier = "Manager Identifier 2"
            storedAlert.modificationCounter = 234
            storedAlert.triggerType = Alert.Trigger.immediate.storedType
            try! assertStoredAlertEncodable(storedAlert, encodesJSON: """
{
  "alertIdentifier" : "Alert Identifier 2",
  "isCritical" : false,
  "issuedDate" : "2020-05-14T21:00:12Z",
  "managerIdentifier" : "Manager Identifier 2",
  "modificationCounter" : 234,
  "triggerType" : 0
}
"""
            )
        }
    }

    private func assertStoredAlertEncodable(_ original: StoredAlert, encodesJSON string: String) throws {
        let data = try encoder.encode(original)
        XCTAssertEqual(String(data: data, encoding: .utf8), string)
    }

    private let dateFormatter = ISO8601DateFormatter()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
