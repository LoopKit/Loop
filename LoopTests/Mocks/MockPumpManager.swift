//
//  MockPumpManager.swift
//  LoopTests
//
//  Created by Pete Schwamb on 10/31/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI
import HealthKit
@testable import Loop

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
        completion(.success(deliveryLimits))
    }

    func estimatedDuration(toBolus units: Double) -> TimeInterval {
        .minutes(units / deliveryUnitsPerMinute)
    }

    var pluginIdentifier: String = "MockPumpManager"

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
