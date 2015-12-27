//
//  CarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class CarelinkMessageBody: MessageBody {
    public static var length: Int = 65

    let rxData: NSData

    public required init?(rxData: NSData) {
        self.rxData = rxData

        if rxData.length == self.dynamicType.length {
            
        } else {
            return nil
        }
    }

    public var txData: NSData {
        return rxData
    }
}
