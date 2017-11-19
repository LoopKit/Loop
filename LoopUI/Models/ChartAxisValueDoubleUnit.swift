//
//  ChartAxisValueDoubleUnit.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/16/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import SwiftCharts


public final class ChartAxisValueDoubleUnit: ChartAxisValueDouble {
    let unitString: String

    public init(_ double: Double, unitString: String, formatter: NumberFormatter) {
        self.unitString = unitString

        super.init(double, formatter: formatter)
    }

    init(_ double: Double, unitString: String) {
        self.unitString = unitString

        super.init(double)
    }

    override public var description: String {
        return formatter.string(from: scalar, unit: unitString) ?? ""
    }
}
