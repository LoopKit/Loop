//
//  DoseEnactorTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 7/30/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
import Foundation
import LoopKit
import HealthKit

@testable import Loop

enum MockPumpManagerError: Error {
    case failed
}

extension MockPumpManagerError: LocalizedError {
    
}

class MockPumpManager: PumpManager {

    var enactBolusCalled: ((Double, BolusActivationType) -> Void)?

    var enactTempBasalCalled: ((Double, TimeInterval) -> Void)?
    
    var enactTempBasalError: PumpManagerError?
    
    init() {
        
    }
    
    // PumpManager implementation
    static var onboardingMaximumBasalScheduleEntryCount: Int = 24
    
    static var onboardingSupportedBasalRates: [Double] = [1,2,3]
    
    static var onboardingSupportedBolusVolumes: [Double] = [1,2,3]

    static var onboardingSupportedMaximumBolusVolumes: [Double] = [1,2,3]
    
    let deliveryUnitsPerMinute = 1.5
    
    var supportedBasalRates: [Double] = [1,2,3]
    
    var supportedBolusVolumes: [Double] = [1,2,3]

    var supportedMaximumBolusVolumes: [Double] = [1,2,3]
    
    var maximumBasalScheduleEntryCount: Int = 24
    
    var minimumBasalScheduleEntryDuration: TimeInterval = .minutes(30)
    
    var pumpManagerDelegate: PumpManagerDelegate?
    
    var pumpRecordsBasalProfileStartEvents: Bool = false
    
    var pumpReservoirCapacity: Double = 50
    
    var lastSync: Date?
    
    var status: PumpManagerStatus =
        PumpManagerStatus(
            timeZone: TimeZone.current,
            device: HKDevice(name: "MockPumpManager", manufacturer: nil, model: nil, hardwareVersion: nil, firmwareVersion: nil, softwareVersion: nil, localIdentifier: nil, udiDeviceIdentifier: nil),
            pumpBatteryChargeRemaining: nil,
            basalDeliveryState: nil,
            bolusState: .noBolus,
            insulinType: .novolog)
    
    func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
    }
    
    func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
    }
    
    func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        completion?(Date())
    }
    
    func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
    }
    
    func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        return nil
    }
    
    func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (PumpManagerError?) -> Void) {
        enactBolusCalled?(units, activationType)
        completion(nil)
    }
    
    func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        completion(.success(nil))
    }
    
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (PumpManagerError?) -> Void) {
        enactTempBasalCalled?(unitsPerHour, duration)
        completion(enactTempBasalError)
    }
    
    func suspendDelivery(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    func resumeDelivery(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>], completion: @escaping (Result<BasalRateSchedule, Error>) -> Void) {
    }

    func syncDeliveryLimits(limits deliveryLimits: DeliveryLimits, completion: @escaping (Result<DeliveryLimits, Error>) -> Void) {

    }
    
    func estimatedDuration(toBolus units: Double) -> TimeInterval {
        .minutes(units / deliveryUnitsPerMinute)
    }

    var managerIdentifier: String = "MockPumpManager"
    
    var localizedTitle: String = "MockPumpManager"
    
    var delegateQueue: DispatchQueue!
    
    required init?(rawState: RawStateValue) {
        
    }
    
    var rawState: RawStateValue = [:]
    
    var isOnboarded: Bool = true
    
    var debugDescription: String = "MockPumpManager"
    
    func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
    }
    
    func getSoundBaseURL() -> URL? {
        return nil
    }
    
    func getSounds() -> [Alert.Sound] {
        return [.sound(name: "doesntExist")]
    }
}

class DoseEnactorTests: XCTestCase {
    func testBasalAndBolusDosedSerially() {
        let enactor = DoseEnactor()
        let tempBasalRecommendation = TempBasalRecommendation(unitsPerHour: 0, duration: 0) // Cancel
        let recommendation = AutomaticDoseRecommendation(basalAdjustment: tempBasalRecommendation, bolusUnits: 1.5)
        let pumpManager = MockPumpManager()
        
        let tempBasalExpectation = expectation(description: "enactTempBasal called")
        pumpManager.enactTempBasalCalled = { (rate, duration) in
            tempBasalExpectation.fulfill()
        }

        let bolusExpectation = expectation(description: "enactBolus called")
        pumpManager.enactBolusCalled = { (amount, automatic) in
            bolusExpectation.fulfill()
        }
        
        enactor.enact(recommendation: recommendation, with: pumpManager) { error in
            XCTAssertNil(error)
        }
        
        wait(for: [tempBasalExpectation, bolusExpectation], timeout: 5, enforceOrder: true)
    }
    
    func testBolusDoesNotIssueIfTempBasalAdjustmentFailed() {
        let enactor = DoseEnactor()
        let tempBasalRecommendation = TempBasalRecommendation(unitsPerHour: 0, duration: 0) // Cancel
        let recommendation = AutomaticDoseRecommendation(basalAdjustment: tempBasalRecommendation, bolusUnits: 1.5)
        let pumpManager = MockPumpManager()
        
        let tempBasalExpectation = expectation(description: "enactTempBasal called")
        pumpManager.enactTempBasalCalled = { (rate, duration) in
            tempBasalExpectation.fulfill()
        }

        pumpManager.enactBolusCalled = { (amount, automatic) in
            XCTFail("Should not enact bolus")
        }
        
        pumpManager.enactTempBasalError = .configuration(MockPumpManagerError.failed)

        enactor.enact(recommendation: recommendation, with: pumpManager) { error in
            XCTAssertNotNil(error)
        }
        
        waitForExpectations(timeout: 2)
    }
    
    func testTempBasalOnly() {
        let enactor = DoseEnactor()
        let tempBasalRecommendation = TempBasalRecommendation(unitsPerHour: 1.2, duration: .minutes(30)) // Cancel
        let recommendation = AutomaticDoseRecommendation(basalAdjustment: tempBasalRecommendation, bolusUnits: 0)
        let pumpManager = MockPumpManager()
        
        let tempBasalExpectation = expectation(description: "enactTempBasal called")
        pumpManager.enactTempBasalCalled = { (rate, duration) in
            XCTAssertEqual(1.2, rate)
            XCTAssertEqual(.minutes(30), duration)
            tempBasalExpectation.fulfill()
        }

        pumpManager.enactBolusCalled = { (amount, automatic) in
            XCTFail("Should not enact bolus")
        }
        

        enactor.enact(recommendation: recommendation, with: pumpManager) { error in
            XCTAssertNil(error)
        }
        
        waitForExpectations(timeout: 2)
    }


}
