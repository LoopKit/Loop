//
//  BolusPickerValues.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

struct BolusPickerValues: RandomAccessCollection {
    private var supportedVolumes: [Double]

    init(supportedVolumes: [Double], maxBolus: Double) {
        self.supportedVolumes = Array(supportedVolumes.prefix(while: { $0 <= maxBolus }))
        if self.supportedVolumes.first != 0 {
            self.supportedVolumes.insert(0, at: supportedVolumes.startIndex)
        }
    }

    var startIndex: Int { supportedVolumes.startIndex }
    var endIndex: Int { supportedVolumes.endIndex }

    func index(after i: Int) -> Int { supportedVolumes.index(after: i) }
    func index(before i: Int) -> Int { supportedVolumes.index(before: i) }

    func index(_ i: Int, offsetBy distance: Int, limitedBy limit: Int) -> Int? {
        supportedVolumes.index(i, offsetBy: distance, limitedBy: limit)
    }

    subscript(pickerValue: Int) -> Double {
        supportedVolumes[pickerValue]
    }
}

extension BolusPickerValues {
    func index(of bolusValue: Double) -> Int {
        let indexAfter = supportedVolumes.firstIndex(where: { $0 > bolusValue }) ?? supportedVolumes.endIndex
        guard indexAfter > 0 else { return 0 }
        return supportedVolumes.index(before: indexAfter)
    }

    func incrementing(_ bolusValue: Double, by pickerIncrement: Int) -> Double {
        assert(pickerIncrement >= 0)
        let thisIndex = index(of: bolusValue)
        let targetIndex = index(thisIndex, offsetBy: pickerIncrement, limitedBy: endIndex - 1) ?? endIndex - 1
        return self[targetIndex]
    }

    func decrementing(_ bolusValue: Double, by pickerDecrement: Int) -> Double {
        assert(pickerDecrement >= 0)
        let thisIndex = index(of: bolusValue)
        let targetIndex = index(thisIndex, offsetBy: -pickerDecrement, limitedBy: startIndex) ?? startIndex
        return self[targetIndex]
    }
}

