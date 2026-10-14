//
//  ChartColorPalette+Loop.swift
//  Loop
//
//  Created by Bharat Mediratta on 4/1/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import LoopUI
import LoopKitUI
import UIKit


extension ChartColorPalette {
    static var primary: ChartColorPalette {
        primary(background: .systemBackground)
    }

    static func primary(background: UIColor) -> ChartColorPalette {
        return ChartColorPalette(axisLine: .axisLineColor, axisLabel: .axisLabelColor, grid: .gridColor, presetTint: .presets, glucoseTint: .glucoseTintColor, insulinTint: .insulinTintColor, carbTint: .carbTintColor, background: background)
    }
}
