//
//  MySentryPumpStatusMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/5/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public enum GlucoseTrend {
    case Flat
    case Up
    case UpUp
    case Down
    case DownDown

    init?(byte: UInt8) {
        switch byte & 0b1110 {
        case 0b0000:
            self = .Flat
        case 0b0010:
            self = .Up
        case 0b0100:
            self = .UpUp
        case 0b0110:
            self = .Down
        case 0b1000:
            self = .DownDown
        default:
            return nil
        }
    }
}


private extension Int {
    init(bytes: [UInt8]) {
        assert(bytes.count <= 4)
        var result: UInt = 0

        for idx in 0..<(bytes.count) {
            let shiftAmount = UInt((bytes.count) - idx - 1) * 8
            result += UInt(bytes[idx]) << shiftAmount
        }

        self.init(result)
    }
}


private extension NSDateComponents {
    convenience init(mySentryBytes: [UInt8]) {
        self.init()

        hour = Int(mySentryBytes[0])
        minute = Int(mySentryBytes[1])
        second = Int(mySentryBytes[2])
        year = Int(mySentryBytes[3]) + 2000
        month = Int(mySentryBytes[4])
        day = Int(mySentryBytes[5])

        calendar = NSCalendar.currentCalendar()
    }
}


/**
Describes a status message sent periodically from the pump to any paired MySentry devices

See: [MinimedRF Class](https://github.com/ps2/minimed_rf/blob/master/lib/minimed_rf/messages/pump_status.rb)
```
-- ------ -- 00 01 020304050607 08 09 10 11 1213 14 15 16 17 18 19 20 21 2223 24 25 26 27 282930313233 3435 --
             se tr    pump date 01 bh ph 00 resv bt          st sr        iob bl             sens date 0000
a2 594040 04 c9 51 092c1e0f0904 01 32 33 00 037a 02 02 05 b0 18 30 13 2b 00d1 00 00 00 70 092b000f0904 0000 33
```
*/
public struct MySentryPumpStatusMessageBody: MessageBody {
    private static let reservoirSignificantDigit = 0.1
    private static let iobSigificantDigit = 0.025
    public static let length = 36

    let pumpDate: NSDate
    let glucoseDate: NSDate
    let glucose: Int?
    let lastGlucose: Int?
    let reservoirRemaining: Double
    let iob: Double
    public let trend: GlucoseTrend

    public init?(rxData: NSData) {
        if rxData.length == self.dynamicType.length,
            let
            trend = GlucoseTrend(byte: rxData[1]),
            pumpDate = NSDateComponents(mySentryBytes: rxData[2...7]).date,
            glucoseDate = NSDateComponents(mySentryBytes: rxData[33...38]).date
        {
            self.trend = trend
            self.pumpDate = pumpDate
            self.glucoseDate = glucoseDate

            self.glucose = Int(bytes: [rxData[24] & 0b00000001, rxData[9]])
            self.lastGlucose = Int(bytes: [(rxData[24] & 0b00000010) >> 1, rxData[10]])

            self.reservoirRemaining = Double(Int(bytes: rxData[12...13])) * self.dynamicType.reservoirSignificantDigit
            self.iob = Double(Int(bytes: rxData[22...23])) * self.dynamicType.iobSigificantDigit
        } else {
            return nil
        }
    }

    public var txData: NSData {
        return NSData()
    }
}
