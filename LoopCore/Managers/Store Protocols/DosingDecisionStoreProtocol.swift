//
//  DosingDecisionStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import LoopKit

public struct LightDosingDecision: DosingDecision {
    public let automaticDoseRecommendation: AutomaticDoseRecommendation?
    public let carbEntry: StoredCarbEntry?
    public let id: UUID
    public let manualBolusRecommendation: ManualBolusRecommendationWithDate?
    public let manualBolusRequested: Double?
    public let scheduleOverride: TemporaryScheduleOverride?
    public let syncIdentifier: UUID
}

public protocol DosingDecisionStoreProtocol: CriticalEventLog {
    var delegate: DosingDecisionStoreDelegate? { get set }

    func storeDosingDecision(_ dosingDecision: StoredDosingDecision) async

    func executeDosingDecisionQuery(fromQueryAnchor queryAnchor: DosingDecisionStore.QueryAnchor?, limit: Int, completion: @escaping (DosingDecisionStore.DosingDecisionQueryResult) -> Void)
    
    func findDosingDecisionsById<D: DosingDecision>(_ id: UUID) async throws -> D?
    func findDosingDecisionsByIds<D: DosingDecision>(_ ids: [UUID]) async throws -> [D]
}

extension DosingDecisionStore: DosingDecisionStoreProtocol { }
