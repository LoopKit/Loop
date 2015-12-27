//
//  Int.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension Int {
    init(bigEndianBytes bytes: [UInt8]) {
        assert(bytes.count <= 4)
        var result: UInt = 0

        for idx in 0..<(bytes.count) {
            let shiftAmount = UInt((bytes.count) - idx - 1) * 8
            result += UInt(bytes[idx]) << shiftAmount
        }

        self.init(result)
    }
}
