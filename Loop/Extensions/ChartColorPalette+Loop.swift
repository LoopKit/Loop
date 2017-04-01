//
//  ChartColorPalette+Loop.swift
//  Loop
//
//  Created by Bharat Mediratta on 4/1/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation

import LoopUI

extension ChartColorPalette {
    static var `default`: ChartColorPalette {
        get {
            return ChartColorPalette(axisLine: .axisLineColor, axisLabel: .axisLabelColor, grid: .gridColor, glucoseTint: .glucoseTintColor, doseTint: .doseTintColor)
        }
    }
}
