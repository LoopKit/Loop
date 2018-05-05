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
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
