//
//  CarbEntryUserInfo.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


public struct CarbEntryUserInfo {
    public let carbEntry: NewCarbEntry

    public init(carbEntry: NewCarbEntry) {
        self.carbEntry = carbEntry
    }
}


extension CarbEntryUserInfo: RawRepresentable {
    public typealias RawValue = [String: Any]

    static let version = 2
    public static let name = "CarbEntryUserInfo"

    public init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == type(of: self).version && rawValue["name"] as? String == CarbEntryUserInfo.name,
            let value = rawValue["ce"] as? NewCarbEntry.RawValue,
            let carbEntry = NewCarbEntry(rawValue: value)
        else {
            return nil
        }

        self.carbEntry = carbEntry
    }

    public var rawValue: RawValue {
        return [
            "v": type(of: self).version,
            "name": CarbEntryUserInfo.name,
            "ce": carbEntry.rawValue,
        ]
    }
}
