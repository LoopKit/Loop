//
//  DoseStore+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/5/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopAlgorithm
import LoopKit

// MARK: - Simulated Core Data

extension DoseStore {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedBolusPerDay: Int { 8 }
    private var simulatedBasalStartDateInterval: TimeInterval { .minutes(5) }
    private var simulatedOtherPerDay: Int { 1 }
    private var simulatedLimit: Int { 10000 }
    private var suspendDuration: TimeInterval { .minutes(30) }

    func generateSimulatedHistoricalPumpEvents() async throws {
        var startDate = Calendar.current.startOfDay(for: cacheStartDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var index = 0
        var simulated = [PersistedPumpEvent]()
        var suspendedAt: Date?

        while startDate < endDate {

            let basalEvent: PersistedPumpEvent?

            if let suspendedTime = suspendedAt, startDate.timeIntervalSince(suspendedTime) > suspendDuration {
                // suspend is over, allow for other basal events
                suspendedAt = nil
            }
            
            if suspendedAt == nil { // if suspended, no other basal events
                if Double.random(in: 0...1) > 0.98 { // 2% chance of this being a suspend
                    basalEvent = PersistedPumpEvent.simulatedSuspend(date: startDate)
                    suspendedAt = startDate
                } else if suspendedAt == nil, Double.random(in: 0...1) < 0.98 { // 98% chance of a successful basal
                    let rate = [0, 0.5, 1, 1.5, 2, 6].randomElement()!
                    basalEvent = PersistedPumpEvent.simulatedTempBasal(date: startDate, duration: .minutes(5), rate: rate, scheduledRate: 1)
                } else {
                    basalEvent = nil
                }
            } else {
                basalEvent = nil
            }

            if let basalEvent = basalEvent {
                simulated.append(basalEvent)
                if basalEvent.type == .suspend {
                    // Report the resume immediately to avoid reconcilation issues
                    let resumeBasalEvent = PersistedPumpEvent.simulatedResume(date: basalEvent.date.addingTimeInterval(suspendDuration))
                    simulated.append(resumeBasalEvent)
                }
            }

            if Double.random(in: 0...1) > 0.98 { // 2% chance of some other event
                let eventDate = startDate.addingTimeInterval(.minutes(1))
                simulated.append([
                    PersistedPumpEvent.simulatedAlarm(date: eventDate),
                    PersistedPumpEvent.simulatedAlarmClear(date: eventDate),
                    PersistedPumpEvent.simulatedRewind(date: eventDate),
                    PersistedPumpEvent.simulatedPrime(date: eventDate)
                ].randomElement()!)
            }

            if Double.random(in: 0...1) < 0.27 { // Aim for roughly 8 per day (chance = 8/288)
                let eventDate = startDate.addingTimeInterval(.minutes(2))
                let amount = [0, 1.5, 2, 3.5, 5, 6].randomElement()!
                simulated.append(PersistedPumpEvent.simulatedBolus(date: eventDate, amount: amount))
            }


            // Process about a day's worth at a time
            if simulated.count >= 300 {
                try await addPumpEvents(events: simulated)
                simulated = []
            }

            index += 1
            startDate = startDate.addingTimeInterval(simulatedBasalStartDateInterval)
        }

        try await addPumpEvents(events: simulated)
    }

    func purgeHistoricalPumpEvents() async throws {
        try await purgePumpEventObjects(before: historicalEndDate)
    }
}

fileprivate extension PersistedPumpEvent {
    static func simulatedAlarm(date: Date) -> PersistedPumpEvent {
        return simulated(date: date, type: .alarm, alarmType: .other("Simulated Other Alarm"))
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
                                         scheduledBasalRate: LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: scheduledRate)))
    }

    private static func simulated(date: Date, type: PumpEventType, alarmType: PumpAlarmType? = nil) -> PersistedPumpEvent {
        return PersistedPumpEvent(date: date,
                                  persistedDate: date,
                                  dose: nil,
                                  isUploaded: false,
                                  objectIDURL: URL(string: "x-coredata:///PumpEvent/\(UUID().uuidString)")!,
                                  raw: Data(UUID().uuidString.utf8),
                                  title: UUID().uuidString,
                                  type: type,
                                  automatic: nil,
                                  alarmType: alarmType)
    }

    private static func simulated(dose: DoseEntry) -> PersistedPumpEvent {
        return PersistedPumpEvent(date: dose.startDate,
                                  persistedDate: dose.startDate,
                                  dose: dose,
                                  isUploaded: false,
                                  objectIDURL: URL(string: "x-coredata:///PumpEvent/\(UUID().uuidString)")!,
                                  raw: Data(UUID().uuidString.utf8),
                                  title: String(describing: dose),
                                  type: dose.type.pumpEventType,
                                  automatic: nil)
    }
}
