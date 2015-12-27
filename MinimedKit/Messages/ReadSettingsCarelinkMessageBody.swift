//
//  ReadSettingsCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public enum BasalProfile {

    case Standard
    case ProfileA
    case ProfileB

    init(rawValue: UInt8) {
        switch rawValue {
        case 1:
            self = .ProfileA
        case 2:
            self = .ProfileB
        default:
            self = .Standard
        }
    }
}


/**
 Describes the response to the Read Settings command from the pump

 See: [Decocare Class](https://github.com/bewest/decoding-carelink/blob/master/decocare/commands.py#L1223)
 ```
 -- ------ -- 00 01 02 03 04 05 06 07 0809 10 11 12 13141516171819 20 21 2223 24 25 26 27 282930313233 343536 --
 a7 594040 c0 19 00 01 00 01 01 00 96 008c 00 00 00 00000064010400 14 00 1901 01 01 00 00 000000000000 000000 00000000000000000000000000000000000000000000000000000000 e9
 ```
 */
public class ReadSettingsCarelinkMessageBody: CarelinkLongMessageBody {
    private static let maxBolusSignificantDigit = 0.1
    private static let maxBasalSignificantDigit = 0.025

    public let maxBasal: Double
    public let maxBolus: Double

    public let insulinActionCurveHours: Int

    public let selectedBasalProfile: BasalProfile

    public required init?(rxData: NSData) {
        let maxBolusTicks: UInt8 = rxData[7]
        maxBolus = Double(maxBolusTicks) * self.dynamicType.maxBolusSignificantDigit

        let maxBasalTicks: Int = Int(bigEndianBytes: rxData[8...9])
        maxBasal = Double(maxBasalTicks) * self.dynamicType.maxBasalSignificantDigit

        let rawSelectedBasalProfile: UInt8 = rxData[12]
        selectedBasalProfile = BasalProfile(rawValue: rawSelectedBasalProfile)

        let rawInsulinActionCurveHours: UInt8 = rxData[18]
        insulinActionCurveHours = Int(rawInsulinActionCurveHours)

        super.init(rxData: rxData)
    }
}


extension ReadSettingsCarelinkMessageBody: DictionaryRepresentable {
    public var dictionaryRepresentation: [String: AnyObject] {
        return [:]
    }
}
