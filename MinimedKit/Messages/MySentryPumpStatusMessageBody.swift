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


public enum SensorReading {
    case Off
    case MeterBGNow
    case WeakSignal
    case CalError
    case Warmup
    case Ended
    case HighBG  // Above 400 mg/dL
    case Lost
    case Unknown
    case Active(glucose: Int)

    init(glucose: Int) {
        switch glucose {
        case 0:
            self = .Off
        case 2:
            self = .MeterBGNow
        case 4:
            self = .WeakSignal
        case 6:
            self = .CalError
        case 8:
            self = .Warmup
        case 10:
            self = .Ended
        case 14:
            self = .HighBG
        case 20:
            self = .Lost
        case 0...20:
            self = .Unknown
        default:
            self = .Active(glucose: glucose)
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
             se tr    pump date 01 bh ph    resv bt          st sr        iob bl             sens date 0000
a2 594040 04 c9 51 092c1e0f0904 01 32 33 00 037a 02 02 05 b0 18 30 13 2b 00d1 00 00 00 70 092b000f0904 0000 33
a2 594040 04 fb 51 1205000f0906 01 05 05 02 0000 04 00 00 00 ff 00 ff ff 0040 00 00 00 71 1205000f0906 0000 2b
a2 594040 04 ff 50 1219000f0906 01 00 00 00 0000 04 00 00 00 00 00 00 00 005e 00 00 00 72 000000000000 0000 8b
a2 594040 04 01 50 1223000f0906 01 00 00 00 0000 04 00 00 00 00 00 00 00 0059 00 00 00 72 000000000000 0000 9f
a2 594040 04 2f 51 1727070f0905 01 84 85 00 00cd 01 01 05 b0 3e 0a 0a 1a 009d 03 00 00 71 1726000f0905 0000 d0
a2 594040 04 9c 51 0003310f0905 01 39 37 00 025b 01 01 06 8d 26 22 08 15 0034 00 00 00 70 0003000f0905 0000 67
a2 594040 04 87 51 0f18150f0907 01 03 71 00 045e 04 02 07 2c 04 44 ff ff 005e 02 00 00 73 0f16000f0907 0000 35
```
*/
public struct MySentryPumpStatusMessageBody: MessageBody {
    private static let reservoirSignificantDigit = 0.1
    private static let iobSigificantDigit = 0.025
    public static let length = 36

    public let pumpDate: NSDate
    public let reservoirRemaining: Double
    public let iob: Double

    public let glucoseTrend: GlucoseTrend
    public let glucoseDate: NSDate?
    public let glucose: SensorReading
    let previousGlucose: SensorReading
//    let sensorAgeHours: Int
//    let sensorRemainingHours: Int

    public init?(rxData: NSData) {
        if rxData.length == self.dynamicType.length,
            let
            trend = GlucoseTrend(byte: rxData[1]),
            pumpDate = NSDateComponents(mySentryBytes: rxData[2...7]).date
        {
            self.glucoseTrend = trend
            self.pumpDate = pumpDate

            reservoirRemaining = Double(Int(bytes: rxData[12...13])) * self.dynamicType.reservoirSignificantDigit
            iob = Double(Int(bytes: rxData[22...23])) * self.dynamicType.iobSigificantDigit

            let glucoseValue = Int(bytes: [rxData[9], rxData[24] << 7]) >> 7
            let previousGlucoseValue = Int(bytes: [rxData[10], rxData[24] << 6]) >> 7

            glucose = SensorReading(glucose: glucoseValue)
            previousGlucose = SensorReading(glucose: previousGlucoseValue)

            switch glucose {
            case .Off:
                glucoseDate = nil
            default:
                glucoseDate = NSDateComponents(mySentryBytes: rxData[28...33]).date
            }

        } else {
            return nil
        }
    }

    public var txData: NSData {
        return NSData()
    }
}

extension MySentryPumpStatusMessageBody: Equatable {
}

public func ==(lhs: MySentryPumpStatusMessageBody, rhs: MySentryPumpStatusMessageBody) -> Bool {
    return lhs.pumpDate == rhs.pumpDate && lhs.glucoseDate == rhs.glucoseDate
}

