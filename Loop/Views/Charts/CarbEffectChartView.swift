//
//  CarbEffectChartView.swift
//  Loop
//
//  Created by Noah Brauner on 7/25/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit
import LoopKitUI
import LoopAlgorithm

struct CarbEffectChartView: View {
    let chartManager: ChartsManager
    var glucoseUnit: HKUnit
    var carbAbsorptionReview: CarbAbsorptionReview?
    var dateInterval: DateInterval
    
    @Binding var isInteractingWithChart: Bool
    
    var body: some View {
        LoopChartView<CarbEffectChart>(chartManager: chartManager, dateInterval: dateInterval, isInteractingWithChart: $isInteractingWithChart) { carbEffectChart in
            carbEffectChart.glucoseUnit = glucoseUnit
            if let carbAbsorptionReview {
                carbEffectChart.setCarbEffects(carbAbsorptionReview.carbEffects.filterDateRange(dateInterval.start, dateInterval.end))
                carbEffectChart.setInsulinCounteractionEffects(carbAbsorptionReview.effectsVelocities.filterDateRange(dateInterval.start, dateInterval.end))
            }
        }
    }
}
