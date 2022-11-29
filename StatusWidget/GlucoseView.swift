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

    var entry: StatusWidgetEntry
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack(spacing: 2) {
                if let glucose = entry.currentGlucose,
                   !entry.glucoseIsStale,
                   let unit = entry.unit
                {
                    let quantity = glucose.quantity
                    let glucoseFormatter = NumberFormatter.glucoseFormatter(for: unit)
                    if let glucoseString = glucoseFormatter.string(from: quantity.doubleValue(for: unit)) {
                        Text(glucoseString)
                            .font(.system(size: 24, weight: .heavy, design: .default))
                    }
                    else {
                        Text("??")
                            .font(.system(size: 24, weight: .heavy, design: .default))
                    }
                }
                else {
                    Text("---")
                        .font(.system(size: 24, weight: .heavy, design: .default))
                }
                
                if let trendImageName = getArrowImage() {
                    Image(systemName: trendImageName)
                }
            }
            // Prevent truncation of text
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(entry.glucoseStatusIsStale ? Color(UIColor.systemGray3) : .primary)
            
            let unitString = entry.unit == nil ? "-" : entry.unit!.localizedShortUnitString
            if let delta = entry.delta, let unit = entry.unit {
                let deltaValue = delta.doubleValue(for: unit)
                let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
                let deltaString = (deltaValue < 0 ? "-" : "+") + numberFormatter.string(from: abs(deltaValue))!
                
                Text(deltaString + " " + unitString)
                // Dynamic text causes string to be cut off
                    .font(.system(size: 13))
                    .foregroundColor(entry.glucoseStatusIsStale ? Color(UIColor.systemGray3) : Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: true, vertical: true)
            }
            else {
                Text(unitString)
                    .font(.footnote)
                    .foregroundColor(entry.glucoseStatusIsStale ? Color(UIColor.systemGray3) : Color(UIColor.secondaryLabel))
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
