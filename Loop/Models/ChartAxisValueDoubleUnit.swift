//
//  ChartAxisValueDoubleUnit.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/16/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import SwiftCharts


final class ChartAxisValueDoubleUnit: ChartAxisValueDouble {
    let unitString: String

    init(_ double: Double, unitString: String, formatter: NSNumberFormatter) {
        self.unitString = unitString

        super.init(double, formatter: formatter)
    }

    init(_ double: Double, unitString: String) {
        self.unitString = unitString

        super.init(double)
    }

    override var description: String {
        return "\(super.description) \(unitString)"
    }
}
