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


/**
Describes a status message sent periodically from the pump to any paired MySentry devices

See: [MinimedRF Class](https://github.com/ps2/minimed_rf/blob/master/lib/minimed_rf/messages/pump_status.rb)
```
-- ------ -- 00 01 020304050607 08 09 10 11 1213 14 15 16 17 18 19 20 21 2223 24 25 26 27 282930313233 3435 --
             se tr    pump date 01 bh ph    resv bt          st sr nxcal  iob bl             sens date 0000
a2 594040 04 c9 51 092c1e0f0904 01 32 33 00 037a 02 02 05 b0 18 30 13 2b 00d1 00 00 00 70 092b000f0904 0000 33
a2 594040 04 fb 51 1205000f0906 01 05 05 02 0000 04 00 00 00 ff 00 ff ff 0040 00 00 00 71 1205000f0906 0000 2b
a2 594040 04 ff 50 1219000f0906 01 00 00 00 0000 04 00 00 00 00 00 00 00 005e 00 00 00 72 000000000000 0000 8b
a2 594040 04 01 50 1223000f0906 01 00 00 00 0000 04 00 00 00 00 00 00 00 0059 00 00 00 72 000000000000 0000 9f
a2 594040 04 2f 51 1727070f0905 01 84 85 00 00cd 01 01 05 b0 3e 0a 0a 1a 009d 03 00 00 71 1726000f0905 0000 d0
a2 594040 04 9c 51 0003310f0905 01 39 37 00 025b 01 01 06 8d 26 22 08 15 0034 00 00 00 70 0003000f0905 0000 67
a2 594040 04 87 51 0f18150f0907 01 03 71 00 045e 04 02 07 2c 04 44 ff ff 005e 02 00 00 73 0f16000f0907 0000 35
```
*/
public struct MySentryPumpStatusMessageBody: MessageBody, DictionaryRepresentable {
    private static let reservoirSignificantDigit = 0.1
    private static let iobSigificantDigit = 0.025
    public static let length = 36

    public let pumpDateComponents: NSDateComponents
    public let batteryRemainingPercent: Int
    public let iob: Double
    public let reservoirRemainingUnits: Double
    public let reservoirRemainingPercent: Int
    public let reservoirRemainingMinutes: Int

    public let glucoseTrend: GlucoseTrend
    public let glucoseDateComponents: NSDateComponents?
    public let glucose: SensorReading
    public let previousGlucose: SensorReading
    public let sensorAgeHours: Int
    public let sensorRemainingHours: Int

    public let nextSensorCalibrationDateComponents: NSDateComponents?

    private let rxData: NSData

    public init?(rxData: NSData) {
        guard rxData.length == self.dynamicType.length, let trend = GlucoseTrend(byte: rxData[1]) else {
            return nil
        }

        self.rxData = rxData

        let pumpDateComponents = NSDateComponents(mySentryBytes: rxData[2...7])

        guard let calendar = pumpDateComponents.calendar where pumpDateComponents.isValidDateInCalendar(calendar) else {
            return nil
        }

        self.pumpDateComponents = pumpDateComponents

        self.glucoseTrend = trend

        reservoirRemainingUnits = Double(Int(bigEndianBytes: rxData[12...13])) * self.dynamicType.reservoirSignificantDigit

        let reservoirRemainingPercent: UInt8 = rxData[15]
        self.reservoirRemainingPercent = Int(round(Double(reservoirRemainingPercent) / 4.0 * 100))

        reservoirRemainingMinutes = Int(bigEndianBytes: [rxData[16], rxData[17]])

        iob = Double(Int(bigEndianBytes: rxData[22...23])) * self.dynamicType.iobSigificantDigit

        let batteryRemainingPercent: UInt8 = rxData[14]
        self.batteryRemainingPercent = Int(round(Double(batteryRemainingPercent) / 4.0 * 100))

        let glucoseValue = Int(bigEndianBytes: [rxData[9], rxData[24] << 7]) >> 7
        let previousGlucoseValue = Int(bigEndianBytes: [rxData[10], rxData[24] << 6]) >> 7

        glucose = SensorReading(glucose: glucoseValue)
        previousGlucose = SensorReading(glucose: previousGlucoseValue)

        switch glucose {
        case .Off:
            glucoseDateComponents = nil
        default:
            let glucoseDateComponents = NSDateComponents(mySentryBytes: rxData[28...33])

            if glucoseDateComponents.isValidDateInCalendar(calendar) {
                self.glucoseDateComponents = glucoseDateComponents
            } else {
                self.glucoseDateComponents = nil
            }
        }

        let sensorAgeHours: UInt8 = rxData[18]
        self.sensorAgeHours = Int(sensorAgeHours)

        let sensorRemainingHours: UInt8 = rxData[19]
        self.sensorRemainingHours = Int(sensorRemainingHours)

        let matchingHour: UInt8 = rxData[20]
        nextSensorCalibrationDateComponents = NSDateComponents()
        nextSensorCalibrationDateComponents?.hour = Int(matchingHour)
        nextSensorCalibrationDateComponents?.minute = Int(rxData[21] as UInt8)
        nextSensorCalibrationDateComponents?.calendar = calendar
    }

