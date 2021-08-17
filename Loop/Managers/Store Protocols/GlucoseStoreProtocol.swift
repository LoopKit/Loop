//
//  GlucoseStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit

protocol GlucoseStoreProtocol: AnyObject {
    
    var latestGlucose: GlucoseSampleValue? { get }
    
    var preferredUnit: HKUnit? { get }
    
    var sampleType: HKSampleType { get }
    
    var delegate: GlucoseStoreDelegate? { get set }
    
    var managedDataInterval: TimeInterval? { get set }
    
    // MARK: HealthKit
    var authorizationRequired: Bool { get }
    
    var sharingDenied: Bool { get }

    func authorize(toShare: Bool, read: Bool, _ completion: @escaping (_ result: HealthKitSampleStoreResult<Bool>) -> Void)
    
    // MARK: Sample Management
    func addGlucoseSamples(_ samples: [NewGlucoseSample], completion: @escaping (_ result: Result<[StoredGlucoseSample], Error>) -> Void)
    
    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (_ result: Result<[StoredGlucoseSample], Error>) -> Void)
    
    func generateDiagnosticReport(_ completion: @escaping (_ report: String) -> Void)
    
    func purgeAllGlucoseSamples(healthKitPredicate: NSPredicate, completion: @escaping (Error?) -> Void)
    
    func executeGlucoseQuery(fromQueryAnchor queryAnchor: GlucoseStore.QueryAnchor?, limit: Int, completion: @escaping (GlucoseStore.GlucoseQueryResult) -> Void)
    
    // MARK: Effect Calculation
    func getRecentMomentumEffect(_ completion: @escaping (_ result: Result<[GlucoseEffect], Error>) -> Void)
    
    func getCounteractionEffects(start: Date, end: Date?, to effects: [GlucoseEffect], _ completion: @escaping (_ effects: Result<[GlucoseEffectVelocity], Error>) -> Void)
    
    func counteractionEffects<Sample: GlucoseSampleValue>(for samples: [Sample], to effects: [GlucoseEffect]) -> [GlucoseEffectVelocity]
}

extension GlucoseStore: GlucoseStoreProtocol { }
