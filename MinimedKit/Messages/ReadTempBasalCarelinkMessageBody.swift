//
//  ReadTempBasalCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/7/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class ReadTempBasalCarelinkMessageBody: CarelinkLongMessageBody {

    // MMX12 and above
    private static let strokesPerUnit = 40

    public enum RateType {
        case Absolute
        case Percent
    }

    public let timeRemaining: NSTimeInterval
    public let rate: Double
    public let rateType: RateType

    public required init?(rxData: NSData) {
        guard rxData.length == self.dynamicType.length else {
            timeRemaining = 0
            rate = 0
            rateType = .Absolute
            super.init(rxData: rxData)
            return nil
        }

        let rawRateType: UInt8 = rxData[1]
        switch rawRateType {
        case 0:
            rateType = .Absolute
            let strokes = Int(bigEndianBytes: rxData[3...4])
            rate = Double(strokes) / Double(self.dynamicType.strokesPerUnit)
        case 1:
            rateType = .Percent
            let rawRate: UInt8 = rxData[2]
            rate = Double(rawRate)
        default:
            timeRemaining = 0
            rate = 0
            rateType = .Absolute
            super.init(rxData: rxData)
            return nil
        }

        let minutesRemaining = Int(bigEndianBytes: rxData[5...6])
        timeRemaining = NSTimeInterval(minutesRemaining * 60)

        super.init(rxData: rxData)
    }
}