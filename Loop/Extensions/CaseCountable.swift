//
//  CaseCountable.swift
//  Loop
//
//  Created by Pete Schwamb on 1/1/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

protocol CaseCountable: RawRepresentable {}

extension CaseCountable where RawValue: Integer {
    static var count: Int {
        var i: RawValue = 0
        while let new = Self(rawValue: i) { i = new.rawValue.advanced(by: 1) }
        return Int(i.toIntMax())
    }
}
