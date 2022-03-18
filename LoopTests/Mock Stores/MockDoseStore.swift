//
//  MockDoseStore.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
@testable import Loop

class MockDoseStore: DoseStoreProtocol {
    
    init(for test: DataManagerTestType = .flatAndStable) {
        self.testType = test // The store returns different effect values based on the test type
        self.pumpEventQueryAfterDate = MockDoseStore.currentDate(for: test)
        self.lastAddedPumpData = MockDoseStore.currentDate(for: test)
    }
    
    static let dateFormatter = ISO8601DateFormatter.localTimeDate()
    
    var testType: DataManagerTestType
    
    var basalProfileApplyingOverrideHistory: BasalRateSchedule?
    
    var delegate: DoseStoreDelegate?
    
    var device: HKDevice?
    
    var pumpRecordsBasalProfileStartEvents: Bool = false
    
    var pumpEventQueryAfterDate: Date
    
    var basalProfile: BasalRateSchedule?
    
    // Default to the adult exponential insulin model
    var insulinModelProvider: InsulinModelProvider = StaticInsulinModelProvider(ExponentialInsulinModelPreset.rapidActingAdult)

    var longestEffectDuration: TimeInterval = ExponentialInsulinModelPreset.rapidActingAdult.actionDuration

    var insulinSensitivitySchedule: InsulinSensitivitySchedule?
    
    var sampleType: HKSampleType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery)!
    
    var authorizationRequired: Bool = false
    
    var sharingDenied: Bool = false
    
    var lastReservoirValue: ReservoirValue?
    
    var lastAddedPumpData: Date
    
    func addPumpEvents(_ events: [NewPumpEvent], lastReconciliation: Date?, completion: @escaping (DoseStore.DoseStoreError?) -> Void) {
        completion(nil)
    }
    
    func addReservoirValue(_ unitVolume: Double, at date: Date, completion: @escaping (ReservoirValue?, ReservoirValue?, Bool, DoseStore.DoseStoreError?) -> Void) {
        completion(nil, nil, false, nil)
    }
    
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        completion(.failure(.configurationError))
    }
    
    func generateDiagnosticReport(_ completion: @escaping (String) -> Void) {
        completion("")
    }
    
    func addDoses(_ doses: [DoseEntry], from device: HKDevice?, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    func resetPumpData(completion: ((DoseStore.DoseStoreError?) -> Void)?) {
        completion?(.configurationError)
    }
    
    func getInsulinOnBoardValues(start: Date, end: Date?, basalDosingEnd: Date?, completion: @escaping (DoseStoreResult<[InsulinValue]>) -> Void) {
        completion(.failure(.configurationError))
    }
    
    func getNormalizedDoseEntries(start: Date, end: Date?, completion: @escaping (DoseStoreResult<[DoseEntry]>) -> Void) {
        completion(.failure(.configurationError))
    }
    
    func executePumpEventQuery(fromQueryAnchor queryAnchor: DoseStore.QueryAnchor?, limit: Int, completion: @escaping (DoseStore.PumpEventQueryResult) -> Void) {
        completion(.failure(DoseStore.DoseStoreError.configurationError))
    }
    
    func getTotalUnitsDelivered(since startDate: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        completion(.failure(.configurationError))
    }
    
    func getGlucoseEffects(start: Date, end: Date? = nil, basalDosingEnd: Date? = Date(), completion: @escaping (_ result: DoseStoreResult<[GlucoseEffect]>) -> Void) {
        let fixture: [JSONDictionary] = loadFixture(fixtureToLoad)
        let dateFormatter = ISO8601DateFormatter.localTimeDate()

        return completion(.success(fixture.map {
            return GlucoseEffect(
                startDate: dateFormatter.date(from: $0["date"] as! String)!,
                quantity: HKQuantity(
                    unit: HKUnit(from: $0["unit"] as! String),
                    doubleValue: $0["amount"] as! Double
                )
            )
        }))
    }
    
    static func currentDate(for testType: DataManagerTestType) -> Date {
        switch testType {
        case .flatAndStable:
            return dateFormatter.date(from: "2020-08-11T20:45:02")!
        case .highAndStable:
            return dateFormatter.date(from: "2020-08-12T12:39:22")!
        case .highAndRisingWithCOB:
            return dateFormatter.date(from: "2020-08-11T21:48:17")!
        case .lowAndFallingWithCOB:
            return dateFormatter.date(from: "2020-08-11T22:06:06")!
        case .lowWithLowTreatment:
            return dateFormatter.date(from: "2020-08-11T22:23:55")!
        case .highAndFalling:
            return dateFormatter.date(from: "2020-08-11T22:59:45")!
        }
    }
}

extension MockDoseStore {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }
    
    var fixtureToLoad: String {
        switch testType {
        case .flatAndStable:
            return "flat_and_stable_insulin_effect"
        case .highAndStable:
            return "high_and_stable_insulin_effect"
        case .highAndRisingWithCOB:
            return "high_and_rising_with_cob_insulin_effect"
        case .lowAndFallingWithCOB:
            return "low_and_falling_insulin_effect"
        case .lowWithLowTreatment:
            return "low_with_low_treatment_insulin_effect"
        case .highAndFalling:
            return "high_and_falling_insulin_effect"
        }
    }
}
