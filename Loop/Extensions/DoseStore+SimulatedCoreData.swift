//
//  DoseStore+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/5/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

// MARK: - Simulated Core Data

extension DoseStore {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedBolusPerDay: Int { 8 }
    private var simulatedBasalStartDateInterval: TimeInterval { .minutes(5) }
    private var simulatedOtherPerDay: Int { 1 }
    private var simulatedLimit: Int { 10000 }

    func generateSimulatedHistoricalPumpEvents(completion: @escaping (Error?) -> Void) {
        generatedSimulatedHistoricalBasalPumpEvents() { error in
            guard error == nil else {
                completion(error)
                return
            }
            self.generatedSimulatedHistoricalBolusPumpEvents() { error in
                guard error == nil else {
                    completion(error)
                    return
                }
                self.generatedSimulatedHistoricalOtherPumpEvents(completion: completion)
            }
        }
    }

    private func generatedSimulatedHistoricalBasalPumpEvents(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: cacheStartDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var index = 0
        var simulated = [PersistedPumpEvent]()

        while startDate < endDate {
            switch index % 3 {
            case 0:
                simulated.append(PersistedPumpEvent.simulatedTempBasal(date: startDate, duration: .minutes(5), rate: 0, scheduledRate: 1))
            case 1:
                simulated.append(PersistedPumpEvent.simulatedTempBasal(date: startDate, duration: .minutes(5), rate: 2, scheduledRate: 1))
            default:
                simulated.append(PersistedPumpEvent.simulatedBasal(date: startDate, duration: .minutes(5), rate: 1))
            }

            if simulated.count >= simulatedLimit {
                if let error = addPumpEvents(events: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            index += 1
            startDate = startDate.addingTimeInterval(simulatedBasalStartDateInterval)
        }

        completion(addPumpEvents(events: simulated))
    }

    private func generatedSimulatedHistoricalBolusPumpEvents(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: cacheStartDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [PersistedPumpEvent]()

        while startDate < endDate {
            for index in 0..<simulatedBolusPerDay {
                simulated.append(PersistedPumpEvent.simulatedBolus(date: startDate.addingTimeInterval(.hours(24) * Double(index) / Double(simulatedBolusPerDay)),
                                                                amount: Double(2 + index % 3)))
            }

            if simulated.count >= simulatedLimit {
                if let error = addPumpEvents(events: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        completion(addPumpEvents(events: simulated))
    }

    private func generatedSimulatedHistoricalOtherPumpEvents(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: cacheStartDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [PersistedPumpEvent]()

        while startDate < endDate {
            for index in 0..<simulatedOtherPerDay {
                var date = startDate.addingTimeInterval(.hours(24) * Double(index) / Double(simulatedOtherPerDay) + .minutes(5))
                simulated.append(PersistedPumpEvent.simulatedAlarm(date: date))
                simulated.append(PersistedPumpEvent.simulatedSuspend(date: date))
                date = date.addingTimeInterval(.minutes(1))
                simulated.append(PersistedPumpEvent.simulatedAlarmClear(date: date))
                simulated.append(PersistedPumpEvent.simulatedRewind(date: date))
                date = date.addingTimeInterval(.minutes(2))
                simulated.append(PersistedPumpEvent.simulatedPrime(date: date))
                date = date.addingTimeInterval(.minutes(1))
                simulated.append(PersistedPumpEvent.simulatedResume(date: date))
            }

            if simulated.count >= simulatedLimit {
                if let error = addPumpEvents(events: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        completion(addPumpEvents(events: simulated))
    }

    func purgeHistoricalPumpEvents(completion: @escaping (Error?) -> Void) {
        purgePumpEventObjects(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension PersistedPumpEvent {
    static func simulatedAlarm(date: Date) -> PersistedPumpEvent {
        return simulated(date: date, type: .alarm)
    }

    static func simulatedAlarmClear(date: Date) -> PersistedPumpEvent {
        return simulated(date: date, type: .alarmClear)
    }

    static func simulatedBasal(date: Date, duration: TimeInterval, rate: Double) -> PersistedPumpEvent {
        return simulated(dose: DoseEntry(type: .basal,
                                  startDate: date,
                                  endDate: date.addingTimeInterval(duration),
                                  value: rate,
                                  unit: .unitsPerHour,
                                  deliveredUnits: rate * duration / .hours(1)))
    }

    static func simulatedBolus(date: Date, amount: Double) -> PersistedPumpEvent {
        return simulated(dose: DoseEntry(type: .bolus,
                                  startDate: date,
                                  endDate: date.addingTimeInterval(.minutes(1)),
                                  value: amount,
                                  unit: .units))
    }

    static func simulatedPrime(date: Date) -> PersistedPumpEvent {
        return simulated(date: date, type: .prime)
    }

    static func simulatedResume(date: Date) -> PersistedPumpEvent {
        return simulated(dose: DoseEntry(resumeDate: date))
    }

    static func simulatedRewind(date: Date) -> PersistedPumpEvent {
        return simulated(date: date, type: .rewind)
    }

    static func simulatedSuspend(date: Date) -> PersistedPumpEvent {
        return simulated(dose: DoseEntry(suspendDate: date))
    }

    static func simulatedTempBasal(date: Date, duration: TimeInterval, rate: Double, scheduledRate: Double) -> PersistedPumpEvent {
        return simulated(dose: DoseEntry(type: .tempBasal,
                                  startDate: date,
                                  endDate: date.addingTimeInterval(duration),
                                  value: rate,
                                  unit: .unitsPerHour,
                                  deliveredUnits: rate * duration / .hours(1),
                                  scheduledBasalRate: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: scheduledRate)))
    }

    private static func simulated(date: Date, type: PumpEventType) -> PersistedPumpEvent {
        return PersistedPumpEvent(date: date,
                                  persistedDate: date,
                                  dose: nil,
                                  isUploaded: false,
                                  objectIDURL: URL(string: "x-coredata:///PumpEvent/\(UUID().uuidString)")!,
                                  raw: Data(UUID().uuidString.utf8),
                                  title: UUID().uuidString,
                                  type: type,
                                  isMutable: false)
    }

    private static func simulated(dose: DoseEntry) -> PersistedPumpEvent {
        return PersistedPumpEvent(date: dose.startDate,
                                  persistedDate: dose.startDate,
                                  dose: dose,
                                  isUploaded: false,
                                  objectIDURL: URL(string: "x-coredata:///PumpEvent/\(UUID().uuidString)")!,
                                  raw: Data(UUID().uuidString.utf8),
                                  title: String(describing: dose),
                                  type: dose.type.pumpEventType!,
                                  isMutable: false)
    }
}
