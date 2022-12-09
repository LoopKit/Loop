//
//  DoseStoreProtocol.swift
//  Loop
//
//  Created by Anna Quinlan on 8/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit

protocol DoseStoreProtocol: AnyObject {
    // MARK: settings
    var basalProfile: LoopKit.BasalRateSchedule? { get set }

    var insulinModelProvider: InsulinModelProvider { get set }
    
    var longestEffectDuration: TimeInterval { get set }

    var insulinSensitivitySchedule: LoopKit.InsulinSensitivitySchedule? { get set }
    
    var basalProfileApplyingOverrideHistory: BasalRateSchedule? { get }
    
    // MARK: authorization
    var authorizationRequired: Bool { get }
    
    var sharingDenied: Bool { get }
    
    // MARK: store information
    var lastReservoirValue: LoopKit.ReservoirValue? { get }
    
    var lastAddedPumpData: Date { get }
    
    var sampleType: HKSampleType { get }
    
    var delegate: DoseStoreDelegate? { get set }
    
    var device: HKDevice? { get set }
    
    var pumpRecordsBasalProfileStartEvents: Bool { get set }
    
    var pumpEventQueryAfterDate: Date { get }
    
    // MARK: dose management
    func addPumpEvents(_ events: [NewPumpEvent], lastReconciliation: Date?, completion: @escaping (_ error: DoseStore.DoseStoreError?) -> Void)
    
    func addReservoirValue(_ unitVolume: Double, at date: Date, completion: @escaping (_ value: ReservoirValue?, _ previousValue: ReservoirValue?, _ areStoredValuesContinuous: Bool, _ error: DoseStore.DoseStoreError?) -> Void)
    
    func getNormalizedDoseEntries(start: Date, end: Date?, completion: @escaping (_ result: DoseStoreResult<[DoseEntry]>) -> Void)
    
    func executePumpEventQuery(fromQueryAnchor queryAnchor: DoseStore.QueryAnchor?, limit: Int, completion: @escaping (DoseStore.PumpEventQueryResult) -> Void)
    
    func generateDiagnosticReport(_ completion: @escaping (_ report: String) -> Void)
    
    func addDoses(_ doses: [DoseEntry], from device: HKDevice?, completion: @escaping (_ error: Error?) -> Void)
    
    // MARK: IOB and insulin effect
    func insulinOnBoard(at date: Date, completion: @escaping (_ result: DoseStoreResult<InsulinValue>) -> Void)
    
    func getGlucoseEffects(start: Date, end: Date?, basalDosingEnd: Date?, completion: @escaping (_ result: DoseStoreResult<[GlucoseEffect]>) -> Void)
    
    func getInsulinOnBoardValues(start: Date, end: Date? , basalDosingEnd: Date?, completion: @escaping (_ result: DoseStoreResult<[InsulinValue]>) -> Void)
    
    func getTotalUnitsDelivered(since startDate: Date, completion: @escaping (_ result: DoseStoreResult<InsulinValue>) -> Void)
    
}

extension DoseStore: DoseStoreProtocol { }
