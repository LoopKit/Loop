//
//  StatusChartsManager.swift
//  Loop Status Extension
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopUI
import SwiftCharts

class StatusChartsManager: ChartsManager {
    let predictedGlucose = PredictedGlucoseChart()

    init(colors: ChartColorPalette, settings: ChartSettings) {
        super.init(colors: colors, settings: settings, charts: [predictedGlucose])
    }
}
