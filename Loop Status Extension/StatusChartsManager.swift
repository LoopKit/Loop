//
//  StatusChartsManager.swift
//  Loop Status Extension
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopUI
import SwiftCharts
import UIKit

class StatusChartsManager: ChartsManager {
    let predictedGlucose = PredictedGlucoseChart()

    init(colors: ChartColorPalette, settings: ChartSettings, traitCollection: UITraitCollection) {
        super.init(colors: colors, settings: settings, charts: [predictedGlucose], traitCollection: traitCollection)
    }
}
