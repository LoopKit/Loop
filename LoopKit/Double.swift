//
//  Double.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension Double: RawRepresentable {
    public typealias RawValue = NSNumber

    public init?(rawValue: RawValue) {
        self = rawValue.doubleValue
    }

    public var rawValue: RawValue {
        return NSNumber(double: self)
    }
}
