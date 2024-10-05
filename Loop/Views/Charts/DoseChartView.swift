//
//  DoseChartView.swift
//  Loop
//
//  Created by Noah Brauner on 7/22/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopAlgorithm

struct DoseChartView: View {
    let chartManager: ChartsManager
    var doses: [BasalRelativeDose]
    var dateInterval: DateInterval
    
    @Binding var isInteractingWithChart: Bool
    
    var body: some View {
        LoopChartView<DoseChart>(chartManager: chartManager, dateInterval: dateInterval, isInteractingWithChart: $isInteractingWithChart) { doseChart in
            doseChart.doseEntries = doses
        }
    }
}
