//
//  BolusPickerValues.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

private func pickerValueFromBolusValue(_ bolusValue: Double) -> Int {
    switch bolusValue {
    case let bolus where bolus > 10:
        return Int(((bolus - 10.0) * 10).rounded()) + pickerValueFromBolusValue(10)
    case let bolus where bolus > 1:
        return Int(((bolus - 1.0) * 20).rounded()) + pickerValueFromBolusValue(1)
    default:
        return Int((bolusValue * 40).rounded())
    }
}

private func bolusValueFromPickerValue(_ pickerValue: Int) -> Double {
    switch pickerValue {
    case let picker where picker > 220:
        return Double(picker - 220) / 10.0 + bolusValueFromPickerValue(220)
    case let picker where picker > 40:
        return Double(picker - 40) / 20.0 + bolusValueFromPickerValue(40)
    default:
        return Double(pickerValue) / 40.0
    }
}

struct BolusPickerValues: RandomAccessCollection {
    init(maxBolus: Double) {
        endIndex = pickerValueFromBolusValue(maxBolus) + 1
    }

    var startIndex: Int { 0 }
    let endIndex: Int

    func index(after i: Int) -> Int { i + 1 }
    func index(before i: Int) -> Int { i - 1 }

    subscript(pickerValue: Int) -> Double {
        bolusValueFromPickerValue(pickerValue)
    }
}

extension BolusPickerValues {
    func index(of bolusValue: Double) -> Int {
        pickerValueFromBolusValue(bolusValue)
    }

    func incrementing(_ bolusValue: Double, by pickerIncrement: Int) -> Double {
        assert(pickerIncrement >= 0)
        let thisIndex = index(of: bolusValue)
        let targetIndex = index(thisIndex, offsetBy: pickerIncrement, limitedBy: endIndex) ?? endIndex - 1
        return self[targetIndex]
    }

    func decrementing(_ bolusValue: Double, by pickerDecrement: Int) -> Double {
        assert(pickerDecrement >= 0)
        let thisIndex = index(of: bolusValue)
        let targetIndex = index(thisIndex, offsetBy: -pickerDecrement, limitedBy: startIndex) ?? startIndex
        return self[targetIndex]
    }
}

