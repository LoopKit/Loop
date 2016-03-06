//
//  NSData.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/2/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public extension NSData {
    @nonobjc subscript(index: Int) -> Int8 {
        let bytes: [Int8] = self[index...index]

        return bytes[0]
    }

    @nonobjc subscript(index: Int) -> UInt8 {
        let bytes: [UInt8] = self[index...index]

        return bytes[0]
    }

    @nonobjc subscript(range: Range<Int>) -> UInt16 {
        return self[range][0]
    }

    @nonobjc subscript(range: Range<Int>) -> UInt32 {
        return self[range][0]
    }

    subscript(range: Range<Int>) -> [Int8] {
        var dataArray = [Int8](count: range.count, repeatedValue: 0)
        self.getBytes(&dataArray, range: NSRange(range))

        return dataArray
    }

    subscript(range: Range<Int>) -> [UInt8] {
        var dataArray = [UInt8](count: range.count, repeatedValue: 0)
        self.getBytes(&dataArray, range: NSRange(range))

        return dataArray
    }

    subscript(range: Range<Int>) -> [UInt16] {
        var dataArray = [UInt16](count: range.count / 2, repeatedValue: 0)
        self.getBytes(&dataArray, range: NSRange(range))

        return dataArray
    }

    subscript(range: Range<Int>) -> [UInt32] {
        var dataArray = [UInt32](count: range.count / 4, repeatedValue: 0)
        self.getBytes(&dataArray, range: NSRange(range))

        return dataArray
    }

    subscript(range: Range<Int>) -> NSData {
        return subdataWithRange(NSRange(range))
    }

    convenience init?(hexadecimalString: String) {
        if let
            chars = hexadecimalString.cStringUsingEncoding(NSUTF8StringEncoding),
            mutableData = NSMutableData(capacity: chars.count / 2)
        {
            for i in 0..<chars.count / 2 {
                var num: UInt8 = 0
                var multi: UInt8 = 16

                for j in 0..<2 {
                    let c = chars[i * 2 + j]
                    var offset: UInt8

                    switch c {
                    case 48...57:   // '0'-'9'
                        offset = 48
                    case 65...70:   // 'A'-'F'
                        offset = 65 - 10         // 10 since 'A' is 10, not 0
                    case 97...102:  // 'a'-'f'
                        offset = 97 - 10         // 10 since 'a' is 10, not 0
                    default:
                        return nil
                    }

                    num += (UInt8(c) - offset) * multi
                    multi = 1
                }
                mutableData.appendBytes(&num, length: 1)
            }

            self.init(data: mutableData)
        } else {
            return nil
        }
    }

    var hexadecimalString: String {
        let bytesCollection = UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(bytes), count: length)

        let string = NSMutableString(capacity: length * 2)
        
        for byte in bytesCollection {
            string.appendFormat("%02x", byte)
        }
        
        return string as String
    }
}
