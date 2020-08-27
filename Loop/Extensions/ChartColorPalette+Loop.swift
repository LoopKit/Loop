//
//  ChartColorPalette+Loop.swift
//  Loop
//
//  Created by Bharat Mediratta on 4/1/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopUI
import LoopKitUI


extension ChartColorPalette {
    static var primary: ChartColorPalette {
        return ChartColorPalette(axisLine: .axisLineColor, axisLabel: .axisLabelColor, grid: .gridColor, glucoseTint: .glucoseTintColor, insulinTint: .insulinTintColor)
    }
}
