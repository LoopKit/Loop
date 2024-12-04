//
//  PredictedGlucoseChartView.swift
//  Loop
//
//  Created by Michael Pangburn on 7/22/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopAlgorithm

struct PredictedGlucoseChartView: View {
    let chartManager: ChartsManager
    var glucoseUnit: LoopUnit
    var glucoseValues: [GlucoseValue]
    var predictedGlucoseValues: [GlucoseValue] = []
    var targetGlucoseSchedule: GlucoseRangeSchedule? = nil
    var preMealOverride: TemporaryScheduleOverride? = nil
    var scheduleOverride: TemporaryScheduleOverride? = nil
    var dateInterval: DateInterval

    @Binding var isInteractingWithChart: Bool
    
    var body: some View {
        LoopChartView<PredictedGlucoseChart>(chartManager: chartManager, dateInterval: dateInterval, isInteractingWithChart: $isInteractingWithChart) { predictedGlucoseChart in
            predictedGlucoseChart.glucoseUnit = glucoseUnit
            predictedGlucoseChart.targetGlucoseSchedule = targetGlucoseSchedule
            predictedGlucoseChart.preMealOverride = preMealOverride
            predictedGlucoseChart.scheduleOverride = scheduleOverride
            predictedGlucoseChart.setGlucoseValues(glucoseValues)
            predictedGlucoseChart.setPredictedGlucoseValues(predictedGlucoseValues)
        }
    }
}
