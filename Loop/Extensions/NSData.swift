//
//  NSData.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension NSData {
    @nonobjc subscript(index: Int) -> UInt8 {
        let bytes: [UInt8] = self[index...index]

        return bytes[0]
    }

    subscript(range: Range<Int>) -> [UInt8] {
        var dataArray = [UInt8](count: range.count, repeatedValue: 0)
        self.getBytes(&dataArray, range: NSRange(range))

        return dataArray
    }

    subscript(range: Range<Int>) -> NSData {
        return subdataWithRange(NSRange(range))
    }
}
