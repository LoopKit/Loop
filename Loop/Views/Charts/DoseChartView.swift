//
//  DoseChartView.swift
//  Loop
//
//  Created by Noah Brauner on 7/22/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopAlgorithm
import LoopKitUI

struct DoseChartView: View {
    let chartManager: ChartsManager
    var doses: [BasalRelativeDose]
    var dateInterval: DateInterval
    
    @Binding var isInteractingWithChart: Bool
    
    var body: some View {
        LoopChartView<LegacyDoseChart>(chartManager: chartManager, dateInterval: dateInterval, isInteractingWithChart: $isInteractingWithChart) { doseChart in
            doseChart.doseEntries = doses.map(\.chartedDose)
        }
    }
}
