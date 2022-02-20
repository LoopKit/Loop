//
//  AlertStore+SimulatedCoreData.swift
//  Loop
//
//  Created by Darin Krauss on 6/12/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

// MARK: - Simulated Core Data

extension AlertStore {
    private var historicalEndDate: Date { Date(timeIntervalSinceNow: -.hours(24)) }

    private var simulatedPerDay: Int { 12 }
    private var simulatedLimit: Int { 10000 }

    func generateSimulatedHistoricalStoredAlerts(completion: @escaping (Error?) -> Void) {
        var startDate = Calendar.current.startOfDay(for: expireDate)
        let endDate = Calendar.current.startOfDay(for: historicalEndDate)
        var simulated = [DatedAlert]()

        while startDate < endDate {
            for index in 0..<simulatedPerDay {
                simulated.append(DatedAlert.simulated(date: startDate.addingTimeInterval(.hours(24) * Double(index) / Double(simulatedPerDay))))
            }

            if simulated.count >= simulatedLimit {
                if let error = addAlerts(alerts: simulated) {
                    completion(error)
                    return
                }
                simulated = []
            }

            startDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        completion(addAlerts(alerts: simulated))
    }

    func purgeHistoricalStoredAlerts(completion: @escaping (Error?) -> Void) {
        purge(before: historicalEndDate, completion: completion)
    }
}

fileprivate extension AlertStore.DatedAlert {
    static func simulated(date: Date) -> AlertStore.DatedAlert {
        let alert = Alert(identifier: Alert.Identifier(managerIdentifier: "simulatedManagerIdentifier",
                                                       alertIdentifier: "simulatedAlertIdentifier"),
                          foregroundContent: Alert.Content(title: "Simulated Alert Foreground Title",
                                                           body: "The body of a foreground simulated alert approximates an actual alert body.",
                                                           acknowledgeActionButtonLabel: "Acknowledged"),
                          backgroundContent: Alert.Content(title: "Simulated Alert Background Title",
                                                           body: "The body of a background simulated alert approximates an actual alert body.",
                                                           acknowledgeActionButtonLabel: "Acknowledged"),
                          trigger: .delayed(interval: 60),
                          sound: .sound(name: "simulated"),
                          metadata: Alert.Metadata(dict: ["simulated": true]))
        return AlertStore.DatedAlert(date: date, alert: alert, syncIdentifier: UUID())
    }
}
