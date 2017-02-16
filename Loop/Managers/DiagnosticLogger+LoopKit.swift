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

    func quantityValue(_ from: GlucoseValue, unit: HKUnit) -> Any {
        let value = from.quantity.doubleValue(for: unit)
        guard !value.isNaN else {
            return "NaN"
        }
        return value
    }

    func quantityValue(_ from: GlucoseEffect, unit: HKUnit) -> Any {
        let value = from.quantity.doubleValue(for: unit)
        guard !value.isNaN else {
            return "NaN"
        }
        return value
    }

    func addLoopStatus(startDate: Date, endDate: Date, glucose: GlucoseValue, effects: [String: [GlucoseEffect]], error: Error?, prediction: [GlucoseValue], predictionWithRetrospectiveEffect: Double, recommendedTempBasal: LoopDataManager.TempBasalRecommendation?) {

        let dateFormatter = DateFormatter.ISO8601StrictDateFormatter()
        let unit = HKUnit.milligramsPerDeciliterUnit()

        var message: [String: Any] = [
            "startDate": dateFormatter.string(from: startDate),
            "duration": endDate.timeIntervalSince(startDate),
            "glucose": [
                "startDate": dateFormatter.string(from: glucose.startDate),
                "value": quantityValue(glucose, unit: unit),
                "unit": unit.unitString
            ],
            "input": effects.reduce([:], { (previous, item) -> [String: Any] in
                var input = previous
                input[item.0] = item.1.map {
                    [
                        "startDate": dateFormatter.string(from: $0.startDate),
                        "value": quantityValue($0, unit: unit),
                        "unit": unit.unitString
                    ]
                }
                return input
            }),
            "prediction": prediction.map { (value) -> [String: Any] in
                [
                    "startDate": dateFormatter.string(from: value.startDate),
                    "value": quantityValue(value, unit: unit),
                    "unit": unit.unitString
                ]
            },
            "prediction_retrospect_delta": predictionWithRetrospectiveEffect.isNaN ? "NaN" : predictionWithRetrospectiveEffect
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
