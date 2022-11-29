//
//  HKHealthStoreMock.swift
//  LoopTests
//
//  Created by Anna Quinlan on 11/28/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import HealthKit
import Foundation
import LoopKit


class HKHealthStoreMock: HKHealthStore {
    var saveError: Error?
    var deleteError: Error?
    var queryResults: (samples: [HKSample]?, error: Error?)?
    var lastQuery: HKQuery?
    var authorizationStatus: HKAuthorizationStatus?

    private var saveHandler: ((_ objects: [HKObject], _ success: Bool, _ error: Error?) -> Void)?
    private var deleteObjectsHandler: ((_ objectType: HKObjectType, _ predicate: NSPredicate, _ success: Bool, _ count: Int, _ error: Error?) -> Void)?

    let queue = DispatchQueue(label: "HKHealthStoreMock")

    override func save(_ object: HKObject, withCompletion completion: @escaping (Bool, Error?) -> Void) {
        queue.async {
            self.saveHandler?([object], self.saveError == nil, self.saveError)
            completion(self.saveError == nil, self.saveError)
        }
    }

    override func save(_ objects: [HKObject], withCompletion completion: @escaping (Bool, Error?) -> Void) {
        queue.async {
            self.saveHandler?(objects, self.saveError == nil, self.saveError)
            completion(self.saveError == nil, self.saveError)
        }
    }

    override func delete(_ objects: [HKObject], withCompletion completion: @escaping (Bool, Error?) -> Void) {
        queue.async {
            completion(self.deleteError == nil, self.deleteError)
        }
    }

    override func deleteObjects(of objectType: HKObjectType, predicate: NSPredicate, withCompletion completion: @escaping (Bool, Int, Error?) -> Void) {
        queue.async {
            self.deleteObjectsHandler?(objectType, predicate, self.deleteError == nil, 0, self.deleteError)
            completion(self.deleteError == nil, 0, self.deleteError)
        }
    }

    func setSaveHandler(_ saveHandler: ((_ objects: [HKObject], _ success: Bool, _ error: Error?) -> Void)?) {
        queue.sync {
            self.saveHandler = saveHandler
        }
    }
    
    override func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?, completion: @escaping (Bool, Error?) -> Void) {
        DispatchQueue.main.async {
            completion(true, nil)
        }
    }
    
    override func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        return authorizationStatus ?? .notDetermined
    }

    func setDeletedObjectsHandler(_ deleteObjectsHandler: ((_ objectType: HKObjectType, _ predicate: NSPredicate, _ success: Bool, _ count: Int, _ error: Error?) -> Void)?) {
        queue.sync {
            self.deleteObjectsHandler = deleteObjectsHandler
        }
    }
}

extension HKHealthStoreMock {

    override func execute(_ query: HKQuery) {
        self.lastQuery = query
    }
}

