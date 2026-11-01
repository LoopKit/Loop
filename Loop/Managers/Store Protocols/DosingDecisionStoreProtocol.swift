//
//  DosingDecisionStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

struct LightDosingDecision: DosingDecision {
    let automaticDoseRecommendation: AutomaticDoseRecommendation?
    let carbEntry: StoredCarbEntry?
    let id: UUID
    let manualBolusRecommendation: ManualBolusRecommendationWithDate?
    let manualBolusRequested: Double?
    let scheduleOverride: TemporaryScheduleOverride?
    let syncIdentifier: UUID
}

protocol DosingDecisionStoreProtocol: CriticalEventLog {
    var delegate: DosingDecisionStoreDelegate? { get set }

    func storeDosingDecision(_ dosingDecision: StoredDosingDecision) async

    func executeDosingDecisionQuery(fromQueryAnchor queryAnchor: DosingDecisionStore.QueryAnchor?, limit: Int, completion: @escaping (DosingDecisionStore.DosingDecisionQueryResult) -> Void)
    
    func findDosingDecisionsById<D: DosingDecision>(_ id: UUID) async throws -> D?
    func findDosingDecisionsByIds<D: DosingDecision>(_ ids: [UUID]) async throws -> [D]
}

extension DosingDecisionStore: DosingDecisionStoreProtocol { }
