//
//  EnliteCGMManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 3/12/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopUI
import MinimedKit
import RileyLinkKit


final class EnliteCGMManager: CGMManager {
    let providesBLEHeartbeat = false

    weak var delegate: CGMManagerDelegate?

    var sensorState: SensorDisplayable?

    let managedDataInterval: TimeInterval? = nil

    func fetchNewDataIfNeeded(with deviceManager: DeviceDataManager, _ completion: @escaping (CGMResult) -> Void) {
        deviceManager.rileyLinkManager.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                completion(.error(LoopError.connectionError))
                return
            }

            guard let ops = deviceManager.pumpOps else {
                completion(.error(LoopError.configurationError("Pump ID")))
                return
            }

            let latestGlucoseDate = self.delegate?.startDateToFilterNewData(for: self) ?? Date(timeIntervalSinceNow: TimeInterval(hours: -24))

            guard latestGlucoseDate.timeIntervalSinceNow <= TimeInterval(minutes: -4.5) else {
                completion(.noData)
                return
            }

            ops.runSession(withName: "Fetch Enlite History", using: device) { (session) in
                do {
                    let events = try session.getGlucoseHistoryEvents(since: latestGlucoseDate.addingTimeInterval(.minutes(1)))
                    _ = deviceManager.remoteDataManager.nightscoutService.uploader?.processGlucoseEvents(events, source: device.deviceURI)

                    if let latestSensorEvent = events.compactMap({ $0.glucoseEvent as? RelativeTimestampedGlucoseEvent }).last {
                        self.sensorState = EnliteSensorDisplayable(latestSensorEvent)
                    }

                    let unit = HKUnit.milligramsPerDeciliter
                    let glucoseValues: [NewGlucoseSample] = events
                        // TODO: Is the { $0.date > latestGlucoseDate } filter duplicative?
                        .filter({ $0.glucoseEvent is SensorValueGlucoseEvent && $0.date > latestGlucoseDate })
                        .map {
                            let glucoseEvent = $0.glucoseEvent as! SensorValueGlucoseEvent
                            let quantity = HKQuantity(unit: unit, doubleValue: Double(glucoseEvent.sgv))
                            return NewGlucoseSample(date: $0.date, quantity: quantity, isDisplayOnly: false, syncIdentifier: glucoseEvent.glucoseSyncIdentifier ?? UUID().uuidString, device: self.device)
                        }

                    completion(.newData(glucoseValues))
                } catch let error {
                    completion(.error(error))
                }
            }
        }
    }

    var device: HKDevice? = nil

    var debugDescription: String {
        return [
            "## EnliteCGMManager",
            "sensorState: \(String(describing: sensorState))",
            ""
        ].joined(separator: "\n")
    }
}

