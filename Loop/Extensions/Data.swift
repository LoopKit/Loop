//
//  NSDate.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/27/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension Data {
    var hexadecimalString: String {
        let string = NSMutableString(capacity: count * 2)

        for byte in self {
            string.appendFormat("%02x", byte)
        }

        return string as String
    }
}
