//
//  ChartAxisValueDoubleLog.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import SwiftCharts


class ChartAxisValueDoubleLog: ChartAxisValueDoubleScreenLoc {

    init(actualDouble: Double, formatter: NSNumberFormatter, labelSettings: ChartLabelSettings = ChartLabelSettings()) {
        let screenLocDouble: Double

        switch actualDouble {
        case let x where x < 0:
            screenLocDouble = -log(-x + 1)
        case let x where x > 0:
            screenLocDouble = log(x + 1)
        default:  // 0
            screenLocDouble = 0
        }

        super.init(screenLocDouble: screenLocDouble, actualDouble: actualDouble, formatter: formatter, labelSettings: labelSettings)
    }

    init(screenLocDouble: Double, formatter: NSNumberFormatter, labelSettings: ChartLabelSettings = ChartLabelSettings()) {
        let actualDouble: Double

        switch screenLocDouble {
        case let x where x < 0:
            actualDouble = -pow(M_E, -x) + 1
        case let x where x > 0:
            actualDouble = pow(M_E, x) - 1
        default:  // 0
            actualDouble = 0
        }

        super.init(screenLocDouble: screenLocDouble, actualDouble: actualDouble, formatter: formatter, labelSettings: labelSettings)
    }

}
