//
//  IOBChartView.swift
//  Loop
//
//  Created by Noah Brauner on 7/22/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopAlgorithm

struct IOBChartView: View {
    let chartManager: ChartsManager
    var iobValues: [InsulinValue]
    var dateInterval: DateInterval
    
    @Binding var isInteractingWithChart: Bool

    var body: some View {
        LoopChartView<IOBChart>(chartManager: chartManager, dateInterval: dateInterval, isInteractingWithChart: $isInteractingWithChart) { iobChart in
            iobChart.setIOBValues(iobValues)
        }
    }
}
