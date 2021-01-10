//
//  LoggedDoseViewModelTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 1/2/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit
import XCTest
@testable import Loop

class LoggedDoseViewModelTests: XCTestCase {

    static let now = Date.distantFuture
    
    var now: Date = BolusEntryViewModelTests.now

    var loggedDoseViewModel: LoggedDoseViewModel!

    static let exampleBolusQuantity = HKQuantity(unit: .internationalUnit(), doubleValue: 1.0)

    static let noBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
    
    var authenticateOverrideCompletion: ((Swift.Result<Void, Error>) -> Void)?
    private func authenticateOverride(_ message: String, _ completion: @escaping (Swift.Result<Void, Error>) -> Void) {
        authenticateOverrideCompletion = completion
    }
    
    var saveAndDeliverSuccess = false

    fileprivate var delegate: MockLoggedDoseViewModelDelegate!
    
    static let mockUUID = UUID()
    let mockUUID = LoggedDoseViewModelTests.mockUUID.uuidString

    override func setUpWithError() throws {
        now = Self.now
        delegate = MockLoggedDoseViewModelDelegate()
        delegate.mostRecentGlucoseDataDate = now
        delegate.mostRecentPumpDataDate = now
        saveAndDeliverSuccess = false
        setUpViewModel()
    }

    func setUpViewModel() {
        loggedDoseViewModel = LoggedDoseViewModel(delegate: delegate,
                                                  now: { self.now },
                                                  screenWidth: 512,
                                                  debounceIntervalMilliseconds: 0,
                                                  uuidProvider: { self.mockUUID },
                                                  timeZone: TimeZone(abbreviation: "GMT")!)
        loggedDoseViewModel.authenticate = authenticateOverride
    }

    func testDoseLogging() throws {
        XCTAssertEqual(0, loggedDoseViewModel.selectedInsulinTypeIndex)
        loggedDoseViewModel.enteredBolus = Self.exampleBolusQuantity
        
        try saveAndDeliver(LoggedDoseViewModelTests.exampleBolusQuantity)
        XCTAssertEqual(delegate.loggedBolusUnits, Self.exampleBolusQuantity.doubleValue(for: .internationalUnit()))
        XCTAssertEqual(delegate.loggedDoseModel, .novolog)
    }
    
    private func saveAndDeliver(_ bolus: HKQuantity, file: StaticString = #file, line: UInt = #line) throws {
        loggedDoseViewModel.enteredBolus = bolus
        loggedDoseViewModel.logDose { self.saveAndDeliverSuccess = true }
        if bolus != LoggedDoseViewModelTests.noBolus {
            let authenticateOverrideCompletion = try XCTUnwrap(self.authenticateOverrideCompletion, file: file, line: line)
            authenticateOverrideCompletion(.success(()))
        }
    }
}

fileprivate class MockLoggedDoseViewModelDelegate: LoggedDoseViewModelDelegate {
    
    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval {
        return .hours(6) + .minutes(10)
    }
    
    var pumpInsulinType: InsulinType?
    
    var loggedBolusUnits: Double?
    var loggedDate: Date?
    var loggedDoseModel: InsulinType?
    func logOutsideInsulinDose(startDate: Date, units: Double, insulinType: InsulinType?) {
        loggedBolusUnits = units
        loggedDate = startDate
        loggedDoseModel = insulinType
    }
    
    var loopStateCallBlock: ((LoopState) -> Void)?
    func withLoopState(do block: @escaping (LoopState) -> Void) {
        loopStateCallBlock = block
    }
    
    var enactedBolusUnits: Double?
    var enactedBolusDate: Date?
    func enactBolus(units: Double, at startDate: Date, completion: @escaping (Error?) -> Void) {
        enactedBolusUnits = units
        enactedBolusDate = startDate
    }
    
    var getGlucoseSamplesResponse: [StoredGlucoseSample] = []
    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void) {
        completion(.success(getGlucoseSamplesResponse))
    }
    
    var insulinOnBoardResult: DoseStoreResult<InsulinValue>?
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        if let insulinOnBoardResult = insulinOnBoardResult {
            completion(insulinOnBoardResult)
        }
    }
    
    var carbsOnBoardResult: CarbStoreResult<CarbValue>?
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (CarbStoreResult<CarbValue>) -> Void) {
        if let carbsOnBoardResult = carbsOnBoardResult {
            completion(carbsOnBoardResult)
        }
    }
    
    var ensureCurrentPumpDataCompletion: (() -> Void)?
    func ensureCurrentPumpData(completion: @escaping () -> Void) {
        ensureCurrentPumpDataCompletion = completion
    }
    
    var mostRecentGlucoseDataDate: Date?
    
    var mostRecentPumpDataDate: Date?
    
    var isPumpConfigured: Bool = true
    
    var preferredGlucoseUnit: HKUnit = .milligramsPerDeciliter
    
    var settings: LoopSettings = LoopSettings()
}

