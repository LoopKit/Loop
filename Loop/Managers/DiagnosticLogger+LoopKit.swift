//
//  DiagnosticLogger+LoopKit.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/25/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


extension DiagnosticLogger {
    func addError(_ message: String, fromSource source: String) {
        let info = [
            "source": source,
            "message": message,
            "reportedAt": DateFormatter.ISO8601StrictDateFormatter().string(from: Date())
        ]

        addMessage(info, toCollection: "errors")
    }

    func addError(_ message: Error, fromSource source: String) {
        addError(String(describing: message), fromSource: source)
    }

    func addLoopStatus(startDate: Date, endDate: Date, glucose: GlucoseValue, effects: [String: [GlucoseEffect]], error: Error?, prediction: [GlucoseValue], predictionWithRetrospectiveEffect: Double, eventualBGWithRetrospectiveEffect: Double, eventualBGWithoutMomentum: Double, recommendedTempBasal: LoopDataManager.TempBasalRecommendation?) {

        let dateFormatter = DateFormatter.ISO8601StrictDateFormatter()
        let unit = HKUnit.milligramsPerDeciliterUnit()

        var message: [String: Any] = [
            "startDate": dateFormatter.string(from: startDate),
            "duration": endDate.timeIntervalSince(startDate),
            "glucose": [
                "startDate": dateFormatter.string(from: glucose.startDate),
                "value": glucose.quantity.doubleValue(for: unit),
                "unit": unit.unitString
            ],
            "input": effects.reduce([:], { (previous, item) -> [String: Any] in
                var input = previous
                input[item.0] = item.1.map {
                    [
                        "startDate": dateFormatter.string(from: $0.startDate),
                        "value": $0.quantity.doubleValue(for: unit),
                        "unit": unit.unitString
                    ]
                }
                return input
            }),
            "prediction": prediction.map { (value) -> [String: Any] in
                [
                    "startDate": dateFormatter.string(from: value.startDate),
                    "value": value.quantity.doubleValue(for: unit),
                    "unit": unit.unitString
                ]
            },
            "prediction_retrospect_delta": predictionWithRetrospectiveEffect,
            "eventualBGWithRetrospectiveEffect": eventualBGWithRetrospectiveEffect,
            "eventualBGWithoutMomentum": eventualBGWithoutMomentum
        ]

        if let error = error {
            message["error"] = String(describing: error)
        }

        if let recommendedTempBasal = recommendedTempBasal {
            message["recommendedTempBasal"] = [
                "rate": recommendedTempBasal.rate,
                "minutes": recommendedTempBasal.duration.minutes
            ]
        }

        addMessage(message, toCollection: "loop")
    }
}
