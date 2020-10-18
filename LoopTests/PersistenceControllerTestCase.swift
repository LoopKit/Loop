//
//  PersistenceControllerTestCase.swift
//  LoopTests
//
//  Created by Darin Krauss on 8/26/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import CoreData
@testable import LoopKit

class PersistenceControllerTestCase: XCTestCase {

    var cacheStore: PersistenceController!

    override func setUp() {
        super.setUp()

        cacheStore = PersistenceController(directoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    override func tearDown() {
        cacheStore.tearDown()
        cacheStore = nil

        super.tearDown()
    }

    deinit {
        cacheStore?.tearDown()
    }

}

extension PersistenceController {
    func tearDown() {
        managedObjectContext.performAndWait {
            let coordinator = self.managedObjectContext.persistentStoreCoordinator!
            let store = coordinator.persistentStores.first!
            let url = coordinator.url(for: store)
            try! self.managedObjectContext.persistentStoreCoordinator!.destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
        }
    }
}
