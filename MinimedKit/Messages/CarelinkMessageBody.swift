//
//  CarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class CarelinkLongMessageBody: MessageBody {
    public static var length: Int = 65

    let rxData: NSData

    public required init?(rxData: NSData) {
        let data: NSMutableData = rxData.mutableCopy() as! NSMutableData

        if data.length < self.dynamicType.length {
            data.increaseLengthBy(self.dynamicType.length - data.length)
        }

        self.rxData = data
    }

    public var txData: NSData {
        return rxData
    }
}


public class CarelinkShortMessageBody: MessageBody {
    public static var length: Int = 1

    let data: NSData

    public convenience init() {
        self.init(rxData: NSData(hexadecimalString: "00")!)!
    }

    public required init?(rxData: NSData) {
        self.data = rxData

        if rxData.length != self.dynamicType.length {
            return nil
        }
    }

    public var txData: NSData {
        return data
    }
}