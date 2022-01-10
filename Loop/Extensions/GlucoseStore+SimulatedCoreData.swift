//
//  GlucoseStore+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/4/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

// MARK: - Simulated Core Data

extension GlucoseStore {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedStartDateInterval: TimeInterval { .minutes(5) }
    private var simulatedValueBase: Double { 110 }
    private var simulatedValueAmplitude: Double { 40 }
    private var simulatedValueIncrement: Double { 2.0 * .pi / 72.0 }    // 6 hour period
    private var simulatedLimit: Int { 10000 }

    func generateSimulatedHistoricalGlucoseObjects(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: earliestCacheDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var value = 0.0
        var simulated = [NewGlucoseSample]()

        while startDate < endDate {
            let previous = simulatedValueBase + simulatedValueAmplitude * sin(value - simulatedValueIncrement)
            let new = simulatedValueBase + simulatedValueAmplitude * sin(value)
            let trendRateValue = new - previous
            let trend: GlucoseTrend? = {
                switch trendRateValue {
                case -0.01...0.01:
                    return .flat
                case -2 ..< -0.01:
                    return .down
                case -5 ..< -2:
                    return .downDown
                case -Double.greatestFiniteMagnitude ..< -5:
                    return .downDownDown
                case 0.01...2:
                    return .up
                case 2...5:
                    return .upUp
                case 5...Double.greatestFiniteMagnitude:
                    return .upUpUp
                default:
                    return nil
                }
            }()
            simulated.append(NewGlucoseSample.simulated(date: startDate,
                                                        quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: new),
                                                        trend: trend,
                                                        trendRate: HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: trendRateValue)))

            if simulated.count >= simulatedLimit {
                if let error = addSimulatedHistoricalGlucoseObjects(samples: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            value += simulatedValueIncrement
            startDate = startDate.addingTimeInterval(simulatedStartDateInterval)
        }

        completion(addSimulatedHistoricalGlucoseObjects(samples: simulated))
    }

    private func addSimulatedHistoricalGlucoseObjects(samples: [NewGlucoseSample]) -> Error? {
        var addError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        addNewGlucoseSamples(samples: samples) { error in
            addError = error
            semaphore.signal()
        }
        semaphore.wait()
        return addError
    }

    func purgeHistoricalGlucoseObjects(completion: @escaping (Error?) -> Void) {
        purgeCachedGlucoseObjects(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension NewGlucoseSample {
    static func simulated(date: Date, quantity: HKQuantity, trend: GlucoseTrend?, trendRate: HKQuantity?) -> NewGlucoseSample {
        return NewGlucoseSample(date: date,
                                quantity: quantity,
                                condition: nil,
                                trend: trend,
                                trendRate: trendRate,
                                isDisplayOnly: false,
                                wasUserEntered: false,
                                syncIdentifier: UUID().uuidString)
    }
}
