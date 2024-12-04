//
//  GlucoseCarbChartView.swift
//  Loop
//
//  Created by Noah Brauner on 7/29/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopAlgorithm

struct GlucoseCarbChartView: View {
    let chartManager: ChartsManager
    var glucoseUnit: LoopUnit
    var glucoseValues: [GlucoseValue]
    var carbEntries: [StoredCarbEntry]
    var dateInterval: DateInterval
    
    @Binding var isInteractingWithChart: Bool
    
    var body: some View {
        LoopChartView<GlucoseCarbChart>(chartManager: chartManager, dateInterval: dateInterval, isInteractingWithChart: $isInteractingWithChart) { glucoseCarbChart in
            glucoseCarbChart.glucoseUnit = glucoseUnit
            glucoseCarbChart.setGlucoseValues(glucoseValues)
            glucoseCarbChart.carbEntries = carbEntries
            glucoseCarbChart.carbEntryImage = UIImage(named: "carbs")
            glucoseCarbChart.carbEntryFavoriteFoodImage = UIImage(named: "Favorite Foods Icon")
        }
    }
}
