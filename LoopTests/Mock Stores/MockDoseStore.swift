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
    var doseHistory: [DoseEntry]?
    var sensitivitySchedule: InsulinSensitivitySchedule?
    
    init(for scenario: DosingTestScenario = .flatAndStable) {
        self.scenario = scenario // The store returns different effect values based on the scenario
        self.pumpEventQueryAfterDate = scenario.currentDate
        self.lastAddedPumpData = scenario.currentDate
        self.doseHistory = loadHistoricDoses(scenario: scenario)
    }
    
    static let dateFormatter = ISO8601DateFormatter.localTimeDate()
    
    var scenario: DosingTestScenario
    
    var basalProfileApplyingOverrideHistory: BasalRateSchedule?
    
    var delegate: DoseStoreDelegate?
    
    var device: HKDevice?
    
    var pumpRecordsBasalProfileStartEvents: Bool = false
    
    var pumpEventQueryAfterDate: Date
    
    var basalProfile: BasalRateSchedule?
    
    // Default to the adult exponential insulin model
    var insulinModelProvider: InsulinModelProvider = StaticInsulinModelProvider(ExponentialInsulinModelPreset.rapidActingAdult)

    var longestEffectDuration: TimeInterval = ExponentialInsulinModelPreset.rapidActingAdult.effectDuration

    var insulinSensitivitySchedule: InsulinSensitivitySchedule?
    
    var sampleType: HKSampleType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery)!
    
    var authorizationRequired: Bool = false
    
    var sharingDenied: Bool = false
    
    var lastReservoirValue: ReservoirValue?
    
    var lastAddedPumpData: Date

    func addPumpEvents(_ events: [NewPumpEvent], lastReconciliation: Date?, replacePendingEvents: Bool, completion: @escaping (DoseStore.DoseStoreError?) -> Void) {
        completion(nil)
    }
    
    func addReservoirValue(_ unitVolume: Double, at date: Date, completion: @escaping (ReservoirValue?, ReservoirValue?, Bool, DoseStore.DoseStoreError?) -> Void) {
        completion(nil, nil, false, nil)
    }
    
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        completion(.success(.init(startDate: scenario.currentDate, value: 9.5)))
    }
    
    func generateDiagnosticReport(_ completion: @escaping (String) -> Void) {
        completion("")
    }
    
    func addDoses(_ doses: [DoseEntry], from device: HKDevice?, completion: @escaping (Error?) -> Void) {
        completion(nil)
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
        if let doseHistory, let sensitivitySchedule, let basalProfile = basalProfileApplyingOverrideHistory {
            // To properly know glucose effects at startDate, we need to go back another DIA hours
            let doseStart = start.addingTimeInterval(-longestEffectDuration)
            let doses = doseHistory.filterDateRange(doseStart, end)
            let trimmedDoses = doses.map { (dose) -> DoseEntry in
                guard dose.type != .bolus else {
                    return dose
                }
                return dose.trimmed(to: basalDosingEnd)
            }

            let annotatedDoses = trimmedDoses.annotated(with: basalProfile)

            let glucoseEffects = annotatedDoses.glucoseEffects(insulinModelProvider: self.insulinModelProvider, longestEffectDuration: self.longestEffectDuration, insulinSensitivity: sensitivitySchedule, from: start, to: end)
            completion(.success(glucoseEffects.filterDateRange(start, end)))
        } else {
            return completion(.success(getCannedGlucoseEffects()))
        }
    }

    func getCannedGlucoseEffects() -> [GlucoseEffect] {
        let fixture: [JSONDictionary] = loadFixture(fixtureToLoad)
        let dateFormatter = ISO8601DateFormatter.localTimeDate()

        return fixture.map {
            return GlucoseEffect(
                startDate: dateFormatter.date(from: $0["date"] as! String)!,
                quantity: HKQuantity(
                    unit: HKUnit(from: $0["unit"] as! String),
                    doubleValue: $0["amount"] as! Double
                )
            )
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
        switch scenario {
        case .liveCapture:
            fatalError("live capture scenario computes effects from doses, does not used pre-canned effects")
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

    public func loadHistoricDoses(scenario: DosingTestScenario) -> [DoseEntry]? {
        if let url = bundle.url(forResource: scenario.fixturePrefix + "doses", withExtension: "json"),
           let data = try? Data(contentsOf: url)
        {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode([DoseEntry].self, from: data)
        } else {
            return nil
        }
    }

}
