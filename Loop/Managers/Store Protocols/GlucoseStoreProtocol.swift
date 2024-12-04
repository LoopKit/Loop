//
//  GlucoseStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopAlgorithm

protocol GlucoseStoreProtocol: AnyObject {
    var latestGlucose: GlucoseSampleValue? { get }
    func getGlucoseSamples(start: Date?, end: Date?) async throws -> [StoredGlucoseSample]
    func addGlucoseSamples(_ samples: [NewGlucoseSample]) async throws -> [StoredGlucoseSample]
}

extension GlucoseStore: GlucoseStoreProtocol { }
