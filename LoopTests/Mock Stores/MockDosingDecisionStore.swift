//
//  MockDosingDecisionStore.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
@testable import Loop

class MockDosingDecisionStore: DosingDecisionStoreProtocol {
    func storeDosingDecision(_ dosingDecision: StoredDosingDecision, completion: @escaping () -> Void) {
        completion()
    }
}
