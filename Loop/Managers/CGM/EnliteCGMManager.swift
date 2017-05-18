//
//  EnliteCGMManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 3/12/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopUI
import MinimedKit


final class EnliteCGMManager: CGMManager {
    var providesBLEHeartbeat = false

    weak var delegate: CGMManagerDelegate?

    var sensorState: SensorDisplayable?

    func fetchNewDataIfNeeded(with deviceManager: DeviceDataManager, _ completion: @escaping (CGMResult) -> Void) {
        guard let device = deviceManager.rileyLinkManager.firstConnectedDevice?.ops
            else {
                completion(.noData)
                return
        }

        let latestGlucoseDate = self.delegate?.startDateToFilterNewData(for: self) ?? Date(timeIntervalSinceNow: TimeInterval(hours: -24))

        guard latestGlucoseDate.timeIntervalSinceNow <= TimeInterval(minutes: -4.5) else {
            completion(.noData)
            return
        }

        device.getGlucoseHistoryEvents(since: latestGlucoseDate.addingTimeInterval(TimeInterval(minutes: 1))) { (result) in
            switch result {
            case .success(let events):

                _ = deviceManager.remoteDataManager.nightscoutService.uploader?.processGlucoseEvents(events, source: device.device.deviceURI)

                if let latestSensorEvent = events.flatMap({ $0.glucoseEvent as?  RelativeTimestampedGlucoseEvent }).last {
                    self.sensorState = EnliteSensorDisplayable(latestSensorEvent)
                }

                let unit = HKUnit.milligramsPerDeciliter()
                let glucoseValues = events
                    // TODO: Is the { $0.date > latestGlucoseDate } filter duplicative?
                    .filter({ $0.glucoseEvent is SensorValueGlucoseEvent && $0.date > latestGlucoseDate })
                    .map({ (e:TimestampedGlucoseEvent) -> (quantity: HKQuantity, date: Date, isDisplayOnly: Bool) in
                        let glucoseEvent = e.glucoseEvent as! SensorValueGlucoseEvent
                        let quantity = HKQuantity(unit: unit, doubleValue: Double(glucoseEvent.sgv))
                        return (quantity: quantity, date: e.date, isDisplayOnly: false)
                    })

                completion(.newData(glucoseValues))
            case .failure(let error):
                completion(.error(error))
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

