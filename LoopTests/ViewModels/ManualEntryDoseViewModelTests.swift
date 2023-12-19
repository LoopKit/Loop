//
//  ManualEntryDoseViewModelTests.swift
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

@MainActor
class ManualEntryDoseViewModelTests: XCTestCase {

    static let now = Date.distantFuture
    
    var now: Date = BolusEntryViewModelTests.now

    var manualEntryDoseViewModel: ManualEntryDoseViewModel!

    static let exampleBolusQuantity = HKQuantity(unit: .internationalUnit(), doubleValue: 1.0)

    static let noBolus = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
    
    fileprivate var delegate: MockManualEntryDoseViewModelDelegate!
    
    static let mockUUID = UUID()
    let mockUUID = ManualEntryDoseViewModelTests.mockUUID.uuidString

    override func setUpWithError() throws {
        now = Self.now
        delegate = MockManualEntryDoseViewModelDelegate()
        setUpViewModel()
    }

    func setUpViewModel() {
        manualEntryDoseViewModel = ManualEntryDoseViewModel(delegate: delegate,
                                                  now: { self.now },
                                                  debounceIntervalMilliseconds: 0,
                                                  uuidProvider: { self.mockUUID },
                                                  timeZone: TimeZone(abbreviation: "GMT")!)
        manualEntryDoseViewModel.authenticationHandler = { _ in return true }
    }

    func testDoseLogging() async throws {
        XCTAssertEqual(.novolog, manualEntryDoseViewModel.selectedInsulinType)
        manualEntryDoseViewModel.enteredBolus = Self.exampleBolusQuantity
        
        try await manualEntryDoseViewModel.saveManualDose()

        XCTAssertEqual(delegate.manualEntryBolusUnits, Self.exampleBolusQuantity.doubleValue(for: .internationalUnit()))
        XCTAssertEqual(delegate.manuallyEnteredDoseInsulinType, .novolog)
    }

    func testDoseNotSavedIfNotAuthenticated() async throws {
        XCTAssertEqual(.novolog, manualEntryDoseViewModel.selectedInsulinType)
        manualEntryDoseViewModel.enteredBolus = Self.exampleBolusQuantity

        manualEntryDoseViewModel.authenticationHandler = { _ in return false }

        do {
            try await manualEntryDoseViewModel.saveManualDose()
            XCTFail("Saving should fail if not authenticated.")
        } catch { }

        XCTAssertNil(delegate.manualEntryBolusUnits)
        XCTAssertNil(delegate.manuallyEnteredDoseInsulinType)
    }

}

fileprivate class MockManualEntryDoseViewModelDelegate: ManualDoseViewModelDelegate {
    var pumpInsulinType: LoopKit.InsulinType?
   
    var manualEntryBolusUnits: Double?
    var manualEntryDoseStartDate: Date?
    var manuallyEnteredDoseInsulinType: InsulinType?

    func addManuallyEnteredDose(startDate: Date, units: Double, insulinType: InsulinType?) {
        manualEntryBolusUnits = units
        manualEntryDoseStartDate = startDate
        manuallyEnteredDoseInsulinType = insulinType
    }
    
    func insulinActivityDuration(for type: LoopKit.InsulinType?) -> TimeInterval {
        return InsulinMath.defaultInsulinActivityDuration
    }
    
    var algorithmDisplayState = AlgorithmDisplayState()

    var settings = StoredSettings()

    var scheduleOverride: TemporaryScheduleOverride?

}

