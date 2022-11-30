//
//  CarbStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit

protocol CarbStoreProtocol: AnyObject {
    
    var sampleType: HKSampleType { get }
    
    var preferredUnit: HKUnit! { get }
    
    var delegate: CarbStoreDelegate? { get set }
    
    // MARK: Settings
    var carbRatioSchedule: CarbRatioSchedule? { get set }
    
    var insulinSensitivitySchedule: InsulinSensitivitySchedule? { get set }
    
    var insulinSensitivityScheduleApplyingOverrideHistory: InsulinSensitivitySchedule? { get }
    
    var carbRatioScheduleApplyingOverrideHistory: CarbRatioSchedule? { get }
    
    var maximumAbsorptionTimeInterval: TimeInterval { get }
    
    var delta: TimeInterval { get }
    
    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes { get }
    
    // MARK: HealthKit
    var authorizationRequired: Bool { get }
    
    var sharingDenied: Bool { get }
    
    func authorize(toShare: Bool, read: Bool, _ completion: @escaping (_ result: HealthKitSampleStoreResult<Bool>) -> Void)
    
    // MARK: Data Management
    func replaceCarbEntry(_ oldEntry: StoredCarbEntry, withEntry newEntry: NewCarbEntry, completion: @escaping (_ result: CarbStoreResult<StoredCarbEntry>) -> Void)
    
    func addCarbEntry(_ entry: NewCarbEntry, completion: @escaping (_ result: CarbStoreResult<StoredCarbEntry>) -> Void)
    
    func getCarbStatus(start: Date, end: Date?, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (_ result: CarbStoreResult<[CarbStatus<StoredCarbEntry>]>) -> Void)
    
    func generateDiagnosticReport(_ completion: @escaping (_ report: String) -> Void)
    
    // MARK: COB & Effect Generation
    func getGlucoseEffects(start: Date, end: Date?, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping(_ result: CarbStoreResult<(entries: [StoredCarbEntry], effects: [GlucoseEffect])>) -> Void)
    
    func glucoseEffects<Sample: CarbEntry>(of samples: [Sample], startingAt start: Date, endingAt end: Date?, effectVelocities: [GlucoseEffectVelocity]?) throws -> [GlucoseEffect]
    
    func getCarbsOnBoardValues(start: Date, end: Date?, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (_ result: CarbStoreResult<[CarbValue]>) -> Void)
    
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (_ result: CarbStoreResult<CarbValue>) -> Void)
    
    func getTotalCarbs(since start: Date, completion: @escaping (_ result: CarbStoreResult<CarbValue>) -> Void)
    
    func deleteCarbEntry(_ entry: StoredCarbEntry, completion: @escaping (_ result: CarbStoreResult<Bool>) -> Void)
}

extension CarbStore: CarbStoreProtocol { }
