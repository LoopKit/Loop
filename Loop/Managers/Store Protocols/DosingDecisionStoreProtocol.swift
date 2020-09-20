//
//  DosingDecisionStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

protocol DosingDecisionStoreProtocol: AnyObject {
    func storeDosingDecision(_ dosingDecision: StoredDosingDecision, completion: @escaping () -> Void)
}

extension DosingDecisionStore: DosingDecisionStoreProtocol { }
