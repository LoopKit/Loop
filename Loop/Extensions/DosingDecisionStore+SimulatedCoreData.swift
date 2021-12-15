//
//  DosingDecisionStore+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/5/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

// MARK: - Simulated Core Data

extension DosingDecisionStore {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedStartDateInterval: TimeInterval { .minutes(5) }
    private var simulatedLimit: Int { 10000 }

    func generateSimulatedHistoricalDosingDecisionObjects(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: expireDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [StoredDosingDecision]()

        while startDate < endDate {
            simulated.append(StoredDosingDecision.simulated(date: startDate))

            if simulated.count >= simulatedLimit {
                if let error = addSimulatedHistoricalDosingDecisionObjects(dosingDecisions: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = startDate.addingTimeInterval(simulatedStartDateInterval)
        }

        completion(addSimulatedHistoricalDosingDecisionObjects(dosingDecisions: simulated))
    }

    private func addSimulatedHistoricalDosingDecisionObjects(dosingDecisions: [StoredDosingDecision]) -> Error? {
        var addError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        addStoredDosingDecisions(dosingDecisions: dosingDecisions) { error in
            addError = error
            semaphore.signal()
        }
        semaphore.wait()
        return addError
    }

    func purgeHistoricalDosingDecisionObjects(completion: @escaping (Error?) -> Void) {
        purgeDosingDecisions(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension StoredDosingDecision {
    static func simulated(date: Date) -> StoredDosingDecision {
        let controllerTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        let scheduleTimeZone = TimeZone(secondsFromGMT: TimeZone(identifier: "America/Phoenix")!.secondsFromGMT())!
        let reason = "simulatedCoreData"
        let settings = StoredDosingDecision.Settings(syncIdentifier: UUID(uuidString: "18CF3948-0B3D-4B12-8BFE-14986B0E6784")!)
        let scheduleOverride = TemporaryScheduleOverride(context: .preMeal,
                                                         settings: TemporaryScheduleOverrideSettings(unit: .milligramsPerDeciliter,
                                                                                                     targetRange: DoubleRange(minValue: 80.0,
                                                                                                                              maxValue: 90.0),
                                                                                                     insulinNeedsScaleFactor: 1.5),
                                                         startDate: date.addingTimeInterval(-.hours(0.5)),
                                                         duration: .finite(.hours(1)),
                                                         enactTrigger: .local,
                                                         syncIdentifier: UUID())
        let controllerStatus = StoredDosingDecision.ControllerStatus(batteryState: .charging,
                                                                     batteryLevel: 0.5)
        let pumpManagerStatus = PumpManagerStatus(timeZone: scheduleTimeZone,
                                                  device: HKDevice(name: "Pump Name",
                                                                   manufacturer: "Pump Manufacturer",
                                                                   model: "Pump Model",
                                                                   hardwareVersion: "Pump Hardware Version",
                                                                   firmwareVersion: "Pump Firmware Version",
                                                                   softwareVersion: "Pump Software Version",
                                                                   localIdentifier: "Pump Local Identifier",
                                                                   udiDeviceIdentifier: "Pump UDI Device Identifier"),
                                                  pumpBatteryChargeRemaining: 0.75,
                                                  basalDeliveryState: .initiatingTempBasal,
                                                  bolusState: .noBolus,
                                                  insulinType: .novolog)
        let cgmManagerStatus = CGMManagerStatus(hasValidSensorSession: true,
                                                lastCommunicationDate: date.addingTimeInterval(-.minutes(1)),
                                                device: HKDevice(name: "CGM Name",
                                                                 manufacturer: "CGM Manufacturer",
                                                                 model: "CGM Model",
                                                                 hardwareVersion: "CGM Hardware Version",
                                                                 firmwareVersion: "CGM Firmware Version",
                                                                 softwareVersion: "CGM Software Version",
                                                                 localIdentifier: "CGM Local Identifier",
                                                                 udiDeviceIdentifier: "CGM UDI Device Identifier"))
        let lastReservoirValue = StoredDosingDecision.LastReservoirValue(startDate: date.addingTimeInterval(-.minutes(1)),
                                                                         unitVolume: 113.3)
        var historicalGlucose = [HistoricalGlucoseValue]()
        for minutes in stride(from: -120.0, to: 0.0, by: 5.0) {
            historicalGlucose.append(HistoricalGlucoseValue(startDate: date.addingTimeInterval(.minutes(minutes)),
                                                            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 125 + minutes / 5)))
        }
        let originalCarbEntry = StoredCarbEntry(uuid: UUID(uuidString: "C86DEB61-68E9-464E-9DD5-96A9CB445FD3")!,
                                                provenanceIdentifier: Bundle.main.bundleIdentifier!,
                                                syncIdentifier: "2B03D96C-6F5D-4140-99CD-80C3E64D6010",
                                                syncVersion: 1,
                                                startDate: date.addingTimeInterval(-.minutes(15)),
                                                quantity: HKQuantity(unit: .gram(), doubleValue: 15),
                                                foodType: "Simulated",
                                                absorptionTime: .hours(3),
                                                createdByCurrentApp: true,
                                                userCreatedDate: date.addingTimeInterval(-.minutes(15)),
                                                userUpdatedDate: date.addingTimeInterval(-.minutes(1)))
        let carbEntry = StoredCarbEntry(uuid: UUID(uuidString: "71B699D7-0E8F-4B13-B7A1-E7751EB78E74")!,
                                        provenanceIdentifier: Bundle.main.bundleIdentifier!,
                                        syncIdentifier: "2B03D96C-6F5D-4140-99CD-80C3E64D6010",
                                        syncVersion: 2,
                                        startDate: date.addingTimeInterval(-.minutes(1)),
                                        quantity: HKQuantity(unit: .gram(), doubleValue: 25),
                                        foodType: "Simulated",
                                        absorptionTime: .hours(5),
                                        createdByCurrentApp: true,
                                        userCreatedDate: date.addingTimeInterval(-.minutes(1)),
                                        userUpdatedDate: nil)
        let manualGlucoseSample = StoredGlucoseSample(uuid: UUID(uuidString: "71B699D7-0E8F-4B13-B7A1-E7751EB78E74")!,
                                                      provenanceIdentifier: Bundle.main.bundleIdentifier!,
                                                      syncIdentifier: "2A67A303-1234-4CB8-8263-79498265368E",
                                                      syncVersion: 1,
                                                      startDate: date.addingTimeInterval(-.minutes(1)),
                                                      quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 123.45),
                                                      condition: nil,
                                                      trend: .up,
                                                      trendRate: HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: 3.4),
                                                      isDisplayOnly: false,
                                                      wasUserEntered: true,
                                                      device: HKDevice(name: "Device Name",
                                                                       manufacturer: "Device Manufacturer",
                                                                       model: "Device Model",
                                                                       hardwareVersion: "Device Hardware Version",
                                                                       firmwareVersion: "Device Firmware Version",
                                                                       softwareVersion: "Device Software Version",
                                                                       localIdentifier: "Device Local Identifier",
                                                                       udiDeviceIdentifier: "Device UDI Device Identifier"),
                                                      healthKitEligibleDate: nil)
        let carbsOnBoard = CarbValue(startDate: date,
                                     endDate: date.addingTimeInterval(.minutes(5)),
                                     quantity: HKQuantity(unit: .gram(), doubleValue: 45.5))
        let insulinOnBoard = InsulinValue(startDate: date, value: 1.5)
        let glucoseTargetRangeSchedule = GlucoseRangeSchedule(rangeSchedule: DailyQuantitySchedule(unit: .milligramsPerDeciliter,
                                                                                                   dailyItems: [RepeatingScheduleValue(startTime: .hours(0), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(8), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(10), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(12), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(14), value: DoubleRange(minValue: 95.0, maxValue: 105.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(16), value: DoubleRange(minValue: 100.0, maxValue: 110.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(18), value: DoubleRange(minValue: 90.0, maxValue: 100.0)),
                                                                                                                RepeatingScheduleValue(startTime: .hours(21), value: DoubleRange(minValue: 110.0, maxValue: 120.0))],
                                                                                                   timeZone: scheduleTimeZone)!)
        var predictedGlucose = [PredictedGlucoseValue]()
        for minutes in stride(from: 5.0, to: 360.0, by: 5.0) {
            predictedGlucose.append(PredictedGlucoseValue(startDate: date.addingTimeInterval(.minutes(minutes)),
                                                          quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 125 + minutes / 5)))
        }
        let automaticDoseRecommendation = AutomaticDoseRecommendation(basalAdjustment: TempBasalRecommendation(unitsPerHour: 0.75,
                                                                                                               duration: .minutes(30)),
                                                                      bolusUnits: 1.25)
        let manualBolusRecommendation = ManualBolusRecommendationWithDate(recommendation: ManualBolusRecommendation(amount: 0.2,
                                                                                                                    pendingInsulin: 0.75,
                                                                                                                    notice: .predictedGlucoseBelowTarget(minGlucose: PredictedGlucoseValue(startDate: date.addingTimeInterval(.minutes(30)),
                                                                                                                                                                                           quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 95.0)))),
                                                                          date: date.addingTimeInterval(-.minutes(1)))
        let manualBolusRequested = 0.5
        let warnings: [Issue] = [Issue(id: "one"),
                                 Issue(id: "two", details: ["size": "small"])]
        let errors: [Issue] = [Issue(id: "alpha"),
                               Issue(id: "bravo", details: ["size": "tiny"])]

        return StoredDosingDecision(date: date,
                                    controllerTimeZone: controllerTimeZone,
                                    reason: reason,
                                    settings: settings,
                                    scheduleOverride: scheduleOverride,
                                    controllerStatus: controllerStatus,
                                    pumpManagerStatus: pumpManagerStatus,
                                    cgmManagerStatus: cgmManagerStatus,
                                    lastReservoirValue: lastReservoirValue,
                                    historicalGlucose: historicalGlucose,
                                    originalCarbEntry: originalCarbEntry,
                                    carbEntry: carbEntry,
                                    manualGlucoseSample: manualGlucoseSample,
                                    carbsOnBoard: carbsOnBoard,
                                    insulinOnBoard: insulinOnBoard,
                                    glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
                                    predictedGlucose: predictedGlucose,
                                    automaticDoseRecommendation: automaticDoseRecommendation,
                                    manualBolusRecommendation: manualBolusRecommendation,
                                    manualBolusRequested: manualBolusRequested,
                                    warnings: warnings,
                                    errors: errors)
    }
}