    public var dictionaryRepresentation: [String: AnyObject] {
        let dateComponentsString = { (components: NSDateComponents) -> String in
            String(
                format: "%04d-%02d-%02dT%02d:%02d:%02d",
                components.year,
                components.month,
                components.day,
                components.hour,
                components.minute,
                components.second
            )
        }

        var dict: [String: AnyObject] = [
            "glucoseTrend": String(glucoseTrend),
            "pumpDate": dateComponentsString(pumpDateComponents),
            "reservoirRemaining": reservoirRemainingUnits,
            "reservoirRemainingPercent": reservoirRemainingPercent,
            "reservoirRemainingMinutes": reservoirRemainingMinutes,
            "iob": iob
        ]

        switch glucose {
        case .Active(glucose: let glucose):
            dict["glucose"] = glucose
        default:
            break
        }

        if let glucoseDateComponents = glucoseDateComponents {
            dict["glucoseDate"] = dateComponentsString(glucoseDateComponents)
        }
        dict["sensorStatus"] = String(glucose)

        switch previousGlucose {
        case .Active(glucose: let glucose):
            dict["lastGlucose"] = glucose
        default:
            break
        }
        dict["lastSensorStatus"] = String(previousGlucose)

        dict["sensorAgeHours"] = sensorAgeHours
        dict["sensorRemainingHours"] = sensorRemainingHours
        if let components = nextSensorCalibrationDateComponents {
            dict["nextSensorCalibration"] = String(format: "%02d:%02d", components.hour, components.minute)
        }

        dict["batteryRemainingPercent"] = batteryRemainingPercent

        dict["byte1"] = rxData.subdataWithRange(NSRange(1...1)).hexadecimalString
        // {50}
        let byte1: UInt8 = rxData[1]
        dict["byte1High"] = String(format: "%02x", byte1 & 0b11110000)
        // {1}
        dict["byte1Low"] = Int(byte1 & 0b00000001)
        // Observed values: 00, 01, 02, 03
        // These seem to correspond with carb/bolus activity
        dict["byte11"] = rxData.subdataWithRange(NSRange(11...11)).hexadecimalString
        // Current alarms?
        // 25: {00,52,65} 4:49 AM - 4:59 AM
        // 26: 00
        dict["byte2526"] = rxData.subdataWithRange(NSRange(25...26)).hexadecimalString
        // 27: {73}
        dict["byte27"] = rxData.subdataWithRange(NSRange(27...27)).hexadecimalString

        return dict
    }

    public var txData: NSData {
        return rxData
    }
}

extension MySentryPumpStatusMessageBody: Equatable {
}

public func ==(lhs: MySentryPumpStatusMessageBody, rhs: MySentryPumpStatusMessageBody) -> Bool {
    return lhs.pumpDateComponents == rhs.pumpDateComponents && lhs.glucoseDateComponents == rhs.glucoseDateComponents
}

