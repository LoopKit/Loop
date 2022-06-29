//
//  ChartSettings+Loop.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import SwiftCharts

extension ChartSettings {
    static var `default`: ChartSettings {
        var settings = ChartSettings()
        settings.top = 12
        settings.bottom = 0
        settings.trailing = 8
        settings.axisTitleLabelsToLabelsSpacing = 0
        settings.labelsToAxisSpacingX = 6
        settings.clipInnerFrame = false
        return settings
    }
}
