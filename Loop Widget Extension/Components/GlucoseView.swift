//
//  GlucoseView.swift
//  Loop
//
//  Created by Noah Brauner on 8/15/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit
import LoopCore

struct GlucoseView: View {
    var entry: StatusWidgetTimelimeEntry
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack(spacing: 2) {
                if !entry.glucoseIsStale,
                   let glucoseQuantity = entry.currentGlucose?.quantity,
                   let unit = entry.unit,
                   let glucoseString = NumberFormatter.glucoseFormatter(for: unit).string(from: glucoseQuantity.doubleValue(for: unit)) {
                    Text(glucoseString)
                        .font(.system(size: 24, weight: .heavy, design: .default))
                }
                else {
                    Text("---")
                        .font(.system(size: 24, weight: .heavy, design: .default))
                }
                
                if let trendImageName = getArrowImage() {
                    Image(systemName: trendImageName)
                }
            }
            .foregroundColor(entry.glucoseStatusIsStale ? .staleGray : .primary)
            
            let unitString = entry.unit?.localizedShortUnitString ?? "-"
            if let delta = entry.delta, let unit = entry.unit {
                let deltaValue = delta.doubleValue(for: unit)
                let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
                let deltaString = (deltaValue < 0 ? "-" : "+") + numberFormatter.string(from: abs(deltaValue))!
                
                Text(deltaString + " " + unitString)
                    .font(.footnote)
                    .foregroundColor(entry.glucoseStatusIsStale ? .staleGray : .secondary)
            }
            else {
                Text(unitString)
                    .font(.footnote)
                    .foregroundColor(entry.glucoseStatusIsStale ? .staleGray : .secondary)
            }
        }
    }
    
    private func getArrowImage() -> String? {
        switch entry.sensor?.trendType {
        case .upUpUp:
            return "arrow.double.up.circle"
        case .upUp:
            return "arrow.up.circle"
        case .up:
            return "arrow.up.right.circle"
        case .flat:
            return "arrow.right.circle"
        case .down:
            return "arrow.down.right.circle"
        case .downDown:
            return "arrow.down.circle"
        case .downDownDown:
            return "arrow.double.down.circle"
        case .none:
            return nil
        }
    }
}
