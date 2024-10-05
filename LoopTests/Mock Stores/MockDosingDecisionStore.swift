//
//  MockDosingDecisionStore.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import XCTest
@testable import Loop

class MockDosingDecisionStore: DosingDecisionStoreProtocol {
    var delegate: LoopKit.DosingDecisionStoreDelegate?
    
    var exportName: String = "MockDosingDecision"

    func exportProgressTotalUnitCount(startDate: Date, endDate: Date?) -> Result<Int64, Error> {
        return .success(1)
    }
    
    func export(startDate: Date, endDate: Date, to stream: LoopKit.DataOutputStream, progress: Progress) -> Error? {
        return nil
    }
    
    var dosingDecisions: [StoredDosingDecision] = []

    var storeExpectation: XCTestExpectation?

    func storeDosingDecision(_ dosingDecision: StoredDosingDecision) async {
        dosingDecisions.append(dosingDecision)
        storeExpectation?.fulfill()
    }

    func executeDosingDecisionQuery(fromQueryAnchor queryAnchor: LoopKit.DosingDecisionStore.QueryAnchor?, limit: Int, completion: @escaping (LoopKit.DosingDecisionStore.DosingDecisionQueryResult) -> Void) {
        if let queryAnchor {
            completion(.success(queryAnchor, []))
        }
    }
}
