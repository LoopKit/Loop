//
//  DiagnosticLogger.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/10/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit


class DiagnosticLogger {
    let APIKey: String
    let APIHost: String
    let APIPath: String

    private lazy var isSimulator: Bool = TARGET_OS_SIMULATOR != 0

    init?() {
        if let
            settingsPath = NSBundle.mainBundle().pathForResource("RemoteSettings", ofType: "plist"),
            settings = NSDictionary(contentsOfFile: settingsPath)
        {
            APIKey = settings["APIKey"] as! String
            APIHost = settings["APIHost"] as! String
            APIPath = settings["APIPath"] as! String
        } else {
            APIKey = ""
            APIHost = ""
            APIPath = ""

            return nil
        }
    }

    func addError(message: String, fromSource source: String) {
        let info = [
            "source": source,
            "message": message,
            "reportedAt": NSDateFormatter.ISO8601StrictDateFormatter().stringFromDate(NSDate())
        ]

        addMessage(info, toCollection: "errors")
    }

    func addError(message: ErrorType, fromSource source: String) {
        addError(String(message), fromSource: source)
    }

    func addLoopStatus(startDate startDate: NSDate, endDate: NSDate, glucose: GlucoseValue, effects: [String: [GlucoseEffect]], error: ErrorType?, prediction: [GlucoseValue], recommendedTempBasal: LoopDataManager.TempBasalRecommendation?) {

        let dateFormatter = NSDateFormatter.ISO8601StrictDateFormatter()
        let unit = HKUnit.milligramsPerDeciliterUnit()

        var message: [String: AnyObject] = [
            "startDate": dateFormatter.stringFromDate(startDate),
            "duration": endDate.timeIntervalSinceDate(startDate),
            "glucose": [
                "startDate": dateFormatter.stringFromDate(glucose.startDate),
                "value": glucose.quantity.doubleValueForUnit(unit),
                "unit": unit.unitString
            ],
            "input": effects.reduce([:], combine: { (previous, item) -> [String: AnyObject] in
                var input = previous
                input[item.0] = item.1.map {
                    [
                        "startDate": dateFormatter.stringFromDate($0.startDate),
                        "value": $0.quantity.doubleValueForUnit(unit),
                        "unit": unit.unitString
                    ]
                }
                return input
            }),
            "prediction": prediction.map({ (value) -> [String: AnyObject] in
                [
                    "startDate": dateFormatter.stringFromDate(value.startDate),
                    "value": value.quantity.doubleValueForUnit(unit),
                    "unit": unit.unitString
                ]
            })
        ]

        if let error = error {
            message["error"] = String(error)
        }

        if let recommendedTempBasal = recommendedTempBasal {
            message["recommendedTempBasal"] = [
                "rate": recommendedTempBasal.rate,
                "minutes": recommendedTempBasal.duration.minutes
            ]
        }

        addMessage(message, toCollection: "loop")
    }

    func addMessage(message: [String: AnyObject], toCollection collection: String) {
        if !isSimulator,
            let messageData = try? NSJSONSerialization.dataWithJSONObject(message, options: []),
            let URL = NSURL(string: APIHost)?.URLByAppendingPathComponent(APIPath).URLByAppendingPathComponent(collection),
            components = NSURLComponents(URL: URL, resolvingAgainstBaseURL: true)
        {
            components.query = "apiKey=\(APIKey)"

            if let URL = components.URL {
                let request = NSMutableURLRequest(URL: URL)

                request.HTTPMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let task = NSURLSession.sharedSession().uploadTaskWithRequest(request, fromData: messageData) { (_, _, error) -> Void in
                    if let error = error {
                        NSLog("%s error: %@", #function, error)
                    }
                }

                task.resume()
            }
        }
    }
}

