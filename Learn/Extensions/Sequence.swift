//
//  Sequence.swift
//  Learn
//
//  Created by Pete Schwamb on 4/10/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

extension Sequence {
    func proportion(where isIncluded: (Element) -> Bool) -> Double? {
        return average(by: { isIncluded($0) ? 1 : 0 })
    }

    func average<T: FloatingPoint>(by getMetric: (Element) -> T) -> T? {
        let (sum, count) = reduce(into: (sum: 0 as T, count: 0)) { result, element in
            result.0 += getMetric(element)
            result.1 += 1
        }

        guard count > 0 else {
            return nil
        }

        return sum / T(count)
    }
}

extension Sequence where Element: FloatingPoint {
    func average() -> Element? {
        return average(by: { $0 })
    }
}
