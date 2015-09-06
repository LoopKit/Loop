//
//  MySentryPumpStatusMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/5/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


enum GlucoseTrend {
    case Flat
    case Up
    case UpUp
    case Down
    case DownDown
}


/// Describes a status message sent periodically from the pump to any paired MySentry devices
/// See: https://github.com/ps2/minimed_rf/blob/master/lib/minimed_rf/messages/pump_status.rb
/// a2 594040 04 c9 51092c1e0f090401323300037a020205b01830132b00d100000070092b000f09040000 33
public struct MySentryPumpStatusMessageBody: MessageBody {
    private static let length = 36

//    let glucose: Int?
//    let trend: GlucoseTrend

    public init?(rxData: NSData) {
        if rxData.length == self.dynamicType.length {

        } else {
            return nil
        }
    }

    public var txData: NSData {
        return NSData()
    }
}