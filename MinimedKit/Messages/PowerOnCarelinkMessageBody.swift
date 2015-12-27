//
//  PowerOnCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class PowerOnCarelinkMessageBody: CarelinkLongMessageBody {

    public convenience init(duration: NSTimeInterval) {

        let sequence = 2
        let on = 1
        let durationMinutes: Int = Int(ceil(duration / 60.0))

        let data = NSData(hexadecimalString: String("%02x%02x%02x", sequence, on, durationMinutes))!

        self.init(rxData: data)!
    }
}