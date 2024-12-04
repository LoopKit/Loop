//
//  MockGlucoseStore.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopAlgorithm
@testable import Loop

class MockGlucoseStore: GlucoseStoreProtocol {

    func getGlucoseSamples(start: Date?, end: Date?) async throws -> [StoredGlucoseSample] {
        storedGlucose?.filterDateRange(start, end) ?? []
    }

    func addGlucoseSamples(_ samples: [NewGlucoseSample]) async throws -> [StoredGlucoseSample] {
        // Using the dose store error because we don't need to create GlucoseStore errors just for the mock store
        throw DoseStore.DoseStoreError.configurationError
    }

    let dateFormatter = ISO8601DateFormatter.localTimeDate()
    
    var storedGlucose: [StoredGlucoseSample]?
    
    var latestGlucose: GlucoseSampleValue? {
        return storedGlucose?.last
    }
}

extension MockGlucoseStore {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }

}

