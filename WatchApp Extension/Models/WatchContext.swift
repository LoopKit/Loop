//
//  WatchContext.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 11/25/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


class WatchContext: NSObject, NSSecureCoding, RawRepresentable {
    typealias RawValue = [String: AnyObject]

    let version = 1
    var glucoseValue: Int?
    var glucoseTrend: Int?
    var glucoseDate: NSDate?
    var IOB: Double?
    var reservoir: Double?
    var pumpDate: NSDate?

    override init() {
        super.init()
    }

    required init?(rawValue: RawValue) {
        super.init()

        if rawValue["v"] as? Int == version {
            glucoseValue = rawValue["gv"] as? Int
            glucoseTrend = rawValue["gt"] as? Int
            glucoseDate = rawValue["gd"] as? NSDate
            IOB = rawValue["iob"] as? Double
            reservoir = rawValue["r"] as? Double
            pumpDate = rawValue["pd"] as? NSDate
        } else {
            return nil
        }
    }

    required convenience init?(coder: NSCoder) {
        if let rawValue = coder.decodeObjectOfClass(NSDictionary.self, forKey: "rawValue") as? [String: AnyObject] {
            self.init(rawValue: rawValue)
        } else {
            return nil
        }
    }

    func encodeWithCoder(coder: NSCoder) {
        coder.encodeObject(rawValue, forKey: "rawValue")
    }

    static func supportsSecureCoding() -> Bool {
        return true
    }

    var rawValue: RawValue {
        var raw: [String: AnyObject] = [
            "v": version
        ]

        raw["gv"] = glucoseValue
        raw["gt"] = glucoseTrend
        raw["gd"] = glucoseDate
        raw["iob"] = IOB
        raw["r"] = reservoir
        raw["pd"] = pumpDate

        return raw
    }
}