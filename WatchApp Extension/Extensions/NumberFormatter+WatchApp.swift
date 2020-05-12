//
//  NumberFormatter+WatchApp.swift
//  WatchApp Extension
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//


import Foundation

extension NumberFormatter {
    class var bolus: NumberFormatter {
       let formatter = NumberFormatter()
       formatter.numberStyle = .decimal
       formatter.minimumIntegerDigits = 1

       return formatter
    }

    func string(fromBolusValue bolusValue: Double) -> String {
        let originalMinimumFractionDigits = minimumFractionDigits
        let originalMaximumFractionDigits = maximumFractionDigits
        defer {
            minimumFractionDigits = originalMinimumFractionDigits
            maximumFractionDigits = originalMaximumFractionDigits
        }

        switch bolusValue {
        case let x where x < 1:
            minimumFractionDigits = 3
            maximumFractionDigits = 3
        case let x where x < 10:
            minimumFractionDigits = 2
            maximumFractionDigits = 2
        default:
            minimumFractionDigits = 1
            maximumFractionDigits = 1
        }

        return string(from: bolusValue as NSNumber) ?? "--"
    }
}
